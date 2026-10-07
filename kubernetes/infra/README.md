Cluster infrastructure. Roadmap step 3.

| Component | Purpose |
|---|---|
| `cilium/` | CNI, kube-proxy replacement, LoadBalancer IP pool (`.70-.99`) with L2 announcements, Hubble ([ADR 0006](../../docs/adr/0006-cluster-bootstrap-cilium-argocd.md)) |
| `coredns/` | Cluster DNS, replacing Talos' copy so its replicas and placement can be set (two replicas, spread across hosts) |
| `local-path/` | Default StorageClass: node-local volumes on each worker's data disk (`/var/mnt/local-path-provisioner`) |
| `cert-manager/` | TLS certificates; internal CA (`homelab-ca` ClusterIssuer) |
| `kubelet-serving-cert-approver/` | Approves the kubelets' serving-certificate requests (kubelets run with `serverTLSBootstrap`, `terraform/talos.tf`) |
| `metrics-server/` | `metrics.k8s.io` for `kubectl top` and the HorizontalPodAutoscaler; verifies kubelet TLS (no `--kubelet-insecure-tls`) |
| `monitoring/` | kube-prometheus-stack: Prometheus (15 days), Alertmanager, Grafana on a LoadBalancer IP, node-exporter on every node |

The cluster runs on demand ([ADR 0007](../../docs/adr/0007-kubernetes-on-demand.md)): every node
carries `topology.kubernetes.io/zone=<physical host>`, which components use to
spread replicas across hosts.

Follow-ups: scrape kube-scheduler, kube-controller-manager and etcd (Talos binds
their metrics to localhost); Cilium and Hubble metrics; Gateway API.
