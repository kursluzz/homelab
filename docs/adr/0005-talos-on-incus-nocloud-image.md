# 0005. Talos on Incus: nocloud disk image with config from a cloud-init drive

- Status: accepted
- Date: 2026-10-04

## Context

Terraform has to turn Incus VMs into Talos nodes with fixed addresses from
`terraform.tfvars` (ADR 0002), with no manual step. Talos has no SSH or shell;
a node gets its machine config either at boot, from its platform, or later
through the Talos API.

## Options considered

- **Talos ISO, then apply the config in maintenance mode**: the documented
  path for bare metal. The node first boots with a DHCP address that Terraform
  doesn't know (Incus can't report guest addresses on an unmanaged bridge
  without its agent, which Talos doesn't run), and the Incus provider can't
  upload ISO volumes. Both need workarounds.
- **ISO with kernel arguments for a static address**: one Image Factory
  schematic per node, and the config still has to be pushed afterwards.
- **"nocloud" disk image, config on a cloud-init drive**: the VM boots the
  installed Talos disk directly. Incus attaches a `cidata` drive generated from
  the instance's `cloud-init.user-data`, and Talos' nocloud platform reads its
  machine config from it at first boot. That includes the static address, so
  the node comes up on its final IP.

## Decision

The nocloud disk image from the Image Factory (vanilla schematic), imported
into each host's Incus as a VM image. Each node's machine config is passed as
`cloud-init.user-data` with a `cloud-init:config` disk device. Terraform
(`talos_machine_configuration_apply`) then manages the config through the Talos
API, and `talosctl upgrade` with the matching `nocloud-installer` image handles
upgrades. Secure Boot is off on the VMs, because the vanilla image is not
signed. Kube-proxy and the default CNI are disabled; Cilium replaces both
(roadmap step 3).

## Consequences

- One `terraform apply` creates the VMs and the cluster, with no maintenance
  mode and no DHCP addresses to discover. Tested on a single node before the
  full apply: static address on first boot, API VIP up about 15 s after
  bootstrap, node registered with Kubernetes.
- Talos 1.14 splits the machine config into typed documents (`LinkConfig`,
  `Layer2VIPConfig`, `KubeNodeConfig`, ...). The older single `v1alpha1` fields
  for the same settings are rejected next to them, so all patches use the
  typed documents.
- The user-data is read once. Terraform ignores later changes to it and to the
  image, so a config change never re-creates a VM; it is applied through the
  Talos API instead.
- The image (~220 MB) is downloaded once to the workstation and uploaded to
  each host; a new Talos version needs a new image only for new nodes.
- Nodes stay NotReady until Cilium is installed.
