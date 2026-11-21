# Every PaaS service is reached through a private endpoint; zones live in the hub and are linked there,
# so the DNS resolver answers for Azure *and* for the factory (which forwards privatelink.* to it).
locals {
  private_dns_zones = {
    sql      = "privatelink.database.windows.net"
    blob     = "privatelink.blob.core.windows.net"
    dfs      = "privatelink.dfs.core.windows.net"
    vault    = "privatelink.vaultcore.azure.net"
    acr      = "privatelink.azurecr.io"
    eventhub = "privatelink.servicebus.windows.net"
    adf      = "privatelink.datafactory.azure.net"
    aks      = "privatelink.${var.location}.azmk8s.io"
  }

  # name => [resource id, subresource, zone key, subnet key]
  private_endpoints = {
    sql      = [azurerm_mssql_server.this.id, "sqlServer", "sql", "data/private-endpoints"]
    blob     = [azurerm_storage_account.lake.id, "blob", "blob", "data/private-endpoints"]
    dfs      = [azurerm_storage_account.lake.id, "dfs", "dfs", "data/private-endpoints"]
    vault    = [azurerm_key_vault.this.id, "vault", "vault", "data/private-endpoints"]
    eventhub = [azurerm_eventhub_namespace.telemetry.id, "namespace", "eventhub", "data/private-endpoints"]
    adf      = [azurerm_data_factory.this.id, "dataFactory", "adf", "data/private-endpoints"]
    acr      = [azurerm_container_registry.this.id, "registry", "acr", "app/private-endpoints"]
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = local.private_dns_zones
  name                  = "hub"
  resource_group_name   = azurerm_resource_group.rg["connectivity"].name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "this" {
  for_each            = local.private_endpoints
  name                = "pe-${local.prefix}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg[split("/", each.value[3])[0]].name
  subnet_id           = azurerm_subnet.spoke[each.value[3]].id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value[0]
    subresource_names              = [each.value[1]]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[each.value[2]].id]
  }
}
