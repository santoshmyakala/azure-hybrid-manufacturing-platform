# Firewall policy, written as IEC 62443 "conduits": every allowed flow names its source zone,
# destination zone, protocol and ports. Everything else is denied (and logged).
locals {
  aks_subnet       = local.spoke_subnets["app/aks-nodes"]
  data_pe_subnet   = local.spoke_subnets["data/private-endpoints"]
  data_integration = local.spoke_subnets["data/integration"]
  shared_mgmt      = local.spoke_subnets["shared/management"]
}

resource "azurerm_firewall_policy_rule_collection_group" "ot_boundary" {
  name               = "ot-boundary"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  # Explicit, logged denies first: cloud → OT and OT → cloud. Nothing in Azure can initiate a
  # connection into the control network, and the control network never talks to the cloud directly.
  network_rule_collection {
    name     = "deny-ot-control"
    priority = 100
    action   = "Deny"
    rule {
      name                  = "azure-to-ot"
      protocols             = ["Any"]
      source_addresses      = local.azure_all
      destination_addresses = var.factory_networks.ot_control
      destination_ports     = ["*"]
    }
    rule {
      name                  = "ot-to-azure"
      protocols             = ["Any"]
      source_addresses      = var.factory_networks.ot_control
      destination_addresses = local.azure_all
      destination_ports     = ["*"]
    }
  }

  # Conduit: industrial DMZ (historian replica, edge gateways, self-hosted IR) → data spoke.
  network_rule_collection {
    name     = "dmz-to-data-spoke"
    priority = 200
    action   = "Allow"
    rule {
      name                  = "telemetry-and-batch"
      protocols             = ["TCP"]
      source_addresses      = var.factory_networks.industrial_dmz
      destination_addresses = [local.data_pe_subnet]
      destination_ports     = ["443", "5671"] # HTTPS + AMQP/TLS (Event Hubs), Data Factory, Storage
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "hybrid_it" {
  name               = "hybrid-it"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 200

  network_rule_collection {
    name     = "corporate-it-to-azure"
    priority = 100
    action   = "Allow"
    rule {
      name                  = "users-to-apps"
      protocols             = ["TCP"]
      source_addresses      = var.factory_networks.corporate_it
      destination_addresses = [local.aks_subnet]
      destination_ports     = ["443"]
    }
    rule {
      name                  = "reporting-to-sql"
      protocols             = ["TCP"]
      source_addresses      = var.factory_networks.corporate_it
      destination_addresses = [local.data_pe_subnet]
      destination_ports     = ["1433"]
    }
  }

  network_rule_collection {
    name     = "azure-to-corporate-it"
    priority = 200
    action   = "Allow"
    rule {
      name                  = "domain-services"
      protocols             = ["TCP", "UDP"]
      source_addresses      = [local.shared_mgmt]
      destination_addresses = var.onprem_domain_controllers
      destination_ports     = ["53", "88", "123", "135", "389", "445", "464", "636", "3268-3269", "49152-65535"]
    }
    rule {
      name                  = "integration-to-mes"
      protocols             = ["TCP"]
      source_addresses      = [local.data_integration]
      destination_addresses = var.factory_networks.corporate_it
      destination_ports     = ["443", "1433"]
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "egress" {
  name               = "internet-egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 300

  application_rule_collection {
    name     = "platform-egress"
    priority = 100
    action   = "Allow"
    rule {
      name                  = "aks-required"
      source_addresses      = [local.aks_subnet]
      destination_fqdn_tags = ["AzureKubernetesService"]
      protocols {
        type = "Https"
        port = 443
      }
    }
    rule {
      name                  = "os-updates"
      source_addresses      = [local.aks_subnet, local.shared_mgmt]
      destination_fqdn_tags = ["WindowsUpdate"]
      protocols {
        type = "Https"
        port = 443
      }
      protocols {
        type = "Http"
        port = 80
      }
    }
  }
}
