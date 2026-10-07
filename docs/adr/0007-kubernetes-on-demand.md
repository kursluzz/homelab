# 0007. Kubernetes on demand; hosted projects outside the cluster

- Status: accepted
- Date: 2026-10-07
- Supersedes: [0004](0004-always-on-node-pool-on-the-home-server.md)

## Context

ADR 0004 kept the cluster running around the clock on the home server, so that
hosted projects (`vaja.dev`, `math.vaja.dev`) would stay up while the lab hosts
are off. In practice the idle cluster costs 30-40 % of the home server's CPU
(two control-plane nodes, two workers, Argo CD and the cluster components), and
the hosted projects are small enough that Docker Compose on the home server
serves them with less overhead and less to operate.

The cluster's purpose is the lab work: scale and failure experiments, the data
pipeline and big data stack. It doesn't need to run when no experiment does.

## Options considered

- **Keep ADR 0004**: hosted projects on the cluster, always on. Pays the idle
  cost all day for workloads that don't need Kubernetes.
- **Always on, rebalanced across hosts**: lower load on the home server, but the
  lab hosts would have to stay on as well.
- **On demand**: hosted projects run with Docker Compose on the home server;
  the cluster is switched on for experiments and off afterwards, with one
  command each way.

## Decision

The cluster runs on demand:

- One control-plane node per host (cp-1 home, cp-2 lab-2, cp-3 lab-1), so etcd
  survives the loss of any one host; workers on every host (two on home, two
  on lab-1, one on lab-2).
- No node pools. Every node carries `topology.kubernetes.io/zone=<host>`, and
  components spread replicas with it.
- `bin/cluster on|off|status` is the switch. Cluster VMs are tagged in Incus
  (`user.cluster`) and never start with their host (`boot.autostart=false`);
  Terraform doesn't manage whether they run.
- At 00:00 UTC the home server runs `cluster off` and powers the lab hosts off,
  over SSH with a key that can only run the power-off command.
- Hosted projects run with Docker Compose on the home server, outside the
  cluster.

## Consequences

- No idle cost while the cluster is off; the home server's 48 GB and CPU go to
  its own services and the Docker Compose projects.
- Every experiment starts with a cold cluster start; its duration is a number
  worth tracking.
- etcd survives the loss of any one host, including the home server.
- Taints that a node registered with can't be removed by the node itself
  (NodeRestriction); dropping the always-on taint took a one-off
  `kubectl taint ... -`.
- Public projects (roadmap steps 9-10) are served from the home server's Docker
  Compose stack, not through the cluster's Gateway.
