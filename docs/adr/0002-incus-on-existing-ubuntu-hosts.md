# 0002. Incus on the existing Ubuntu hosts instead of Proxmox

- Status: accepted
- Date: 2026-10-03
- Supersedes: [0001](0001-proxmox-terraform-talos.md) (hypervisor layer only; Terraform + Talos stay)

## Context

All three machines already run Ubuntu Server with services that must keep
running:

| Host  | RAM   | Existing services                    | Availability                |
|-------|-------|--------------------------------------|-----------------------------|
| home  | 16 GB | Immich, torrent                      | Always on                   |
| lab-1 | 64 GB | Immich backup server, Ollama         | Powered on for experiments  |
| lab-2 | 16 GB | None                                 | Powered on for experiments  |

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

Kubernetes: 3 control-plane nodes, one per host, and 3 workers (2 on lab-1, 1 on
lab-2). The home server is the management point. It runs Terraform, `talosctl`
and `kubectl`, and sends Wake-on-LAN to power the lab hosts on. It hosts only a
control-plane VM, with hard CPU and RAM limits and the default control-plane
`NoSchedule` taint, and no data workloads.

Ollama stays a systemd service on lab-1's host OS, started on demand and capped
with `MemoryMax`.

## Consequences

- No host is reinstalled. Incus comes from packages and everything after that
  goes through its API, so no physical access is needed.
- etcd survives the loss of any one host, which ADR 0001 could not.
  With the lab hosts off, the home server's control-plane node alone has no
  quorum and the cluster is down by design. It is stopped together with the lab
  to return its RAM to the home server.
- The home server is now part of the platform. Failure tests target the
  control-plane VM, never the host. etcd is sensitive to fsync latency, so
  the VM disk must not share a slow disk with Immich's library.
- Docker (Immich on home and lab-1) loads `br_netfilter` and sets the iptables
  `FORWARD` policy to `DROP`, which drops traffic between bridged VMs. Each such
  host needs a `DOCKER-USER` rule that accepts traffic on the LAN bridge.
- Moving a NIC into a bridge over SSH can cut off the session. The netplan change
  is applied with `netplan try`, which reverts unless confirmed.
- Without a free disk, storage pools use the `dir` driver on the existing
  filesystems, so instance snapshots are full copies. Nodes are rebuilt from git,
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
