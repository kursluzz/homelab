# One Incus VM per Kubernetes node, on the host and storage pool from
# terraform.tfvars, attached to the LAN bridge.

# Data disk for persistent volumes. Talos formats it as a user volume mounted
# at /var/mnt/local-path-provisioner (talos.tf), separate from the system disk.
resource "incus_storage_volume" "data" {
  for_each = { for name, n in var.nodes : name => n if n.data_disk_gb > 0 }

  remote       = each.value.host
  pool         = each.value.storage
  name         = "${each.key}-data"
  content_type = "block"
  config = {
    size = "${each.value.data_disk_gb}GiB"
  }
}

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
    # The cluster is switched on and off as a whole by bin/cluster (ADR 0007):
    # never start with the host, and mark the VM as a cluster node so the
    # switch never touches other instances on the same host.
    "boot.autostart" = "false"
    "user.cluster"   = var.cluster_name
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

  dynamic "device" {
    for_each = each.value.data_disk_gb > 0 ? [incus_storage_volume.data[each.key]] : []
    content {
      name = "data"
      type = "disk"
      properties = {
        pool   = device.value.pool
        source = device.value.name
      }
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
  # "talosctl upgrade", config changes through the Talos API. Whether it runs
  # is up to bin/cluster, so an apply never switches the cluster on or off.
  lifecycle {
    ignore_changes = [image, config["cloud-init.user-data"], running]
  }
}
