terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.36.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.4.0"
    }
  }

  backend "azurerm" {
    tenant_id            = "b3033e23-4e79-48f8-a7b4-062fd451d4b2"
    subscription_id      = "a9835b1f-dc51-4b91-83b1-436fc54726b5"
    resource_group_name  = "skwig-homelab-rg-euw-prd"
    storage_account_name = "skwighomelabsteuwprd"
    container_name       = "iac"
    key                  = "prd.terraform.tfstate"
  }
}

locals {
  tenant_id       = "b3033e23-4e79-48f8-a7b4-062fd451d4b2"
  subscription_id = "a9835b1f-dc51-4b91-83b1-436fc54726b5"
}

provider "azurerm" {
  subscription_id = local.subscription_id
  features {}
}

provider "azuread" {
}

resource "azurerm_resource_group" "homelab_resource_group" {
  name     = "skwig-homelab-rg-euw-prd"
  location = "West Europe"
}

resource "azurerm_storage_account" "homelab_storage_account" {
  name                     = "skwighomelabsteuwprd"
  resource_group_name      = azurerm_resource_group.homelab_resource_group.name
  location                 = azurerm_resource_group.homelab_resource_group.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "homelab_container_iac" {
  name                  = "iac"
  storage_account_id    = azurerm_storage_account.homelab_storage_account.id
  container_access_type = "private"
}

resource "azuread_application" "homelab_application" {
  display_name = "Skwig's homelab"
}

resource "azuread_service_principal" "homelab_service_principal" {
  client_id = azuread_application.homelab_application.client_id
}

resource "azuread_service_principal_password" "homelab" {
  service_principal_id = azuread_service_principal.homelab_service_principal.id
}

resource "azurerm_key_vault" "homelab_key_vault" {
  name                      = "skwig-homelab-kv-euw-prd"
  location                  = azurerm_resource_group.homelab_resource_group.location
  resource_group_name       = azurerm_resource_group.homelab_resource_group.name
  tenant_id                 = local.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
}

resource "azurerm_key_vault_key" "homelab_sops_key" {
  name         = "sops"
  key_vault_id = azurerm_key_vault.homelab_key_vault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }
}

resource "azurerm_role_assignment" "homelab_service_principal_key_vaultcontributor" {
  scope                = azurerm_key_vault.homelab_key_vault.id
  principal_id         = azuread_service_principal.homelab_service_principal.object_id
  role_definition_name = "Key Vault Secrets User"
}

output "client_id" {
  value = azuread_application.homelab_application.client_id
}

output "client_secret" {
  value     = azuread_service_principal_password.homelab.value
  sensitive = true
}

output "tenant_id" {
  value = local.tenant_id
}

output "vault_uri" {
  value = azurerm_key_vault.homelab_key_vault.vault_uri
}
