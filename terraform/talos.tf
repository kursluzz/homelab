# Machine configuration per node. Talos 1.14 splits the config into typed
# documents; each patch below is one document, merged into the generated config.
# Documents are YAML-encoded where they are defined: a conditional unifies the
# types of its branches and would turn booleans such as `enabled = false` into
# strings.

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  controlplanes   = { for name, n in var.nodes : name => n if n.role == "controlplane" }
  first_cp        = sort(keys(local.controlplanes))[0]
  installer_image = "factory.talos.dev/nocloud-installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
  node_pool_label = "homelab/node-pool"

  # Every node.
  common_patches = [for doc in [
    {
      # One NIC per VM (virtio); give it a stable name for the documents below.
      apiVersion = "v1alpha1"
      kind       = "LinkAliasConfig"
      name       = "lan"
      selector   = { match = "link.driver == \"virtio_net\"" }
    },
    {
      apiVersion  = "v1alpha1"
      kind        = "ResolverConfig"
      nameservers = [{ address = var.gateway }]
    },
    {
      # Used by "talosctl upgrade"; the first boot uses the disk image.
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer  = { image = local.installer_image }
      provisioning = {
        diskSelector = { match = "disk.dev_path == \"/dev/sda\"" }
        wipe         = false
      }
    },
  ] : yamlencode(doc)]

  # Control-plane nodes: the API virtual IP. Cilium (roadmap step 3) replaces
  # both the default CNI (flannel) and kube-proxy, so neither is deployed;
  # CoreDNS comes from Argo CD.
  controlplane_patches = [for doc in [
    {
      apiVersion = "v1alpha1"
      kind       = "Layer2VIPConfig"
      name       = var.cluster_endpoint
      link       = "lan"
    },
    {
      apiVersion = "v1alpha1"
      kind       = "KubeProxyConfig"
      enabled    = false
    },
    {
      apiVersion = "v1alpha1"
      kind       = "KubeFlannelCNIConfig"
      "$patch"   = "delete"
    },
    {
      # Argo CD deploys CoreDNS instead (kubernetes/infra/coredns), placed on
      # the always-on pool. Talos leaves the objects it created in place.
      apiVersion = "v1alpha1"
      kind       = "KubeCoreDNSConfig"
      enabled    = false
    },
  ] : yamlencode(doc)]

  node_patches = {
    for name, n in var.nodes : name => concat(
      [for doc in [
        {
          apiVersion = "v1alpha1"
          kind       = "HostnameConfig"
          auto       = "off"
          hostname   = name
        },
        {
          apiVersion = "v1alpha1"
          kind       = "LinkConfig"
          name       = "lan"
          addresses  = [{ address = "${n.ip}/${var.lan_prefix_length}" }]
          routes     = [{ gateway = var.gateway }]
        },
      ] : yamlencode(doc)],
      # Persistent volumes: the whole data disk as one filesystem, mounted at
      # /var/mnt/local-path-provisioner, where local-path creates volumes.
      # Incus attaches the root disk first (sda) and the data disk second (sdb).
      n.data_disk_gb > 0 ? [yamlencode({
        apiVersion   = "v1alpha1"
        kind         = "UserVolumeConfig"
        name         = "local-path-provisioner"
        volumeType   = "disk"
        provisioning = { diskSelector = { match = "disk.dev_path == \"/dev/sdb\"" } }
      })] : [],
      # Node pools (ADR 0004): every worker is labelled with its pool; the
      # always-on pool is also tainted, so only workloads that tolerate it land
      # on the home server. Taints are set at first registration (a kubelet
      # cannot change its own taints later).
      n.role == "worker" ? [yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeNodeConfig"
        labels     = { (local.node_pool_label) = n.node_pool }
        taints     = n.node_pool == "always-on" ? { (local.node_pool_label) = "always-on:NoSchedule" } : {}
      })] : [],
    )
  }
}

data "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_endpoint}:6443"
  machine_type       = each.value.role
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = trimprefix(var.kubernetes_version, "v")

  config_patches = concat(
    local.common_patches,
    each.value.role == "controlplane" ? local.controlplane_patches : [],
    local.node_patches[each.key],
  )
}
