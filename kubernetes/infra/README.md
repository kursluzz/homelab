Cluster infrastructure: Cilium, cert-manager, storage, observability. Roadmap step 3.

- `cilium/`: CNI, kube-proxy replacement, LoadBalancer IP pool (`.70-.99`) with
  L2 announcements, Hubble ([ADR 0006](../../docs/adr/0006-cluster-bootstrap-cilium-argocd.md)).

Cluster essentials (needed while the lab hosts are off) tolerate the
`homelab/node-pool=always-on:NoSchedule` taint and prefer that pool
([ADR 0004](../../docs/adr/0004-always-on-node-pool-on-the-home-server.md)).
