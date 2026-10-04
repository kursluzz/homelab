# One Incus VM per Kubernetes node, on the host and storage pool from
# terraform.tfvars, attached to the LAN bridge.
resource "incus_instance" "node" {
  for_each = var.nodes

  remote = each.value.host
  name   = each.key
  type   = "virtual-machine"
  image  = incus_image.talos[each.value.host].fingerprint

  config = {
    "limits.cpu"    = tostring(each.value.cores)
    "limits.memory" = "${each.value.ram_gb}GiB"
    # The vanilla Talos image is not signed for Secure Boot.
    "security.secureboot" = "false"
    # Start with the host, e.g. after a Wake-on-LAN power-on.
    "boot.autostart" = "true"
    # Read by Talos at first boot from the config drive below. Later config
    # changes are applied through the Talos API (cluster.tf).
    "cloud-init.user-data" = data.talos_machine_configuration.node[each.key].machine_configuration
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = each.value.storage
      size = "${each.value.disk_gb}GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "bridged"
      parent  = var.bridge
    }
  }

  # cloud-init "cidata" drive with the user-data above; Talos' nocloud
  # platform reads its machine config from it.
  device {
    name = "cidata"
    type = "disk"
    properties = {
      source = "cloud-init:config"
    }
  }

  # A node is never re-imaged or re-seeded: Talos upgrades go through
  # "talosctl upgrade", config changes through the Talos API.
  lifecycle {
    ignore_changes = [image, config["cloud-init.user-data"]]
  }
}
