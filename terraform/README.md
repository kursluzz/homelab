Creates the Incus VMs on the three hosts and bootstraps Talos Kubernetes on them. Roadmap step 2.

Inventory: copy `terraform.tfvars.example` to `terraform.tfvars` and edit.
Each host is an Incus remote (`incus remote add <host> https://<ip>:8443`); the
client certificate stays in `~/.config/incus` and is never committed.
