# VM inventory: every Kubernetes node, its address and size lives here.
# Physical hosts (addresses, MACs, roles) live in ansible/inventory.yaml; this
# file refers to them by name. Committed on purpose (private LAN addresses are
# harmless). Credentials are not kept here; see "Local credentials" in README.md.

cluster_name     = "homelab"
cluster_endpoint = "192.168.0.50" # virtual IP shared by the control-plane nodes
gateway          = "192.168.0.1"
bridge           = "br0" # LAN bridge on every host; VMs get LAN addresses

# Node addresses (192.168.0.50-69) are outside the router's DHCP pool (.100-.200).
# Hosts (.21-.23) are DHCP reservations, also outside the pool.

# Host RAM, for the budgets below. Terraform reaches each host through the
# Incus remote of the same name (~/.config/incus).
#   saturn: i5-7500 4C/4T. Always on: Immich, file sharing, torrent. Management point.
#   triton: i5-7500 4C/4T, no GPU. Ollama. Powered on for experiments.
#   orion:  i5-7400 4C/4T. Powered on for experiments.
hosts = {
  saturn = { ram_gb = 20 }
  triton = { ram_gb = 64 }
  orion  = { ram_gb = 16 }
}

# Incus storage pools ("dir" driver on existing ext4 filesystems, no repartitioning):
#   saturn: "nvme"    = 1 TB NVMe (/mnt/seattle)
#   triton: "default" = 512 GB NVMe (root), "ssd" = 1 TB SATA SSD (/mnt/monaco);
#           8 TB HDD (/mnt/dallas) left for S3 / backups
#   orion:  "default" = 1 TB NVMe (root)

# Kubernetes nodes (VMs). One control-plane node per host: etcd survives the
# loss of any one host. saturn's VMs are stopped together with the lab.
# vCPUs are overcommitted on purpose (10 vCPUs on 4 threads on triton); pod
# requests/limits, not VM cores, are what keep workloads apart. saturn's VMs
# get at most 2 vCPUs each so its own services keep CPU headroom.
nodes = {
  cp-1 = { host = "triton", role = "controlplane", ip = "192.168.0.51", cores = 2, ram_gb = 4, disk_gb = 40, pool = "default" }
  cp-2 = { host = "orion", role = "controlplane", ip = "192.168.0.52", cores = 2, ram_gb = 4, disk_gb = 40, pool = "default" }
  cp-3 = { host = "saturn", role = "controlplane", ip = "192.168.0.53", cores = 2, ram_gb = 4, disk_gb = 40, pool = "nvme" }

  w-1 = { host = "triton", role = "worker", ip = "192.168.0.61", cores = 4, ram_gb = 18, disk_gb = 150, pool = "ssd" }
  w-2 = { host = "triton", role = "worker", ip = "192.168.0.62", cores = 4, ram_gb = 18, disk_gb = 150, pool = "ssd" }
  w-3 = { host = "orion", role = "worker", ip = "192.168.0.63", cores = 4, ram_gb = 8, disk_gb = 100, pool = "default" }
  w-4 = { host = "saturn", role = "worker", ip = "192.168.0.64", cores = 2, ram_gb = 6, disk_gb = 80, pool = "nvme" }
}

# RAM budgets (GB):
#   saturn: host services ~6 (Immich ML peaks included) + cp-3 4 + w-4 6 = 16 of 20.
#   triton: host 2 + cp-1 4 + workers 36 + Ollama 16 = 58 of 64.
#           Ollama runs on the host (systemd, MemoryMax=16G), not in Incus;
#           for large models, stop w-1/w-2 and raise MemoryMax.
#   orion:  host 2 + cp-2 4 + w-3 8 = 14 of 16.
