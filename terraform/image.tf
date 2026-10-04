# Talos boots from the Image Factory's "nocloud" disk image, imported into each
# host's Incus as a VM image. On first boot Talos reads its machine config from
# the cloud-init config drive Incus attaches (nodes.tf), so every node comes up
# with its final config and static address, without a maintenance-mode step.

# Vanilla image, no system extensions.
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({ customization = {} })
}

locals {
  talos_image_dir = "${path.module}/.talos-image/${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 12)}"
}

# Downloads the disk image once to the workstation and builds the Incus
# metadata tarball next to it (talos-image.sh is idempotent).
resource "terraform_data" "talos_image_files" {
  input = local.talos_image_dir

  provisioner "local-exec" {
    command = "${path.module}/talos-image.sh ${var.talos_version} ${talos_image_factory_schematic.this.id} ${local.talos_image_dir}"
  }
}

resource "incus_image" "talos" {
  for_each = var.hosts
  remote   = each.key

  source_file = {
    data_path     = "${terraform_data.talos_image_files.output}/disk.qcow2"
    metadata_path = "${terraform_data.talos_image_files.output}/metadata.tar.gz"
  }
}
