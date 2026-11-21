locals {
  prefix = "${var.name}-${var.environment}"
  tags   = merge(var.tags, { Environment = var.environment })

  azure_all   = concat([var.hub_cidr], values(var.spoke_cidrs))

  # hub subnets (/22): fixed names required by Azure for the gateway, firewall and bastion subnets
  hub_subnets = {
    GatewaySubnet       = cidrsubnet(var.hub_cidr, 4, 0) # /26: ExpressRoute + VPN gateways coexist here
    AzureFirewallSubnet = cidrsubnet(var.hub_cidr, 4, 1) # /26 required
    AzureBastionSubnet  = cidrsubnet(var.hub_cidr, 4, 2) # /26 required
    dns-inbound         = cidrsubnet(var.hub_cidr, 6, 12)
    dns-outbound        = cidrsubnet(var.hub_cidr, 6, 13)
  }
  dns_inbound_ip = cidrhost(local.hub_subnets["dns-inbound"], 4) # static: on-prem DNS forwards privatelink zones here
  # Azure Firewall always takes the first usable address (.4) of AzureFirewallSubnet; computing it keeps
  # every route known at plan time. A postcondition on the firewall checks the assumption after apply.
  firewall_ip = cidrhost(local.hub_subnets["AzureFirewallSubnet"], 4)
}

resource "azurerm_resource_group" "rg" {
  for_each = toset(["connectivity", "app", "data", "shared"])
  name     = "rg-${local.prefix}-${each.key}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["shared"].name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  daily_quota_gb      = 20 # FinOps guardrail against runaway log ingestion
  tags                = local.tags
}
