# homelab

Self-hosted Kubernetes platform on home PCs: the hosting environment for
my projects, with a streaming and analytics data stack (Kafka, PostgreSQL,
ClickHouse) running on it.

Everything is declarative and lives in this repo: Terraform creates the VMs,
Talos turns them into a Kubernetes cluster, and Argo CD installs everything
else from git.

> Status: **work in progress**, being built step by step. See [Roadmap](#roadmap).

## Hardware

| Host   | CPU              | RAM   | Role                                                      |
|--------|------------------|-------|-----------------------------------------------------------|
| pve-1  | Intel i5-7500 (4C/4T) | 64 GB | Proxmox: 2 control-plane nodes, 2 heavy workers, LLM container |
| pve-2  | Intel i5-7500 (4C/4T) | 16 GB | Proxmox: 1 control-plane node, 1 light worker             |
| home server | Intel i5 8th gen | 16 GB | Not part of the lab. Always on, runs the Proxmox QDevice (quorum tie-breaker) |

The two Proxmox hosts can be powered off when the lab isn't in use; the home
server keeps running independently. 1 GbE network.

Host names, IPs and the VM split live in one place,
[`terraform/terraform.tfvars`](terraform/terraform.tfvars.example). Nothing
else in the repo hardcodes an address, so if you fork this, you only edit that file.

## Stack

| Layer            | Tool                                                        | Why (see [ADRs](docs/adr/)) |
|------------------|-------------------------------------------------------------|-----------------------------|
| Hypervisor       | Proxmox VE (2-host cluster + QDevice)                       | Split 2 machines into 6 k8s nodes you can kill and add |
| LLM inference    | Ollama in an LXC container on pve-1                         | Near-native CPU inference, sized up by stopping worker VMs |
| Provisioning     | Terraform (`bpg/proxmox`, `siderolabs/talos`)               | Same workflow as cloud IaC |
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

## Repo layout

```
terraform/            Proxmox VMs + Talos bootstrap
talos/                Talos machine config patches
kubernetes/
  bootstrap/          Argo CD + the root app-of-apps
  infra/              cilium, cert-manager, storage, observability
  data/               strimzi, cloudnative-pg, clickhouse, garage
experiments/          load / chaos / scaling experiments, with results
docs/adr/             architecture decision records
```

## Roadmap

- [ ] 1. Proxmox cluster on pve-1 + pve-2, QDevice on the home server
- [ ] 2. Terraform + Talos: 3 control-plane nodes, 3 workers; Ollama LXC container
- [ ] 3. Cilium, Argo CD, cert-manager, storage, observability
- [ ] 4. CloudNativePG, Strimzi, ClickHouse; Debezium CDC pipeline Postgres → Kafka → ClickHouse
- [ ] 5. Experiments: KEDA on Kafka lag, k6 load tests, Chaos Mesh failover
- [ ] 6. Garage S3, Iceberg, Trino, Spark / Flink

## Experiments

Each experiment in [`experiments/`](experiments/) states a hypothesis, the setup,
how it was measured, and the result, with numbers and dashboard screenshots.

## Rules for this repo

- Secrets are SOPS-encrypted or kept out entirely; `gitleaks` runs as a pre-commit hook.
- Only public datasets (ClickHouse sample datasets, NYC taxi, GitHub events, ...).
- Always the latest versions; Renovate keeps charts and images up to date.

## License

[MIT](LICENSE)
