mock_data "azurerm_client_config" {
  defaults = { tenant_id = "00000000-0000-0000-0000-000000000001" }
}
mock_data "azurerm_subscription" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000", subscription_id = "00000000-0000-0000-0000-000000000000" }
}
mock_data "azurerm_policy_definition_built_in" {
  defaults = { id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000000" }
}
mock_data "azurerm_policy_set_definition" {
  defaults = { id = "/providers/Microsoft.Authorization/policySetDefinitions/a8640138-9b0a-4a28-b8cb-1666c838647d" }
}
mock_resource "azurerm_resource_group" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock" }
}
mock_resource "azurerm_virtual_network" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-mock" }
}
mock_resource "azurerm_subnet" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworks/vnet-mock/subnets/snet-mock" }
}
mock_resource "azurerm_public_ip" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/publicIPAddresses/pip-mock" }
}
mock_resource "azurerm_firewall_policy" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/firewallPolicies/afwp-mock" }
}
mock_resource "azurerm_firewall" {
  # Azure assigns the first usable address of AzureFirewallSubnet; the postcondition checks it.
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/azureFirewalls/afw-mock", ip_configuration = { private_ip_address = "10.100.0.68" } }
}
mock_resource "azurerm_virtual_network_gateway" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/virtualNetworkGateways/gw-mock" }
}
mock_resource "azurerm_local_network_gateway" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/localNetworkGateways/lgw-mock" }
}
mock_resource "azurerm_express_route_circuit" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/expressRouteCircuits/erc-mock" }
}
mock_resource "azurerm_network_ddos_protection_plan" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/ddosProtectionPlans/ddos-mock" }
}
mock_resource "azurerm_route_table" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/routeTables/rt-mock" }
}
mock_resource "azurerm_network_security_group" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/networkSecurityGroups/nsg-mock" }
}
mock_resource "azurerm_private_dns_zone" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/privateDnsZones/privatelink.mock.net" }
}
mock_resource "azurerm_private_dns_resolver" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/dnsResolvers/dnspr-mock" }
}
mock_resource "azurerm_private_dns_resolver_inbound_endpoint" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/dnsResolvers/dnspr-mock/inboundEndpoints/inbound" }
}
mock_resource "azurerm_private_dns_resolver_outbound_endpoint" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/dnsResolvers/dnspr-mock/outboundEndpoints/outbound" }
}
mock_resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/dnsForwardingRulesets/frs-mock" }
}
mock_resource "azurerm_log_analytics_workspace" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.OperationalInsights/workspaces/log-mock" }
}
mock_resource "azurerm_kubernetes_cluster" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ContainerService/managedClusters/aks-mock" }
}
mock_resource "azurerm_container_registry" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ContainerRegistry/registries/acrmock" }
}
mock_resource "azurerm_mssql_server" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Sql/servers/sql-mock" }
}
mock_resource "azurerm_mssql_database" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Sql/servers/sql-mock/databases/db-mock" }
}
mock_resource "azurerm_storage_account" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Storage/storageAccounts/stmock" }
}
mock_resource "azurerm_key_vault" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.KeyVault/vaults/kv-mock" }
}
mock_resource "azurerm_eventhub_namespace" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.EventHub/namespaces/evhns-mock" }
}
mock_resource "azurerm_data_factory" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.DataFactory/factories/adf-mock" }
}
mock_resource "azurerm_monitor_action_group" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/actionGroups/ag-mock" }
}
mock_resource "azurerm_recovery_services_vault" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.RecoveryServices/vaults/rsv-mock" }
}
mock_resource "azurerm_maintenance_configuration" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Maintenance/maintenanceConfigurations/mc-mock" }
}
mock_resource "azurerm_user_assigned_identity" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mock", principal_id = "00000000-0000-0000-0000-0000000000cc", client_id = "00000000-0000-0000-0000-0000000000dd" }
}
mock_resource "azurerm_subscription_policy_assignment" {
  defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock", identity = { principal_id = "00000000-0000-0000-0000-0000000000ee", tenant_id = "00000000-0000-0000-0000-000000000001" } }
}
