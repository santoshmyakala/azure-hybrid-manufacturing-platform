# Spokes: application, data, shared services. No spoke talks to another spoke, the factory or the
# internet except through the hub firewall.
locals {
  spoke_rg = { app = "app", data = "data", shared = "shared" }
  spoke_subnets = {
    "app/aks-nodes"            = cidrsubnet(var.spoke_cidrs.app, 2, 0)    # /22
    "app/private-endpoints"    = cidrsubnet(var.spoke_cidrs.app, 4, 4)    # /24
    "data/private-endpoints"   = cidrsubnet(var.spoke_cidrs.data, 2, 0)   # /24
    "data/integration"         = cidrsubnet(var.spoke_cidrs.data, 2, 1)   # /24
    "shared/management"        = cidrsubnet(var.spoke_cidrs.shared, 1, 0) # /25
    "shared/private-endpoints" = cidrsubnet(var.spoke_cidrs.shared, 1, 1) # /25
  }
}

resource "azurerm_virtual_network" "spoke" {
  for_each            = var.spoke_cidrs
  name                = "vnet-${local.prefix}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg[local.spoke_rg[each.key]].name
  address_space       = [each.value]
  dns_servers         = [local.firewall_ip] # firewall DNS proxy → resolver → private zones / AD
  tags                = local.tags
}

resource "azurerm_subnet" "spoke" {
  for_each                          = local.spoke_subnets
  name                              = split("/", each.key)[1]
  resource_group_name               = azurerm_resource_group.rg[local.spoke_rg[split("/", each.key)[0]]].name
  virtual_network_name              = azurerm_virtual_network.spoke[split("/", each.key)[0]].name
  address_prefixes                  = [each.value]
  private_endpoint_network_policies = "Enabled" # NSGs and UDRs also apply to private endpoints
}

# ---------------------------------------------------------------- peering (hub ↔ spoke)
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                     = var.spoke_cidrs
  name                         = "hub-to-${each.key}"
  resource_group_name          = azurerm_resource_group.rg["connectivity"].name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true # spokes use the hub's ExpressRoute / VPN gateways
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                     = var.spoke_cidrs
  name                         = "${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.rg[local.spoke_rg[each.key]].name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_forwarded_traffic      = true
  use_remote_gateways          = true
  allow_virtual_network_access = true
  depends_on                   = [azurerm_virtual_network_gateway.er, azurerm_virtual_network_gateway.vpn]
}

resource "azurerm_private_dns_resolver_virtual_network_link" "spoke" {
  for_each                  = var.spoke_cidrs
  name                      = each.key
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  virtual_network_id        = azurerm_virtual_network.spoke[each.key].id
}

# ---------------------------------------------------------------- forced routing through the firewall
resource "azurerm_route_table" "spoke" {
  for_each                      = var.spoke_cidrs
  name                          = "rt-${local.prefix}-${each.key}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg[local.spoke_rg[each.key]].name
  bgp_route_propagation_enabled = false # factory routes learned over ExpressRoute must not bypass the firewall
  tags                          = local.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.firewall_ip
  }
}

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each       = local.spoke_subnets
  subnet_id      = azurerm_subnet.spoke[each.key].id
  route_table_id = azurerm_route_table.spoke[split("/", each.key)[0]].id
}

# ---------------------------------------------------------------- NSGs (defence in depth behind the firewall)
resource "azurerm_network_security_group" "spoke" {
  for_each            = local.spoke_subnets
  name                = "nsg-${local.prefix}-${replace(each.key, "/", "-")}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg[local.spoke_rg[split("/", each.key)[0]]].name
  tags                = local.tags

  # OT control networks may never reach Azure workloads directly (only via the industrial DMZ).
  security_rule {
    name                       = "deny-ot-control-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.factory_networks.ot_control
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "spoke" {
  for_each                  = local.spoke_subnets
  subnet_id                 = azurerm_subnet.spoke[each.key].id
  network_security_group_id = azurerm_network_security_group.spoke[each.key].id
}
