# Shared services spoke: patching, backup. Access to VMs only through Bastion (in the hub).
resource "azurerm_maintenance_configuration" "patching" {
  name                     = "mc-${local.prefix}-weekly"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.rg["shared"].name
  scope                    = "InGuestPatch" # Azure Update Manager, also for Arc-enabled factory servers
  in_guest_user_patch_mode = "User"
  tags                     = local.tags

  window {
    start_date_time = "2026-12-06 02:00"
    duration        = "03:55"
    time_zone       = "W. Europe Standard Time"
    recur_every     = "1Week Sunday" # aligned with the plant's weekly maintenance stop
  }

  install_patches {
    reboot = "IfRequired"
    linux {
      classifications_to_include = ["Critical", "Security"]
    }
    windows {
      classifications_to_include = ["Critical", "Security", "UpdateRollup"]
    }
  }
}

resource "azurerm_recovery_services_vault" "this" {
  name                          = "rsv-${local.prefix}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg["shared"].name
  sku                           = "Standard"
  storage_mode_type             = "GeoRedundant"
  cross_region_restore_enabled  = true       # restore in the DR region without waiting for a Microsoft failover
  immutability                  = "Unlocked" # lock once retention is agreed (ransomware protection)
  public_network_access_enabled = false
  tags                          = local.tags
}
