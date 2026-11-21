# Guardrails (Azure Policy) and FinOps (tags, budgets). Built-in definitions are looked up by their
# exact display names, verified against Microsoft's published built-in policy definitions.
data "azurerm_subscription" "current" {}

locals {
  # display name => effect parameter (null when the definition has no effect parameter)
  deny_public_access = {
    "Public network access on Azure SQL Database should be disabled"    = "Deny"
    "Storage accounts should disable public network access"             = "Deny"
    "Azure Key Vault should disable public network access"              = "Deny"
    "Event Hub Namespaces should disable public network access"         = "Deny"
    "Public network access should be disabled for Container registries" = "Deny"
    "Public network access on Azure Data Factory should be disabled"    = "Deny"
  }
  required_tags = ["CostCenter", "Owner", "Environment", "Workload"]
}

data "azurerm_policy_definition_built_in" "allowed_locations" {
  display_name = "Allowed locations"
}

data "azurerm_policy_definition_built_in" "require_rg_tag" {
  display_name = "Require a tag on resource groups"
}

data "azurerm_policy_definition_built_in" "inherit_tag" {
  display_name = "Inherit a tag from the resource group if missing"
}

data "azurerm_policy_definition_built_in" "no_public_access" {
  for_each     = local.deny_public_access
  display_name = each.key
}

data "azurerm_policy_set_definition" "aks_baseline" {
  display_name = "Kubernetes cluster pod security baseline standards for Linux-based workloads"
}

resource "azurerm_subscription_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  display_name         = "Resources only in the primary and DR regions"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition_built_in.allowed_locations.id
  parameters = jsonencode({
    listOfAllowedLocations = { value = [var.location, var.secondary_location] }
  })
  non_compliance_message {
    content = "Deploy only to ${var.location} or ${var.secondary_location} (data residency and DR design)."
  }
}

resource "azurerm_subscription_policy_assignment" "require_rg_tag" {
  for_each             = toset(local.required_tags)
  name                 = "require-rg-tag-${lower(each.key)}"
  display_name         = "Resource groups must carry the ${each.key} tag"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition_built_in.require_rg_tag.id
  parameters           = jsonencode({ tagName = { value = each.key } })
  non_compliance_message {
    content = "FinOps: tag the resource group with ${each.key} so its cost can be allocated."
  }
}

resource "azurerm_subscription_policy_assignment" "inherit_tag" {
  for_each             = toset(local.required_tags)
  name                 = "inherit-tag-${lower(each.key)}"
  display_name         = "Resources inherit ${each.key} from their resource group"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition_built_in.inherit_tag.id
  location             = var.location
  parameters           = jsonencode({ tagName = { value = each.key } })
  identity {
    type = "SystemAssigned"
  }
}

# The Modify effect needs its identity to hold the role named in the definition (Contributor).
resource "azurerm_role_assignment" "inherit_tag" {
  for_each             = azurerm_subscription_policy_assignment.inherit_tag
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = each.value.identity[0].principal_id
}

resource "azurerm_subscription_policy_assignment" "no_public_access" {
  for_each             = local.deny_public_access
  name                 = "deny-public-${substr(md5(each.key), 0, 8)}"
  display_name         = each.key
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition_built_in.no_public_access[each.key].id
  parameters           = jsonencode({ effect = { value = each.value } })
  non_compliance_message {
    content = "PaaS services must be reached through private endpoints over ExpressRoute/VPN, never the internet."
  }
}

resource "azurerm_subscription_policy_assignment" "aks_baseline" {
  name                 = "aks-pod-security-baseline"
  display_name         = "AKS pod security baseline (deny)"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_set_definition.aks_baseline.id
  parameters           = jsonencode({ effect = { value = "Deny" } })
}

# ---------------------------------------------------------------- budgets (showback per area)
resource "azurerm_consumption_budget_resource_group" "area" {
  for_each          = var.budget_split
  name              = "budget-${local.prefix}-${each.key}"
  resource_group_id = azurerm_resource_group.rg[each.key].id
  amount            = floor(var.monthly_budget * each.value)
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  # Early warning on the forecast, then on actual spend.
  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThan"
    contact_emails = var.budget_contacts
  }
  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThan"
    contact_emails = var.budget_contacts
  }
  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Actual"
    operator       = "GreaterThan"
    contact_emails = var.budget_contacts
    contact_roles  = ["Owner"]
  }

  lifecycle {
    ignore_changes = [time_period] # the start date is fixed once the budget exists
  }
}
