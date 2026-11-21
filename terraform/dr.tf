# DR: SQL auto-failover group to the secondary region (RPO seconds, RTO about an hour with the
# grace period), geo-redundant lake (RA-GZRS) and cross-region restore for backups.
resource "azurerm_resource_group" "dr" {
  count    = var.enable_dr ? 1 : 0
  name     = "rg-${local.prefix}-dr"
  location = var.secondary_location
  tags     = local.tags
}

resource "azurerm_mssql_server" "secondary" {
  count                         = var.enable_dr ? 1 : 0
  name                          = "sql-${local.prefix}-dr-${substr(md5(var.subscription_id), 0, 6)}"
  location                      = var.secondary_location
  resource_group_name           = azurerm_resource_group.dr[0].name
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = local.tags

  azuread_administrator {
    login_username              = var.sql_admin_group.name
    object_id                   = var.sql_admin_group.object_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_failover_group" "this" {
  count     = var.enable_dr ? 1 : 0
  name      = "fog-${local.prefix}"
  server_id = azurerm_mssql_server.this.id
  databases = [azurerm_mssql_database.production.id]
  tags      = local.tags

  partner_server {
    id = azurerm_mssql_server.secondary[0].id
  }

  # Automatic, but only after an hour: a short regional blip should not trigger a failover
  # (and the data loss of an unplanned one). Planned failover is a runbook step.
  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }
  readonly_endpoint_failover_policy_enabled = true
}
