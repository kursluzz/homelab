# 0004. Always-on node pool and the control-plane majority on the home server

- Status: accepted
- Date: 2026-10-04
- Amends: [0002](0002-incus-on-existing-ubuntu-hosts.md) (control-plane placement)

## Context

The platform hosts public projects (e.g. `math.vaja.dev`, roadmap steps 9-10)
that must stay up around the clock. The two lab hosts are powered off at night
and only switched on for experiments; the home server is always on.

ADR 0002 put one control-plane node on each host. With the lab hosts off, only
1 of 3 etcd members is left, so etcd has no quorum and the Kubernetes API is
down. Pods that are already running keep running, because the kubelet does not
need the API for that, but nothing self-heals: no rescheduling, no new pods, no
certificate renewals, no operator actions. After a reboot of the home server,
the kubelet cannot fetch its pod list, so nothing starts again until the lab
hosts are back.

## Options considered

- **Keep one control-plane node per host and wake the lab daily, or run it
  24/7**: no architecture change, but the projects still depend on hosts that
  are meant to be optional, and the lab draws power all day.
- **A single control-plane node on the home server**: works with the lab off and
  costs the least RAM, but loses control-plane HA, so etcd quorum and
  control-plane failover can no longer be tested.
- **A separate always-on cluster on the home server**: a clean split, but two
  clusters to bootstrap, upgrade and monitor.
- **Two of three control-plane nodes on the home server, plus an always-on node
  pool there**: one cluster, the API keeps quorum with the lab off, and losing
  any single control-plane VM is still survivable.

## Decision

Three control-plane nodes: two on the home server, one on lab-1. Workers form two
node pools, set as node labels and taints at bootstrap:

- **`always-on`** (a worker on the home server, tainted): cluster essentials
  (CoreDNS, Cilium operator, cert-manager, Cloudflare Tunnel, CloudNativePG
  operator, Argo CD) and the hosted projects, which tolerate the taint and are
  pinned to the pool.
- **`lab`** (workers on lab-1 and lab-2): the data stack and experiment
  workloads, pinned to the pool.

Each project gets its own namespace with a ResourceQuota and a default-deny
NetworkPolicy. There are no separate dev/prod environments.

## Consequences

- With the lab hosts off, etcd keeps 2 of 3 members. The API, scheduling and
  the hosted projects keep working, including after a reboot of the home server.
- The cluster no longer survives the loss of the home server. It is never a
  failure-test target, and the hosted projects live on it anyway.
- Control-plane failover remains testable: losing any one control-plane VM, or
  either lab host, leaves quorum.
- Lab workloads are pinned to `lab`. When the lab powers off, their pods are
  evicted and wait as Pending; they never move onto the home server. When it
  powers on, they are rescheduled, and stateful pods reattach to their local
  volumes.
- Database backups for the hosted projects go off-site to S3-compatible
  storage (Cloudflare R2), not to object storage on a lab host that is off at
  night.
- Upgrading a control-plane node on the home server leaves quorum depending on
  lab-1's member, so control-plane upgrades need the lab on.
- The home server's VMs take 12 of its 20 GB (two control-plane nodes at 3 GB,
  an always-on worker at 6 GB). The always-on worker's size limits how many
  projects it can host.
  Update 2026-10-06: the home server now has 48 GB and a 1 TB system SSD. Two
  always-on workers (w-4, w-5) at 10 GB and control-plane nodes at 4 GB take
  28 GB, with 8 GB kept free for a Docker Compose workload outside the
  cluster; all its VM disks are on the system SSD.
