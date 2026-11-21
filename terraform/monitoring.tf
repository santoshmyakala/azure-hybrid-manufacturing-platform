# Diagnostics to one workspace + alerts on the hybrid links the factory depends on.
locals {
  diagnostics = {
    firewall  = azurerm_firewall.this.id
    er-gw     = azurerm_virtual_network_gateway.er.id
    vpn-gw    = azurerm_virtual_network_gateway.vpn.id
    keyvault  = azurerm_key_vault.this.id
    eventhubs = azurerm_eventhub_namespace.telemetry.id
    adf       = azurerm_data_factory.this.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each                       = local.diagnostics
  name                           = "to-log-analytics"
  target_resource_id             = each.value
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  log_analytics_destination_type = each.key == "firewall" ? "Dedicated" : null

  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "platform" {
  name                = "ag-${local.prefix}-platform"
  resource_group_name = azurerm_resource_group.rg["shared"].name
  short_name          = "platform"
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.budget_contacts
    content {
      name                    = "mail-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

locals {
  link_alerts = {
    # name => [scope, namespace, metric, aggregation, operator, threshold, description]
    er-bgp-down     = [azurerm_express_route_circuit.factory.id, "Microsoft.Network/expressRouteCircuits", "BgpAvailability", "Average", "LessThan", 100, "ExpressRoute BGP session to the factory degraded: traffic is failing over to VPN"]
    er-arp-down     = [azurerm_express_route_circuit.factory.id, "Microsoft.Network/expressRouteCircuits", "ArpAvailability", "Average", "LessThan", 100, "ExpressRoute layer-2 (ARP) availability degraded"]
    vpn-tunnel-idle = [azurerm_virtual_network_gateway.vpn.id, "Microsoft.Network/virtualNetworkGateways", "TunnelAverageBandwidth", "Average", "LessThan", 1, "Backup VPN tunnel carries no traffic: check the failover path is up"]
    firewall-health = [azurerm_firewall.this.id, "Microsoft.Network/azureFirewalls", "FirewallHealth", "Average", "LessThan", 90, "Azure Firewall health below 90%"]
    firewall-snat   = [azurerm_firewall.this.id, "Microsoft.Network/azureFirewalls", "SNATPortUtilization", "Average", "GreaterThan", 80, "Firewall SNAT ports above 80%: add public IPs or a NAT gateway"]
  }
}

resource "azurerm_monitor_metric_alert" "links" {
  for_each            = local.link_alerts
  name                = "alert-${local.prefix}-${each.key}"
  resource_group_name = azurerm_resource_group.rg["connectivity"].name
  scopes              = [each.value[0]]
  description         = each.value[6]
  severity            = startswith(each.key, "er-") ? 1 : 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = each.value[1]
    metric_name      = each.value[2]
    aggregation      = each.value[3]
    operator         = each.value[4]
    threshold        = each.value[5]
  }

  action {
    action_group_id = azurerm_monitor_action_group.platform.id
  }
}
