output "firewall_private_ip" { value = local.firewall_ip }
output "dns_inbound_endpoint_ip" {
  description = "Configure the factory's DNS servers to forward privatelink.* zones to this address."
  value       = local.dns_inbound_ip
}
output "aks_cluster_name" { value = azurerm_kubernetes_cluster.this.name }
output "expressroute_service_key" {
  description = "Give this to the connectivity provider to provision the circuit."
  value       = azurerm_express_route_circuit.factory.service_key
  sensitive   = true
}
output "sql_failover_listener" {
  value = var.enable_dr ? "${azurerm_mssql_failover_group.this[0].name}.database.windows.net" : null
}
