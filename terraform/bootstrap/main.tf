# One-time bootstrap (run with Owner rights): keyless GitHub Actions → Azure via OIDC federated
# credentials on two user-assigned identities, and a key-less Terraform state account.
terraform {
  required_version = ">= 1.11"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14"
    }
  }
}

variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "swedencentral"
}

variable "github_repository" {
  type    = string
  default = "santoshmyakala/azure-hybrid-manufacturing-platform"
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {}
}

data "azurerm_subscription" "current" {}

locals {
  # GitHub environment per identity: plans run in unprotected plan-* environments, applies only in
  # the protected ones (main branch + required reviewers).
  identities = {
    plan   = ["plan-nonprod", "plan-prod"]
    deploy = ["nonprod", "prod"]
  }
}

resource "azurerm_resource_group" "bootstrap" {
  name     = "rg-mfg-bootstrap"
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                            = "stmfgtfstate${substr(md5(var.subscription_id), 0, 8)}"
  resource_group_name             = azurerm_resource_group.bootstrap.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false # Entra ID only
  allow_nested_items_to_be_public = false
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "state" {
  name               = "tfstate"
  storage_account_id = azurerm_storage_account.state.id
}

resource "azurerm_user_assigned_identity" "github" {
  for_each            = local.identities
  name                = "id-github-mfg-${each.key}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = var.location
}

resource "azurerm_federated_identity_credential" "github" {
  for_each            = { for pair in flatten([for id, envs in local.identities : [for e in envs : { id = id, env = e }]]) : "${pair.id}-${pair.env}" => pair }
  name                = "github-${each.key}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  parent_id           = azurerm_user_assigned_identity.github[each.value.id].id
  issuer              = "https://token.actions.githubusercontent.com"
  audience            = ["api://AzureADTokenExchange"]
  subject             = "repo:${var.github_repository}:environment:${each.value.env}"
}

# plan: read everything, read/lock state.
resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github["plan"].principal_id
}

# deploy: create resources, assign policies and the platform's own role assignments.
resource "azurerm_role_assignment" "deploy" {
  for_each             = toset(["Contributor", "Resource Policy Contributor", "Role Based Access Control Administrator"])
  scope                = data.azurerm_subscription.current.id
  role_definition_name = each.key
  principal_id         = azurerm_user_assigned_identity.github["deploy"].principal_id
}

resource "azurerm_role_assignment" "state" {
  for_each             = azurerm_user_assigned_identity.github
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor" # plan also needs to write the lock blob
  principal_id         = each.value.principal_id
}

output "github_variables" {
  value = {
    AZURE_TENANT_ID          = data.azurerm_subscription.current.tenant_id
    AZURE_SUBSCRIPTION_ID    = var.subscription_id
    AZURE_PLAN_CLIENT_ID     = azurerm_user_assigned_identity.github["plan"].client_id
    AZURE_DEPLOY_CLIENT_ID   = azurerm_user_assigned_identity.github["deploy"].client_id
    TF_STATE_RESOURCE_GROUP  = azurerm_resource_group.bootstrap.name
    TF_STATE_STORAGE_ACCOUNT = azurerm_storage_account.state.name
  }
}
