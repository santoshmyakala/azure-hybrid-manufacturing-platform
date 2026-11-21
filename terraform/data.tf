# Data spoke: everything private, Entra ID authentication only (no SQL logins, no storage keys,
# no Event Hubs SAS keys).
resource "azurerm_mssql_server" "this" {
  name                                 = "sql-${local.prefix}-${substr(md5(var.subscription_id), 0, 6)}"
  location                             = var.location
  resource_group_name                  = azurerm_resource_group.rg["data"].name
  version                              = "12.0"
  minimum_tls_version                  = "1.2"
  public_network_access_enabled        = false
  outbound_network_restriction_enabled = true
  tags                                 = local.tags

  azuread_administrator {
    login_username              = var.sql_admin_group.name
    object_id                   = var.sql_admin_group.object_id
    azuread_authentication_only = true
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_mssql_database" "production" {
  name                 = "sqldb-production"
  server_id            = azurerm_mssql_server.this.id
  sku_name             = "GP_Gen5_4"
  zone_redundant       = true
  storage_account_type = "GeoZone"
  tags                 = local.tags

  short_term_retention_policy {
    retention_days = 14
  }

  long_term_retention_policy {
    weekly_retention  = "P8W"
    monthly_retention = "P12M"
    yearly_retention  = "P7Y" # production records retention
    week_of_year      = 1
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ADLS Gen2 lake for historian exports and analytics.
resource "azurerm_storage_account" "lake" {
  name                              = "st${replace(local.prefix, "-", "")}${substr(md5(var.subscription_id), 0, 8)}"
  location                          = var.location
  resource_group_name               = azurerm_resource_group.rg["data"].name
  account_tier                      = "Standard"
  account_replication_type          = "RAGZRS" # zone- and geo-redundant, readable in the DR region
  account_kind                      = "StorageV2"
  is_hns_enabled                    = true
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  tags                              = local.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
}

# FinOps: move cold historian data to cheaper tiers automatically.
resource "azurerm_storage_management_policy" "lake" {
  storage_account_id = azurerm_storage_account.lake.id
  rule {
    name    = "historian-tiering"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["historian/"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 180
      }
    }
  }
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${local.prefix}-${substr(md5(var.subscription_id), 0, 6)}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg["data"].name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "premium" # HSM-backed keys
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false
  tags                          = local.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# Plant telemetry: edge gateways in the industrial DMZ publish over AMQP/TLS through ExpressRoute.
resource "azurerm_eventhub_namespace" "telemetry" {
  name                          = "evhns-${local.prefix}-${substr(md5(var.subscription_id), 0, 6)}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg["data"].name
  sku                           = "Standard"
  capacity                      = 2
  auto_inflate_enabled          = true
  maximum_throughput_units      = 8
  local_authentication_enabled  = false # Entra ID only: no SAS keys on factory devices
  public_network_access_enabled = false
  minimum_tls_version           = "1.2"
  tags                          = local.tags
}

resource "azurerm_eventhub" "plant_telemetry" {
  name              = "plant-telemetry"
  namespace_id      = azurerm_eventhub_namespace.telemetry.id
  partition_count   = 8
  message_retention = 7
}

resource "azurerm_data_factory" "this" {
  name                            = "adf-${local.prefix}-${substr(md5(var.subscription_id), 0, 6)}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.rg["data"].name
  managed_virtual_network_enabled = true
  public_network_enabled          = false
  tags                            = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# Runs on a host in the industrial DMZ, so batch copies from the historian/MES never open
# an inbound path from Azure to the factory.
resource "azurerm_data_factory_integration_runtime_self_hosted" "factory_dmz" {
  name            = "shir-factory-dmz"
  data_factory_id = azurerm_data_factory.this.id
  description     = "Self-hosted IR on the industrial DMZ host (outbound HTTPS only)"
}
