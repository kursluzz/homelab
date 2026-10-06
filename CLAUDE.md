# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this repo is

A self-hosted Kubernetes platform on home PCs: it hosts my projects and runs a
streaming/analytics data stack. Everything is declarative. Terraform creates
Incus VMs on the existing Ubuntu hosts and bootstraps Talos Kubernetes, and
Argo CD installs everything else from `kubernetes/`. See `README.md` for the
stack and `docs/adr/` for the reasoning behind each choice.

## Rules

- **Two inventory files, split by layer.** Physical hosts (addresses, MACs,
  roles) live only in `ansible/inventory.yaml`; VMs, node addresses and sizes
  live only in `terraform/terraform.tfvars`, which refers to hosts by name. Host
  names and the bridge name must match in both. Never hardcode an address or
  node name anywhere else; the one exception is the Cilium LoadBalancer pool
  (`kubernetes/infra/cilium/resources/`), which must be a cluster manifest.
- **GitOps only.** Cluster state changes by committing to `kubernetes/` and letting
  Argo CD sync. `kubectl apply` / `helm install` are for debugging and are never
  the way something gets installed.
- **Operators over hand-rolled manifests.** Stateful services run through their
  operator (Strimzi, CloudNativePG, Altinity clickhouse-operator), not as raw
  StatefulSets.
- **Latest versions.** Don't pin to old releases; Renovate keeps charts and images current.
- **Current industry standards.** Pick the tool the industry uses today, not the
  familiar one.
- **Secrets.** Never commit a plaintext secret. Kubernetes secrets are
  `*.sops.yaml` files encrypted with age (see `.sops.yaml`). Terraform reaches
  Incus with the client certificate in `~/.config/incus`, never committed.
  `gitleaks` runs as a pre-commit hook.
- **Public data only.** Never add data, configs or credentials from any employer.
  Use public datasets (ClickHouse sample datasets, NYC taxi, GitHub events).
- **Resource requests and limits on everything.** The hardware is small, and
  the scheduler needs them to place pods correctly.

## Writing style for committed files

This repo is public. Write READMEs, ADRs and experiment reports the way an
engineer documents a platform: requirements, trade-offs, measurements and
conclusions. Avoid tutorial or diary wording ("practise", "learn", "my first ...").
State results with numbers. Name tools by their category freely (e.g. the big
data stack: Spark, Flink, Iceberg, Trino); don't claim data volumes or
throughput the hardware can't deliver.

## Decisions and experiments

- Any significant tool or architecture choice gets an ADR in `docs/adr/`
  (copy `0000-template.md`, next number, date it).
- Each experiment goes in `experiments/NNN-name/README.md` from `TEMPLATE.md`,
  and gets a row in `experiments/README.md`.
- When a component is deployed, update the Roadmap checkboxes in `README.md`.
