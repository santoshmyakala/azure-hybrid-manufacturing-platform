# Offline tests (mocked azurerm provider: no subscription, no cost).
mock_provider "azurerm" {
  source          = "./tests/mocks"
  override_during = plan
}

override_resource {
  target          = azurerm_subnet.hub["GatewaySubnet"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/GatewaySubnet" }
}
override_resource {
  target          = azurerm_subnet.hub["AzureFirewallSubnet"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/AzureFirewallSubnet" }
}
override_resource {
  target          = azurerm_subnet.hub["AzureBastionSubnet"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/AzureBastionSubnet" }
}
override_resource {
  target          = azurerm_subnet.hub["dns-inbound"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/dns-inbound" }
}
override_resource {
  target          = azurerm_subnet.hub["dns-outbound"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/dns-outbound" }
}
override_resource {
  target          = azurerm_subnet.spoke["app/aks-nodes"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-app/subnets/aks-nodes" }
}
override_resource {
  target          = azurerm_subnet.spoke["app/private-endpoints"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-app/subnets/private-endpoints" }
}
override_resource {
  target          = azurerm_subnet.spoke["data/private-endpoints"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-data/subnets/private-endpoints" }
}
override_resource {
  target          = azurerm_subnet.spoke["data/integration"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-data/subnets/integration" }
}
override_resource {
  target          = azurerm_subnet.spoke["shared/management"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/management" }
}
override_resource {
  target          = azurerm_subnet.spoke["shared/private-endpoints"]
  override_during = plan
  values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-shared/subnets/private-endpoints" }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  vpn_shared_key  = "test-only-not-a-real-key-test-only"
  sql_admin_group = { name = "sg-sql-admins", object_id = "00000000-0000-0000-0000-0000000000aa" }
}

run "hybrid_connectivity" {
  command = plan

  assert {
    condition     = azurerm_virtual_network_gateway.er.type == "ExpressRoute" && azurerm_virtual_network_gateway.vpn.type == "Vpn"
    error_message = "ExpressRoute (primary) and VPN (backup) gateways must both exist."
  }
  assert {
    condition     = azurerm_virtual_network_gateway.er.ip_configuration[0].subnet_id == azurerm_subnet.hub["GatewaySubnet"].id && alltrue([for c in azurerm_virtual_network_gateway.vpn.ip_configuration : c.subnet_id == azurerm_subnet.hub["GatewaySubnet"].id])
    error_message = "Both gateways must coexist in the hub GatewaySubnet."
  }
  assert {
    condition     = tonumber(split("/", local.hub_subnets["GatewaySubnet"])[1]) <= 27
    error_message = "ExpressRoute/VPN coexistence needs a /27 or larger GatewaySubnet."
  }
  assert {
    condition     = endswith(azurerm_virtual_network_gateway.er.sku, "AZ") && endswith(azurerm_virtual_network_gateway.vpn.sku, "AZ")
    error_message = "Gateways must be zone-redundant SKUs."
  }
  assert {
    condition     = azurerm_virtual_network_gateway.vpn.active_active && azurerm_virtual_network_gateway_connection.vpn.bgp_enabled
    error_message = "Backup VPN must be active-active with BGP so failover is automatic."
  }
  assert {
    condition     = azurerm_virtual_network_gateway_connection.vpn.ipsec_policy[0].ike_encryption == "GCMAES256" && azurerm_virtual_network_gateway_connection.vpn.ipsec_policy[0].dh_group == "DHGroup24" && azurerm_virtual_network_gateway_connection.vpn.connection_protocol == "IKEv2"
    error_message = "VPN must use an explicit strong IKEv2 / AES-GCM-256 policy."
  }
}

run "all_traffic_inspected" {
  command = plan

  assert {
    condition     = alltrue([for rt in azurerm_route_table.spoke : one(rt.route).next_hop_in_ip_address == "10.100.0.68" && one(rt.route).address_prefix == "0.0.0.0/0" && !rt.bgp_route_propagation_enabled])
    error_message = "Every spoke must send 0/0 to the firewall and ignore gateway-learned routes."
  }
  assert {
    condition     = toset([for r in azurerm_route_table.gateway.route : r.address_prefix]) == toset(values(var.spoke_cidrs)) && alltrue([for r in azurerm_route_table.gateway.route : r.next_hop_in_ip_address == "10.100.0.68"])
    error_message = "Traffic from the factory to every spoke must be routed through the firewall."
  }
  assert {
    condition     = length(azurerm_subnet_route_table_association.spoke) == length(local.spoke_subnets) && length(azurerm_subnet_network_security_group_association.spoke) == length(local.spoke_subnets)
    error_message = "Every spoke subnet needs the route table and an NSG."
  }
  assert {
    condition     = alltrue([for p in azurerm_virtual_network_peering.spoke_to_hub : p.use_remote_gateways]) && alltrue([for p in azurerm_virtual_network_peering.hub_to_spoke : p.allow_gateway_transit])
    error_message = "Spokes reach the factory only through the hub gateways."
  }
  assert {
    condition     = azurerm_firewall_policy.this.sku == "Premium" && azurerm_firewall_policy.this.intrusion_detection[0].mode == "Deny" && azurerm_firewall_policy.this.threat_intelligence_mode == "Deny"
    error_message = "Firewall Premium with IDPS and threat intelligence in deny mode."
  }
}

run "ot_zones_and_conduits" {
  command = plan

  assert {
    condition     = [for c in azurerm_firewall_policy_rule_collection_group.ot_boundary.network_rule_collection : c.action if c.priority == min([for x in azurerm_firewall_policy_rule_collection_group.ot_boundary.network_rule_collection : x.priority]...)][0] == "Deny"
    error_message = "The OT deny collection must be evaluated before any allow."
  }
  assert {
    condition     = length([for c in azurerm_firewall_policy_rule_collection_group.ot_boundary.network_rule_collection : c if c.action == "Deny" && length([for r in c.rule : r if contains(r.destination_addresses, "10.10.0.0/16")]) > 0 && length([for r in c.rule : r if contains(r.source_addresses, "10.10.0.0/16")]) > 0]) == 1
    error_message = "Both directions between Azure and the OT control zone must be explicitly denied."
  }
  assert {
    condition = alltrue(flatten([for g in [azurerm_firewall_policy_rule_collection_group.ot_boundary, azurerm_firewall_policy_rule_collection_group.hybrid_it] : [
      for c in g.network_rule_collection : [for r in c.rule : !contains(r.destination_addresses, "10.10.0.0/16")] if c.action == "Allow"
    ]]))
    error_message = "No allow rule may target the OT control network."
  }
  assert {
    condition = alltrue(flatten([for c in azurerm_firewall_policy_rule_collection_group.ot_boundary.network_rule_collection : [
      for r in c.rule : toset(r.source_addresses) == toset(var.factory_networks.industrial_dmz) && toset(r.destination_ports) == toset(["443", "5671"]) && toset(r.destination_addresses) == toset([local.spoke_subnets["data/private-endpoints"]])
    ] if c.action == "Allow"]))
    error_message = "The only factory→cloud conduit is industrial DMZ → data-spoke private endpoints on 443/5671."
  }
  assert {
    condition     = alltrue([for n in azurerm_network_security_group.spoke : one([for r in n.security_rule : r if r.name == "deny-ot-control-inbound"]).access == "Deny"])
    error_message = "Every spoke NSG must also deny the OT control zone (defence in depth)."
  }
}

run "private_paas_only" {
  command = plan

  assert {
    condition     = !azurerm_mssql_server.this.public_network_access_enabled && !azurerm_storage_account.lake.public_network_access_enabled && !azurerm_key_vault.this.public_network_access_enabled && !azurerm_eventhub_namespace.telemetry.public_network_access_enabled && !azurerm_container_registry.this.public_network_access_enabled && !azurerm_data_factory.this.public_network_enabled
    error_message = "No PaaS service may be reachable from the internet."
  }
  assert {
    condition     = toset(keys(azurerm_private_endpoint.this)) == toset(["sql", "blob", "dfs", "vault", "eventhub", "adf", "acr"])
    error_message = "Each PaaS service needs a private endpoint."
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.hub) == length(local.private_dns_zones)
    error_message = "All privatelink zones must be linked to the hub, where the resolver serves Azure and the factory."
  }
  assert {
    condition     = azurerm_mssql_server.this.azuread_administrator[0].azuread_authentication_only && !azurerm_storage_account.lake.shared_access_key_enabled && !azurerm_eventhub_namespace.telemetry.local_authentication_enabled && !azurerm_container_registry.this.admin_enabled
    error_message = "Entra ID authentication only: no SQL logins, storage keys, SAS keys or registry admin user."
  }
  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "Key Vault needs purge protection and RBAC."
  }
}

run "hybrid_dns" {
  command = plan

  assert {
    condition     = azurerm_private_dns_resolver_inbound_endpoint.this.ip_configurations[0].private_ip_allocation_method == "Static" && output.dns_inbound_endpoint_ip == "10.100.0.196"
    error_message = "The inbound resolver IP must be static: the factory's DNS servers forward to it."
  }
  assert {
    condition     = azurerm_private_dns_resolver_forwarding_rule.ad.domain_name == "corp.example.com." && length(azurerm_private_dns_resolver_forwarding_rule.ad.target_dns_servers) == 2
    error_message = "The AD domain must be forwarded to the on-prem domain controllers."
  }
  assert {
    condition     = alltrue([for v in azurerm_virtual_network.spoke : tolist(v.dns_servers) == tolist(["10.100.0.68"])]) && azurerm_firewall_policy.this.dns[0].proxy_enabled
    error_message = "Spokes resolve through the firewall DNS proxy so FQDN rules see the same answers."
  }
}

run "aks_is_private_and_keyless" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled && azurerm_kubernetes_cluster.this.local_account_disabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "AKS: private API server, no local accounts, workload identity."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].outbound_type == "userDefinedRouting" && length(azurerm_kubernetes_cluster.this.default_node_pool[0].zones) == 3
    error_message = "AKS egress through the firewall, nodes across three zones."
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.batch_spot.priority == "Spot" && azurerm_kubernetes_cluster_node_pool.batch_spot.min_count == 0
    error_message = "Batch runs on spot capacity that scales to zero (FinOps)."
  }
}

run "governance_and_finops" {
  command = plan

  assert {
    condition     = tolist(jsondecode(azurerm_subscription_policy_assignment.allowed_locations.parameters).listOfAllowedLocations.value) == tolist(["swedencentral", "northeurope"])
    error_message = "Only the primary and DR regions are allowed."
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.require_rg_tag) == 4 && length(azurerm_subscription_policy_assignment.inherit_tag) == 4 && length(azurerm_role_assignment.inherit_tag) == 4
    error_message = "Required FinOps tags must be enforced on resource groups and inherited by resources."
  }
  assert {
    condition     = length(azurerm_subscription_policy_assignment.no_public_access) == 6 && alltrue([for a in azurerm_subscription_policy_assignment.no_public_access : jsondecode(a.parameters).effect.value == "Deny"])
    error_message = "Public network access must be denied by policy for every PaaS type used."
  }
  assert {
    condition     = sum([for b in azurerm_consumption_budget_resource_group.area : b.amount]) <= var.monthly_budget
    error_message = "Area budgets must not exceed the monthly budget."
  }
  assert {
    condition     = alltrue([for b in azurerm_consumption_budget_resource_group.area : contains([for n in b.notification : n.threshold_type], "Forecasted")])
    error_message = "Every budget alerts on the forecast before money is spent."
  }
  assert {
    condition     = azurerm_log_analytics_workspace.this.daily_quota_gb > 0 && one(azurerm_storage_management_policy.lake.rule).actions[0].base_blob[0].tier_to_archive_after_days_since_modification_greater_than == 180
    error_message = "Cost guardrails: log ingestion cap and historian data tiering."
  }
  assert {
    condition     = alltrue([for k in ["CostCenter", "Owner", "Environment", "Workload"] : contains(keys(azurerm_resource_group.rg["app"].tags), k)])
    error_message = "Every resource group carries the FinOps tags."
  }
}

run "disaster_recovery" {
  command = plan

  assert {
    condition     = azurerm_mssql_failover_group.this[0].read_write_endpoint_failover_policy[0].mode == "Automatic" && azurerm_mssql_failover_group.this[0].read_write_endpoint_failover_policy[0].grace_minutes == 60
    error_message = "SQL fails over automatically, but only after a 60-minute grace period."
  }
  assert {
    condition     = azurerm_mssql_server.secondary[0].location == "northeurope" && azurerm_storage_account.lake.account_replication_type == "RAGZRS" && azurerm_recovery_services_vault.this.cross_region_restore_enabled
    error_message = "DR region copies for SQL, the lake and backups."
  }
}

run "nonprod_without_dr_or_ddos" {
  command = plan
  variables {
    environment     = "nonprod"
    enable_dr       = false
    ddos_protection = false
  }
  assert {
    condition     = length(azurerm_mssql_failover_group.this) == 0 && length(azurerm_network_ddos_protection_plan.this) == 0
    error_message = "Non-production can drop DR and DDoS Network Protection to save cost."
  }
}

run "rejects_missing_finops_tag" {
  command = plan
  variables {
    tags = { CostCenter = "x", Owner = "y", Environment = "prod" }
  }
  expect_failures = [var.tags]
}

run "rejects_weak_vpn_key" {
  command = plan
  variables {
    vpn_shared_key = "short"
  }
  expect_failures = [var.vpn_shared_key]
}

run "rejects_budget_split_not_100_percent" {
  command = plan
  variables {
    budget_split = { connectivity = 0.5, app = 0.5, data = 0.5, shared = 0.1 }
  }
  expect_failures = [var.budget_split]
}
