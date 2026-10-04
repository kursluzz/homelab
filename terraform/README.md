Creates the Incus VMs on the three hosts and bootstraps Talos Kubernetes on them
(roadmap step 2, [ADR 0005](../docs/adr/0005-talos-on-incus-nocloud-image.md)).

Prerequisites: `ansible-playbook workstation.yml` (Terraform, talosctl, kubectl,
Incus client) and `ansible-playbook site.yml` (Incus on the hosts, with each
host registered as an Incus remote of the same name).

Inventory: [`terraform.tfvars`](terraform.tfvars). Physical hosts and their
storage pools are in [`ansible/inventory.yaml`](../ansible/inventory.yaml).

```bash
# The state holds the cluster's CA and keys; keep it outside the repo.
terraform init -backend-config="path=$HOME/Dropbox/homelab/terraform/terraform.tfstate"
terraform apply
```

`apply` imports the Talos disk image into each host, creates the VMs, waits for
Talos, bootstraps etcd on the first control-plane node, and writes
`~/.talos/config` and `~/.kube/homelab.yaml`.

Day-2:

- Config changes (e.g. a new patch in `talos.tf`): `terraform apply`, which
  pushes them through the Talos API.
- Talos upgrade: bump `talos_version`, then
  `talosctl upgrade -n <node> --image factory.talos.dev/nocloud-installer/<schematic>:<version>`
  one node at a time (control plane with the lab on, ADR 0004).
- Kubernetes upgrade: `talosctl upgrade-k8s --to <version>`, then bump
  `kubernetes_version`.
