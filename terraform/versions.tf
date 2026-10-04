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
  }
}

# No remote blocks: the provider uses the remotes in the Incus client config
# (~/.config/incus), which ansible/site.yml registers for every host.
provider "incus" {}

provider "talos" {}
