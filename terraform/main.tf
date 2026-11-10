# Minimal, cheapest-possible AKS cluster for the Kubernetes basics demo.
# Public API server, Free control plane tier, 2 small x86 nodes.

terraform {
  required_version = ">= 1.15"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13"
    }
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription to deploy into (az account list -o table). Set explicitly so a different 'az' default can't redirect the deploy."
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "demo" {
  name     = "aks-demo"
  location = "polandcentral"
}

resource "azurerm_kubernetes_cluster" "demo" {
  name                = "aks-demo"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  dns_prefix          = "aks-demo"
  sku_tier            = "Free" # no control plane fee, no uptime SLA

  default_node_pool {
    name            = "system"
    node_count      = 2
    vm_size         = "Standard_B2als_v2" # cheapest x86 size AKS accepts (2 vCPU / 4 GiB); hpa-example image is amd64-only, so no Arm
    os_disk_size_gb = 30                  # default is 128 GB; smaller disk = cheaper

    # AKS sets this default itself; declaring it stops Terraform from trying to remove it on every plan.
    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Required block in azurerm 5.x. "Manual" = classic fixed node pool (no Node Auto Provisioning).
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Second node pool for application workloads. "User" mode = AKS won't put its own system pods here.
# AKS labels its nodes "kubernetes.azure.com/agentpool: apps" - pods target it with a nodeSelector.
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.demo.id
  mode                  = "User"
  node_count            = 1
  vm_size               = "Standard_B2als_v2"
  os_disk_size_gb       = 30

  # AKS sets this default itself; declaring it stops Terraform from trying to remove it on every plan.
  upgrade_settings {
    max_surge = "10%"
  }
}

output "get_credentials" {
  value = "az aks get-credentials --subscription ${var.subscription_id} -g ${azurerm_resource_group.demo.name} -n ${azurerm_kubernetes_cluster.demo.name}"
}
