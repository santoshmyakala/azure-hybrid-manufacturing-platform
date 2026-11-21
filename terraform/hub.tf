# Connectivity hub: ExpressRoute (primary) + VPN (backup) into one GatewaySubnet, Azure Firewall
# Premium inspecting every flow between the factory, the spokes and the internet, private DNS.
resource "azurerm_network_ddos_protection_plan" "this" {
  count               = var.ddos_protection ? 1 : 0
  name                = "ddos-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  tags                = local.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${local.prefix}-hub"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  address_space       = [var.hub_cidr]
  tags                = local.tags

  dynamic "ddos_protection_plan" {
    for_each = azurerm_network_ddos_protection_plan.this
    content {
      id     = ddos_protection_plan.value.id
      enable = true
    }
  }
}

resource "azurerm_subnet" "hub" {
  for_each             = local.hub_subnets
  name                 = each.key
  resource_group_name  = azurerm_resource_group.rg["connectivity"].name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value]

  dynamic "delegation" {
    for_each = startswith(each.key, "dns-") ? [1] : []
    content {
      name = "dns-resolver"
      service_delegation {
        name    = "Microsoft.Network/dnsResolvers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}

# ---------------------------------------------------------------- public IPs (zone-redundant)
resource "azurerm_public_ip" "pip" {
  for_each            = toset(["firewall", "bastion", "ergw", "vpngw-1", "vpngw-2"])
  name                = "pip-${local.prefix}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

# ---------------------------------------------------------------- ExpressRoute (primary path)
resource "azurerm_express_route_circuit" "factory" {
  name                  = "erc-${local.prefix}-factory"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg["connectivity"].name
  service_provider_name = var.expressroute.service_provider
  peering_location      = var.expressroute.peering_location
  bandwidth_in_mbps     = var.expressroute.bandwidth_mbps
  tags                  = local.tags

  sku {
    tier   = "Standard"
    family = "MeteredData" # FinOps: factory egress volume is modest; see docs/finops.md
  }
}

resource "azurerm_express_route_circuit_peering" "private" {
  peering_type                  = "AzurePrivatePeering"
  express_route_circuit_name    = azurerm_express_route_circuit.factory.name
  resource_group_name           = azurerm_resource_group.rg["connectivity"].name
  peer_asn                      = var.expressroute.peer_asn
  primary_peer_address_prefix   = var.expressroute.primary_subnet
  secondary_peer_address_prefix = var.expressroute.secondary_subnet
  vlan_id                       = var.expressroute.vlan_id
}

resource "azurerm_virtual_network_gateway" "er" {
  name                = "ergw-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  type                = "ExpressRoute"
  sku                 = "ErGw1AZ" # zone-redundant
  tags                = local.tags

  ip_configuration {
    name                 = "default"
    public_ip_address_id = azurerm_public_ip.pip["ergw"].id
    subnet_id            = azurerm_subnet.hub["GatewaySubnet"].id
  }
}

resource "azurerm_virtual_network_gateway_connection" "er" {
  name                       = "conn-${local.prefix}-er-factory"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg["connectivity"].name
  type                       = "ExpressRoute"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.er.id
  express_route_circuit_id   = azurerm_express_route_circuit.factory.id
  routing_weight             = 100
  tags                       = local.tags
  depends_on                 = [azurerm_express_route_circuit_peering.private]
}

# ---------------------------------------------------------------- VPN (backup path)
resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "vpngw-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw2AZ"
  generation          = "Generation2"
  active_active       = true # two tunnels, survives a gateway instance failure
  bgp_enabled         = true
  tags                = local.tags

  bgp_settings {
    asn = 65515
  }

  ip_configuration {
    name                 = "active-1"
    public_ip_address_id = azurerm_public_ip.pip["vpngw-1"].id
    subnet_id            = azurerm_subnet.hub["GatewaySubnet"].id
  }
  ip_configuration {
    name                 = "active-2"
    public_ip_address_id = azurerm_public_ip.pip["vpngw-2"].id
    subnet_id            = azurerm_subnet.hub["GatewaySubnet"].id
  }

  # ER and VPN gateways in one GatewaySubnet: the ER gateway must exist first (coexistence rule)
  depends_on = [azurerm_virtual_network_gateway.er]
}

resource "azurerm_local_network_gateway" "factory" {
  name                = "lgw-${local.prefix}-factory"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  gateway_address     = var.vpn.factory_public_ip
  tags                = local.tags

  bgp_settings {
    asn                 = var.vpn.factory_bgp_asn
    bgp_peering_address = var.vpn.factory_bgp_peer
  }
}

resource "azurerm_virtual_network_gateway_connection" "vpn" {
  name                       = "conn-${local.prefix}-vpn-factory"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg["connectivity"].name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.factory.id
  shared_key                 = var.vpn_shared_key
  bgp_enabled                = true
  connection_protocol        = "IKEv2"
  dpd_timeout_seconds        = 45
  tags                       = local.tags

  # Strong, explicit crypto instead of the negotiated defaults.
  ipsec_policy {
    ike_encryption   = "GCMAES256"
    ike_integrity    = "SHA384"
    dh_group         = "DHGroup24"
    ipsec_encryption = "GCMAES256"
    ipsec_integrity  = "GCMAES256"
    pfs_group        = "PFS24"
    sa_lifetime      = 27000
  }
}

# ---------------------------------------------------------------- Azure Firewall Premium
resource "azurerm_firewall_policy" "this" {
  name                     = "afwp-${local.prefix}"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.rg["connectivity"].name
  sku                      = "Premium"
  threat_intelligence_mode = "Deny"
  tags                     = local.tags

  dns {
    proxy_enabled = true # spokes resolve through the firewall so FQDN rules match what clients resolve
    servers       = [local.dns_inbound_ip]
  }

  intrusion_detection {
    mode = "Deny"
  }
}

resource "azurerm_firewall" "this" {
  name                = "afw-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  zones               = ["1", "2", "3"]
  tags                = local.tags

  ip_configuration {
    name                 = "default"
    subnet_id            = azurerm_subnet.hub["AzureFirewallSubnet"].id
    public_ip_address_id = azurerm_public_ip.pip["firewall"].id
  }

  lifecycle {
    postcondition {
      condition     = self.ip_configuration[0].private_ip_address == local.firewall_ip
      error_message = "Azure Firewall did not take the expected private IP; update local.firewall_ip."
    }
  }
}

# ---------------------------------------------------------------- Bastion (no public IPs on VMs)
resource "azurerm_bastion_host" "this" {
  name                = "bas-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  sku                 = "Standard"
  tunneling_enabled   = true # native RDP/SSH clients with Entra ID sign-in
  ip_connect_enabled  = true # reach VMs in peered spokes by private IP
  tags                = local.tags

  ip_configuration {
    name                 = "default"
    subnet_id            = azurerm_subnet.hub["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.pip["bastion"].id
  }
}

# ---------------------------------------------------------------- hybrid DNS
resource "azurerm_private_dns_resolver" "this" {
  name                = "dnspr-${local.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = local.tags
}

# The factory's DNS servers conditionally forward privatelink.* zones to this address.
resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  name                    = "inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  tags                    = local.tags
  ip_configurations {
    subnet_id                    = azurerm_subnet.hub["dns-inbound"].id
    private_ip_allocation_method = "Static"
    private_ip_address           = local.dns_inbound_ip
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "this" {
  name                    = "outbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  subnet_id               = azurerm_subnet.hub["dns-outbound"].id
  tags                    = local.tags
}

# Azure workloads resolve the AD domain via the factory's domain controllers.
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "this" {
  name                                       = "frs-${local.prefix}"
  location                                   = var.location
  resource_group_name                        = azurerm_resource_group.rg["connectivity"].name
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.this.id]
  tags                                       = local.tags
}

resource "azurerm_private_dns_resolver_forwarding_rule" "ad" {
  name                      = "ad-domain"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  domain_name               = var.onprem_ad_domain
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = var.onprem_dns_servers
    content {
      ip_address = target_dns_servers.value
      port       = 53
    }
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  name                      = "hub"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  virtual_network_id        = azurerm_virtual_network.hub.id
}

# GatewaySubnet: traffic arriving from the factory to any spoke goes through the firewall first.
resource "azurerm_route_table" "gateway" {
  name                = "rt-${local.prefix}-gateway"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  tags                = local.tags

  dynamic "route" {
    for_each = var.spoke_cidrs
    content {
      name                   = "to-${route.key}-via-firewall"
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = local.firewall_ip
    }
  }
}

resource "azurerm_subnet_route_table_association" "gateway" {
  subnet_id      = azurerm_subnet.hub["GatewaySubnet"].id
  route_table_id = azurerm_route_table.gateway.id
}
