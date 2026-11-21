# Application spoke: private AKS (no public API server, no local accounts) and a private registry.
data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-${local.prefix}-aks"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["app"].name
  tags                = local.tags
}

# Explicit kubelet identity: stable across cluster rebuilds, so registry and Key Vault grants survive.
resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${local.prefix}-aks-kubelet"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg["app"].name
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_kubelet_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# The cluster registers its API-server record in the hub zone, so on-prem admins resolve it too.
resource "azurerm_role_assignment" "aks_dns" {
  scope                = azurerm_private_dns_zone.this["aks"].id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.spoke["app"].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                      = "aks-${local.prefix}"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg["app"].name
  dns_prefix                = "aks-${local.prefix}"
  sku_tier                  = "Standard" # financially backed API-server SLA
  private_cluster_enabled   = true
  private_dns_zone_id       = azurerm_private_dns_zone.this["aks"].id
  local_account_disabled    = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true # pods get Entra tokens; no secrets for Azure access
  azure_policy_enabled      = true
  image_cleaner_enabled     = true
  cost_analysis_enabled     = true # per-namespace cost in Cost Management (FinOps showback)
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"
  tags                      = local.tags

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_D4ds_v5"
    vnet_subnet_id               = azurerm_subnet.spoke["app/aks-nodes"].id
    zones                        = ["1", "2", "3"]
    auto_scaling_enabled         = true
    min_count                    = 3
    max_count                    = 5
    only_critical_addons_enabled = true
    host_encryption_enabled      = true
    os_sku                       = "AzureLinux"
    temporary_name_for_rotation  = "systemtmp"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  kubelet_identity {
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    outbound_type       = "userDefinedRouting" # egress via the hub firewall
  }

  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday" # outside production shifts
    start_time  = "02:00"
    utc_offset  = "+01:00"
  }

  depends_on = [
    azurerm_role_assignment.aks_dns,
    azurerm_role_assignment.aks_network,
    azurerm_role_assignment.aks_kubelet_operator,
    azurerm_subnet_route_table_association.spoke, # UDR must exist before a userDefinedRouting cluster
    azurerm_private_dns_zone_virtual_network_link.hub,
  ]
}

# Workload pool for factory applications; spot capacity for interruptible batch work (FinOps).
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D8ds_v5"
  vnet_subnet_id        = azurerm_subnet.spoke["app/aks-nodes"].id
  zones                 = ["1", "2", "3"]
  auto_scaling_enabled  = true
  min_count             = 3
  max_count             = 12
  os_sku                = "AzureLinux"
  tags                  = local.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "batch_spot" {
  name                  = "batchspot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_D8ds_v5"
  vnet_subnet_id        = azurerm_subnet.spoke["app/aks-nodes"].id
  zones                 = ["1", "2", "3"]
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = -1
  auto_scaling_enabled  = true
  min_count             = 0 # scales to zero when no batch jobs run
  max_count             = 10
  node_taints           = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
  tags                  = local.tags
}

resource "azurerm_container_registry" "this" {
  name                          = replace("acr${local.prefix}${substr(md5(var.subscription_id), 0, 6)}", "-", "")
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg["app"].name
  sku                           = "Premium" # private endpoints, zone redundancy, retention
  admin_enabled                 = false
  public_network_access_enabled = false
  zone_redundancy_enabled       = true
  anonymous_pull_enabled        = false
  data_endpoint_enabled         = true
  tags                          = local.tags
}

resource "azurerm_role_assignment" "aks_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
}
