variable "cluster_name" {
  description = "Kubernetes cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "Virtual IP shared by the control-plane nodes (Kubernetes API)."
  type        = string
}

variable "gateway" {
  description = "LAN default gateway, also used as the DNS server."
  type        = string
}

variable "lan_prefix_length" {
  description = "Prefix length of the LAN the nodes are on."
  type        = number
  default     = 24
}

variable "bridge" {
  description = "Host bridge the VMs attach to (ansible/inventory.yaml)."
  type        = string
}

variable "hosts" {
  description = "Physical hosts by Incus remote name. Addresses live in ansible/inventory.yaml."
  type = map(object({
    ram_gb = number
  }))
}

variable "nodes" {
  description = "Kubernetes nodes (VMs), keyed by node name."
  type = map(object({
    host    = string
    role    = string # controlplane | worker
    ip      = string
    cores   = number
    ram_gb  = number
    disk_gb = number
    storage = string # Incus storage pool on that host
    # Second disk for persistent volumes (local-path); workers only.
    data_disk_gb = optional(number, 0)
  }))

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["controlplane", "worker"], n.role)])
    error_message = "role must be controlplane or worker."
  }
  validation {
    condition     = length([for n in values(var.nodes) : n if n.role == "controlplane"]) % 2 == 1
    error_message = "etcd needs an odd number of control-plane nodes."
  }
}

variable "talos_version" {
  description = "Talos release for the node image and the installer (upgrades)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for new clusters. Upgrades go through talosctl upgrade-k8s."
  type        = string
}
