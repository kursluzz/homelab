# VM inventory: every Kubernetes node, its address and size lives here.
# Physical hosts (addresses, MACs, roles) live in ansible/inventory.yaml; this
# file refers to them by name. Committed on purpose (private LAN addresses are
# harmless). Credentials are not kept here; see "Local credentials" in README.md.

cluster_name = "homelab"
# Upgrades: talosctl upgrade / upgrade-k8s; these values set what new nodes get.
# renovate: datasource=github-releases depName=siderolabs/talos
talos_version = "v1.14.2"
# renovate: datasource=github-releases depName=kubernetes/kubernetes
kubernetes_version = "v1.37.1"
cluster_endpoint   = "192.168.0.40" # virtual IP shared by the control-plane nodes
gateway            = "192.168.0.1"
bridge             = "br0" # LAN bridge on every host; VMs get LAN addresses

# LAN plan (192.168.0.0/24):
#   .1         router
#   .2-.19     other devices with static addresses
#   .20-.29    physical hosts (ansible/inventory.yaml; DHCP reservations by MAC)
#   .30-.39    VMs and containers outside Kubernetes (spare)
#   .40        Kubernetes API virtual IP
#   .41-.49    control-plane nodes
#   .50-.69    workers
#   .70-.99    LoadBalancer IPs for Services (Cilium LB IPAM)
#   .100-.200  router DHCP pool

# Host RAM, for the budgets below. Terraform reaches each host through the
# Incus remote of the same name (~/.config/incus).
#   saturn: i5-7500 4C/4T. Always on: Immich, file sharing, torrent. VPN endpoint.
#   triton: i5-7500 4C/4T, no GPU. Ollama. Powered on for experiments.
#   orion:  i5-7400 4C/4T. Powered on for experiments.
hosts = {
  saturn = { ram_gb = 48 }
  triton = { ram_gb = 64 }
  orion  = { ram_gb = 20 }
}

# Incus storage pools are defined per host in ansible/inventory.yaml (incus_pools):
#   saturn: "ssd" = 1 TB system SSD
#   triton: "default" = 512 GB NVMe (root), "ssd" = 1 TB SATA SSD;
#           8 TB HDD (/mnt/dallas) left for S3 / backups
#   orion:  "default" = 1 TB NVMe (root)

# Kubernetes nodes (VMs), ADR 0007: one control-plane node per host, so etcd
# survives the loss of any one host; workers on every host. The cluster runs on
# demand (bin/cluster on|off). Each node is labelled with its host as
# topology.kubernetes.io/zone.
# storage is an Incus storage pool on that host (ansible/inventory.yaml); the
# root disk and the data disk (persistent volumes, local-path) both use it.
# vCPUs are overcommitted on purpose; pod requests/limits, not VM cores, are
# what keep workloads apart.
# saturn's VMs get at most 2 vCPUs each so its own services keep CPU headroom.
nodes = {
  cp-1 = { host = "saturn", role = "controlplane", ip = "192.168.0.41", cores = 2, ram_gb = 4, disk_gb = 40, storage = "ssd" }
  cp-2 = { host = "orion", role = "controlplane", ip = "192.168.0.42", cores = 2, ram_gb = 4, disk_gb = 40, storage = "default" }
  cp-3 = { host = "triton", role = "controlplane", ip = "192.168.0.43", cores = 2, ram_gb = 4, disk_gb = 40, storage = "default" }

  w-1 = { host = "triton", role = "worker", ip = "192.168.0.51", cores = 4, ram_gb = 18, disk_gb = 150, data_disk_gb = 200, storage = "ssd" }
  w-2 = { host = "triton", role = "worker", ip = "192.168.0.52", cores = 4, ram_gb = 18, disk_gb = 150, data_disk_gb = 200, storage = "ssd" }
  w-3 = { host = "orion", role = "worker", ip = "192.168.0.53", cores = 4, ram_gb = 12, disk_gb = 150, data_disk_gb = 300, storage = "default" }
  w-4 = { host = "saturn", role = "worker", ip = "192.168.0.54", cores = 2, ram_gb = 10, disk_gb = 100, data_disk_gb = 100, storage = "ssd" }
  w-5 = { host = "saturn", role = "worker", ip = "192.168.0.55", cores = 2, ram_gb = 10, disk_gb = 60, data_disk_gb = 150, storage = "ssd" }
}

# RAM budgets (GB), with the cluster on:
#   saturn: host services ~8 (Immich ML peaks included) + Docker Compose projects 8
#           + cp-1 4 + w-4 10 + w-5 10 = 40 of 48. With the cluster off, its VMs use nothing.
#   triton: host 2 + cp-3 4 + workers 36 + Ollama 16 = 58 of 64.
#           Ollama runs on the host (systemd, MemoryMax=16G), not in Incus;
#           for large models, stop w-1/w-2 and raise MemoryMax.
#   orion:  host 2 + cp-2 4 + w-3 12 = 18 of 20 (18 GiB usable).
