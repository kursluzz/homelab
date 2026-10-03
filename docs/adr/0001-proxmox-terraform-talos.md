# 0001. Proxmox + Terraform + Talos as the base layer

- Status: superseded by [0002](0002-incus-on-existing-ubuntu-hosts.md)
- Date: 2026-09-30

## Context

Two machines are available for the lab, with uneven RAM (64 and 16 GB). A
third, always-on home server (16 GB) runs personal services and must stay
out of the lab, so failure tests can never affect it.

The platform hosts my projects and must support load and failure testing
(scaling, failover, partition rebalancing), which needs more than two nodes to
be meaningful. The 64 GB machine is also used for local LLM inference, so its
RAM has to be reassignable between the cluster and an inference workload.
The whole platform must be rebuildable from git.

## Options considered

- **Kubernetes directly on the machines (k3s or Talos)**: least overhead,
  but only 2 nodes, the 64 GB machine is one huge node, LLM inference competes
  with cluster workloads, and rebuilding means reinstalling an OS.
- **Proxmox + VMs + k3s via Ansible**: flexible, but nodes are mutable Ubuntu
  machines that drift over time.
- **Proxmox + VMs + Talos, all driven by Terraform**: 6 nodes from 2 machines,
  VM snapshots, immutable API-managed nodes, RAM moved between VMs and an LLM
  container on demand, same workflow as cloud IaC.

## Decision

Proxmox VE on both lab machines as one cluster, with a Corosync QDevice
(`corosync-qnetd`) on the home server as the third quorum vote. Terraform
(`bpg/proxmox`) creates the VMs and the LLM container, and the
`siderolabs/talos` provider bootstraps Kubernetes on the VMs.

Kubernetes: 3 control-plane nodes (2 on pve-1, 1 on pve-2) and 3 workers.
LLM inference runs in an LXC container on pve-1, outside Kubernetes.

## Consequences

- The Proxmox cluster keeps quorum when either lab machine is down, and both
  can be powered off without affecting the home server.
- etcd survives the loss of pve-2 but not of pve-1, which holds 2 of the 3
  control-plane nodes. Worker, broker and database-replica failures remain
  fully testable; full control-plane HA needs a third lab host.
- Nodes can be destroyed and recreated with `terraform apply`.
- The LLM container and the pve-1 workers share 64 GB. Large models need
  worker VMs stopped first; a small model fits next to a reduced cluster.
- Proxmox costs ~1-2 GB of RAM per host.
- Talos has no SSH; all node debugging goes through `talosctl` and the Talos API.
  Fallback if that proves too restrictive: k3s on the same VMs.
