# homelab

Self-hosted Kubernetes platform on home PCs: the hosting environment for
my projects, with a streaming and analytics data stack (Kafka, PostgreSQL,
ClickHouse) running on it.

Everything is declarative and lives in this repo: Terraform creates the VMs,
Talos turns them into a Kubernetes cluster, and Argo CD installs everything
else from git.

> Status: **work in progress**, being built step by step. See [Roadmap](#roadmap).

## Hardware

| Host  | CPU                   | RAM   | Role                                                                 |
|-------|-----------------------|-------|----------------------------------------------------------------------|
| home  | Intel i5-7500 (4C/4T) | 20 GB | Always on. VPN endpoint, Wake-on-LAN relay, 2 control-plane nodes, always-on worker for hosted projects |
| lab-1 | Intel i5-7500 (4C/4T) | 64 GB | 1 control-plane node, 2 heavy workers (lab pool), Ollama on the host |
| lab-2 | Intel i5-7400 (4C/4T) | 16 GB | 1 worker (lab pool)                                                  |

All three run Ubuntu Server with Incus; nodes are Talos VMs on a LAN bridge.
lab-1 and lab-2 are powered on over Wake-on-LAN when the lab is in use; the
home server's own services do not depend on them. 1 GbE network.

Physical hosts live in [`ansible/inventory.yaml`](ansible/inventory.yaml) and
the VM split in [`terraform/terraform.tfvars`](terraform/terraform.tfvars.example).
Nothing else in the repo hardcodes an address, so if you fork this, you only
edit those two files.

## Stack

| Layer            | Tool                                                        | Why (see [ADRs](docs/adr/)) |
|------------------|-------------------------------------------------------------|-----------------------------|
| Hypervisor       | Incus on Ubuntu Server (3 standalone hosts)                 | VMs on the existing hosts without a reinstall |
| LLM inference    | Ollama on lab-1's host, started on demand                   | Near-native CPU inference, sized up by stopping worker VMs |
| Host config      | Ansible                                                     | Agentless, idempotent configuration of the existing hosts |
| Remote access    | WireGuard on the home server (planned)                      | Kernel-native VPN, one UDP port forwarded |
| Public access    | Cloudflare DNS + Tunnel, Gateway API, cert-manager / Let's Encrypt (planned) | No open inbound port; one subdomain per project; free TLS |
| Provisioning     | Terraform (`lxc/incus`, `siderolabs/talos`)                 | Same workflow as cloud IaC |
| Kubernetes       | Talos Linux                                                 | Immutable, API-only, no drift |
| GitOps           | Argo CD (app-of-apps)                                       | Install by pushing to git |
| Network          | Cilium (CNI, Hubble, Gateway API, L2 LB IPs)                | One component instead of flannel + MetalLB + ingress |
| Storage          | local-path / TopoLVM for databases, Longhorn for the rest   | Databases replicate themselves |
| Object storage   | Garage (S3 API)                                             | Lightweight, self-hosted S3 |
| Secrets / TLS    | SOPS + age, cert-manager                                    | Encrypted secrets in a public repo |
| Kafka            | Strimzi (KRaft), Kafka Connect, Debezium, Cruise Control    | |
| Postgres         | CloudNativePG                                               | |
| ClickHouse       | Altinity clickhouse-operator + ClickHouse Keeper            | |
| Big data         | Apache Iceberg, Trino, Spark Operator, Flink Operator       | |
| Observability    | kube-prometheus-stack, Loki, Tempo, OpenTelemetry Collector | |
| Scaling / tests  | KEDA, k6 (+ k6-operator), Chaos Mesh                        | |
| Jobs / workflows | RabbitMQ (cluster operator), Celery, DBOS, Temporal, Argo Workflows (planned) | Long-running staged batch jobs; compared in [experiments](experiments/README.md) |

## Repo layout

```
ansible/              host configuration: LAN bridge, Incus, Wake-on-LAN
terraform/            Incus VMs + Talos bootstrap
talos/                Talos machine config patches
kubernetes/
  bootstrap/          Argo CD + the root app-of-apps
  infra/              cilium, cert-manager, storage, observability
  data/               strimzi, cloudnative-pg, clickhouse, garage
experiments/          load / chaos / scaling experiments, with results
docs/adr/             architecture decision records
```

## Roadmap

- [x] 1. Ansible host setup: Docker, uv, LAN bridge, Incus
- [ ] 2. Terraform + Talos: 3 control-plane nodes (2 on the home server), 4 workers in two node pools: always-on (hosted projects) and lab
- [ ] 3. Cilium, Argo CD, cert-manager, storage, observability
- [ ] 4. CloudNativePG, Strimzi, ClickHouse; Debezium CDC pipeline Postgres → Kafka → ClickHouse
- [ ] 5. Experiments: KEDA on Kafka lag, k6 load tests, Chaos Mesh failover
- [ ] 6. Garage S3, Iceberg, Trino, Spark / Flink
- [ ] 7. Staged media-processing workload: resumable uploads to Garage, queue per stage, KEDA, Temporal / Argo Workflows ([planned experiments](experiments/README.md#planned-staged-media-processing-workload))
- [ ] 8. WireGuard VPN on the home server: remote access to the hosts, the cluster and its LoadBalancer IPs; Wake-on-LAN relay for the lab hosts. Independent of steps 2-7; any time after step 1
- [ ] 9. Public projects on `vaja.dev`: one subdomain per project, Cloudflare DNS and Tunnel (no inbound port), routing by hostname through the Cilium Gateway, HTTPS from Cloudflare's edge plus cert-manager with Let's Encrypt (DNS-01) in the cluster
- [ ] 10. `math.vaja.dev`: React frontend and an API with WebSockets behind the gateway

## Experiments

Each experiment in [`experiments/`](experiments/) states a hypothesis, the setup,
how it was measured, and the result, with numbers and dashboard screenshots.

## Local credentials

Nothing secret is committed. Running the platform needs these local files, all
gitignored:

| File | Created by | Used by |
|------|------------|---------|
| `.env` | Copied from [`.env.example`](.env.example) | Shell, via [direnv](https://direnv.net/) (`dotenv`) or `set -a; . ./.env` |
| `homelab.age.key` | `age-keygen -o homelab.age.key`; the public key goes into `.sops.yaml` | SOPS, to decrypt `*.sops.yaml` |
| `terraform/terraform.tfstate` | `terraform apply` | Terraform. Holds the Talos cluster CA and keys |
| `talosconfig`, `kubeconfig` | Terraform outputs (roadmap step 2) | `talosctl`, `kubectl` |
| `~/.config/incus/client.crt`, `client.key` | `incus remote add <host> <trust token>` | Incus CLI and Terraform |

Losing the age key makes every committed secret unreadable, so it is backed up
outside the repo. The Incus client certificate is re-issued with a new trust
token; the rest is regenerated by rebuilding the cluster.

## Rules for this repo

- Secrets are SOPS-encrypted or kept out entirely; `gitleaks` runs as a pre-commit hook.
- Only public datasets (ClickHouse sample datasets, NYC taxi, GitHub events, ...).
- Always the latest versions; Renovate keeps charts and images up to date.

## License

[MIT](LICENSE)
