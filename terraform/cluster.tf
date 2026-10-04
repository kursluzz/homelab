# Applies config changes to running nodes, bootstraps etcd once, and writes the
# client configs to the workstation.

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  depends_on = [incus_instance.node]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[local.first_cp].ip
  endpoint             = var.nodes[local.first_cp].ip

  depends_on = [talos_machine_configuration_apply.node]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[local.first_cp].ip
  endpoint             = var.nodes[local.first_cp].ip

  depends_on = [talos_machine_bootstrap.this]
}

# talosctl talks to the control-plane nodes directly, not through the API VIP:
# the VIP only exists while etcd is healthy.
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n in values(local.controlplanes) : n.ip]
  nodes                = [for n in values(var.nodes) : n.ip]
}

# Default talosctl location; ~/.talos and ~/.kube are symlinked into the
# workstation backup (see README.md, "Local credentials").
resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = pathexpand("~/.talos/config")
  file_permission = "0600"
}

resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = pathexpand("~/.kube/homelab.yaml")
  file_permission = "0600"
}
