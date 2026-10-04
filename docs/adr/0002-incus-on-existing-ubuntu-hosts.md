# 0002. Incus on the existing Ubuntu hosts instead of Proxmox

- Status: accepted
- Date: 2026-10-03
- Supersedes: [0001](0001-proxmox-terraform-talos.md) (hypervisor layer only; Terraform + Talos stay)
- Amended by: [0004](0004-always-on-node-pool-on-the-home-server.md) (control-plane placement)

## Context

All three machines already run Ubuntu Server with services that must keep
running:

| Host  | CPU            | RAM   | Existing services                                   | Availability               |
|-------|----------------|-------|-----------------------------------------------------|----------------------------|
| home  | i5-7500 4C/4T  | 20 GB | Immich (Docker), file sharing, torrent, game server | Always on                  |
| lab-1 | i5-7500 4C/4T  | 64 GB | Ollama, game server                                 | Powered on for experiments |
| lab-2 | i5-7400 4C/4T  | 16 GB | None                                                | Powered on for experiments |

Proxmox VE installs only from its own ISO or on top of Debian, so ADR 0001
means reinstalling the hosts and moving these services. The machines run
headless, and installation and operation must be fully remote: no monitor, no
installer media, no console access.

ADR 0001 also left etcd unable to survive the loss of the 64 GB host, which held
2 of the 3 control-plane nodes.

## Options considered

- **Proxmox VE (ADR 0001)**: well-known UI, clustering, backup tooling. Requires
  wiping every host and an ISO install at the console. Rejected on that basis.
- **Proxmox on a second disk, existing Ubuntu imported as a VM**: keeps the data,
  but needs a new disk per host, an installer at the console, and turns the
  personal services into guests.
- **libvirt/KVM + a libvirt Terraform provider**: lowest layer, same QEMU/KVM
  underneath. Networks, storage pools and boot media are wired by hand in
  Terraform, with no container support for side workloads.
- **Kubernetes directly on the hosts (k3s/kubeadm)**: no hypervisor overhead, but
  each host becomes one node (the 64 GB one oversized), Kubernetes shares the
  OS with Immich, and node failure tests would hit personal services.
- **Incus on the existing Ubuntu**: installed from packages over SSH. It has a
  REST API over HTTPS, runs both VMs and system containers, and supports
  snapshots, resource limits and an optional web UI. The Incus project maintains
  its own Terraform provider (`lxc/incus`). It is less widely known than Proxmox.

## Decision

Incus runs on all three hosts as **standalone servers, not as an Incus cluster**.
An Incus cluster keeps its database on Raft and would lose quorum whenever the
two lab hosts are off, which would also block the home server's API. Terraform
registers each host as an Incus remote. `lxc/incus` creates the VMs, and
`siderolabs/talos` bootstraps Kubernetes on them. Each host's NIC is in a Linux
bridge, so VMs get LAN addresses and can reach each other across hosts.

Kubernetes: 3 control-plane nodes, one per host, and 4 workers (2 on lab-1, 1 on
lab-2, 1 on home). Ansible, Terraform, `talosctl` and `kubectl` run from a
workstation. The home server is the always-on point: it sends Wake-on-LAN to
power the lab hosts on, also when the workstation is remote. Its
VMs are capped at 2 vCPUs each and 10 GB of RAM in total, which leaves headroom
for its own services.

Ollama stays a systemd service on lab-1's host OS, started on demand and capped
with `MemoryMax`.

## Consequences

- No host is reinstalled. Incus comes from packages and everything after that
  goes through its API, so no physical access is needed.
- etcd survives the loss of any one host, which ADR 0001 could not.
  With the lab hosts off, the home server's control-plane node alone has no
  quorum and the cluster is down by design. The home server's VMs are stopped
  together with the lab to return their RAM to it.
- The home server is now part of the platform. Failure tests target its VMs,
  never the host. etcd is sensitive to fsync latency, so the VM disks go on
  NVMe, not on the HDDs that hold the media library.
- Docker (installed on every host by Ansible) loads `br_netfilter` and sets the
  iptables `FORWARD` policy to `DROP`, which drops traffic between bridged VMs.
  Every host needs a `DOCKER-USER` rule that accepts traffic on the LAN bridge.
- Moving a NIC into a bridge over SSH can cut off the session. The netplan change
  is applied with `netplan try`, which reverts unless confirmed. The bridge keeps
  the NIC's MAC address, so the router's DHCP reservation still matches.
- Storage pools use the `dir` driver on the existing ext4 filesystems, so no disk
  is repartitioned and instance snapshots are full copies. Nodes are rebuilt from git,
  not restored from snapshots.
- Incus VMs default to UEFI Secure Boot. Talos nodes either boot the Talos
  SecureBoot image or set `security.secureboot=false`.
- The host OS is mutable Ubuntu with personal services on it. The Kubernetes
  nodes are still Talos: immutable and API-managed.
- Ollama on the host shares lab-1's RAM with the VMs without a hypervisor
  boundary. `MemoryMax` is the only cap, and large models still need worker VMs
  stopped first.
- Lost compared to Proxmox: built-in web UI, live migration and Proxmox Backup
  Server. None of these were planned to be used.
