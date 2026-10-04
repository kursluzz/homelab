Cluster infrastructure. Roadmap step 3.

| Component | Purpose | Runs on |
|---|---|---|
| `cilium/` | CNI, kube-proxy replacement, LoadBalancer IP pool (`.70-.99`) with L2 announcements, Hubble ([ADR 0006](../../docs/adr/0006-cluster-bootstrap-cilium-argocd.md)) | every node; operator on always-on |
| `coredns/` | Cluster DNS, replacing Talos' copy so it can be placed | always-on worker and control-plane nodes |
| `local-path/` | Default StorageClass: node-local volumes on each worker's data disk (`/var/mnt/local-path-provisioner`) | always-on |
| `cert-manager/` | TLS certificates; internal CA (`homelab-ca` ClusterIssuer) | always-on |
| `monitoring/` | kube-prometheus-stack: Prometheus (15 days), Alertmanager, Grafana on a LoadBalancer IP, node-exporter | lab (node-exporter on every node) |

Cluster essentials (needed while the lab hosts are off) tolerate the
`homelab/node-pool=always-on:NoSchedule` taint and prefer that pool
([ADR 0004](../../docs/adr/0004-always-on-node-pool-on-the-home-server.md)).
Monitoring runs on the lab pool and pauses while the lab is off.

Follow-ups: scrape kube-scheduler, kube-controller-manager and etcd (Talos binds
their metrics to localhost); Cilium and Hubble metrics; Gateway API.
