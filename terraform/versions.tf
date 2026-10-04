terraform {
  required_version = ">= 1.16"

  # The state holds the cluster's CA and keys, so it lives outside the repo:
  #   terraform init -backend-config="path=$HOME/Dropbox/homelab/terraform/terraform.tfstate"
  backend "local" {}

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.2"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

# No remote blocks: the provider uses the remotes in the Incus client config
# (~/.config/incus), which ansible/site.yml registers for every host.
provider "incus" {}

provider "talos" {}

# Talks to the new cluster through the API virtual IP with the admin
# credentials Talos issued (cluster.tf).
provider "helm" {
  kubernetes = {
    host                   = "https://${var.cluster_endpoint}:6443"
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  }
}
