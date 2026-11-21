variable "subscription_id" {
  description = "Landing-zone subscription for this workload."
  type        = string
}

variable "name" {
  description = "Short workload prefix."
  type        = string
  default     = "mfg"
}

variable "environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["prod", "nonprod"], var.environment)
    error_message = "environment must be prod or nonprod."
  }
}

variable "location" {
  description = "Primary region (close to the factory)."
  type        = string
  default     = "swedencentral"
}

variable "secondary_location" {
  description = "DR region for SQL failover group and backup restores."
  type        = string
  default     = "northeurope"
  validation {
    condition     = var.secondary_location != var.location
    error_message = "The DR region must differ from the primary region."
  }
}

variable "tags" {
  description = "Mandatory FinOps tags, enforced by Azure Policy and inherited by every resource."
  type        = map(string)
  default = {
    CostCenter  = "CC-4100-PLANT"
    Owner       = "platform-team@example.com"
    Environment = "prod"
    Workload    = "manufacturing-platform"
  }
  validation {
    condition     = alltrue([for t in ["CostCenter", "Owner", "Environment", "Workload"] : contains(keys(var.tags), t)])
    error_message = "tags must include CostCenter, Owner, Environment and Workload."
  }
}

# ---------------------------------------------------------------- address plan
variable "hub_cidr" {
  type    = string
  default = "10.100.0.0/22"
}

variable "spoke_cidrs" {
  description = "Spoke VNets. Must not overlap with each other or with the factory networks."
  type        = map(string)
  default = {
    app    = "10.110.0.0/20"
    data   = "10.120.0.0/22"
    shared = "10.130.0.0/24"
  }
}

# The factory side, modelled on IEC 62443 zones / the Purdue model.
variable "factory_networks" {
  description = "On-premises address ranges by security zone."
  type = object({
    ot_control     = list(string) # Purdue levels 0-2: PLCs, SCADA, HMIs — never reachable from Azure
    industrial_dmz = list(string) # level 3.5: historian replica, edge gateways, self-hosted IR
    corporate_it   = list(string) # level 4: AD, DNS, MES front-ends, users
  })
  default = {
    ot_control     = ["10.10.0.0/16"]
    industrial_dmz = ["10.20.0.0/24"]
    corporate_it   = ["10.30.0.0/16"]
  }
}

variable "onprem_dns_servers" {
  description = "Corporate AD DNS servers (conditional forwarding target for the AD domain)."
  type        = list(string)
  default     = ["10.30.0.10", "10.30.0.11"]
}

variable "onprem_ad_domain" {
  description = "Active Directory DNS domain, with trailing dot."
  type        = string
  default     = "corp.example.com."
}

variable "onprem_domain_controllers" {
  type    = list(string)
  default = ["10.30.0.10", "10.30.0.11"]
}

# ---------------------------------------------------------------- connectivity
variable "expressroute" {
  description = "Primary private connectivity to the factory."
  type = object({
    service_provider = string
    peering_location = string
    bandwidth_mbps   = number
    primary_subnet   = string # /30 for private peering, primary link
    secondary_subnet = string # /30 for private peering, secondary link
    peer_asn         = number
    vlan_id          = number
  })
  default = {
    service_provider = "Equinix"
    peering_location = "Stockholm"
    bandwidth_mbps   = 1000
    primary_subnet   = "192.168.255.0/30"
    secondary_subnet = "192.168.255.4/30"
    peer_asn         = 65010
    vlan_id          = 100
  }
}

variable "vpn" {
  description = "Backup site-to-site VPN over the internet (used automatically if ExpressRoute fails)."
  type = object({
    factory_public_ip = string
    factory_bgp_asn   = number
    factory_bgp_peer  = string
  })
  default = {
    factory_public_ip = "203.0.113.10" # RFC 5737 documentation address
    factory_bgp_asn   = 65020
    factory_bgp_peer  = "10.30.255.1"
  }
}

variable "vpn_shared_key" {
  description = "IPsec pre-shared key (from a secret store, never in a file)."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.vpn_shared_key) >= 32
    error_message = "Use at least 32 random characters."
  }
}

variable "ddos_protection" {
  description = "Azure DDoS Network Protection plan for the hub (significant fixed monthly cost; see docs/finops.md)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------- workloads
variable "aks_admin_group_object_ids" {
  description = "Entra ID groups that administer the AKS cluster (Azure RBAC; local accounts are disabled)."
  type        = list(string)
  default     = []
}

variable "sql_admin_group" {
  description = "Entra ID group that administers Azure SQL (Entra-only authentication)."
  type        = object({ name = string, object_id = string })
}

# ---------------------------------------------------------------- FinOps
variable "monthly_budget" {
  description = "Monthly budget in the billing currency for the workload's resource groups."
  type        = number
  default     = 25000
}

variable "budget_contacts" {
  type    = list(string)
  default = ["finops@example.com", "platform-team@example.com"]
}

variable "budget_split" {
  description = "Share of the monthly budget per resource group (showback by platform area)."
  type        = map(number)
  default     = { connectivity = 0.35, app = 0.30, data = 0.30, shared = 0.05 }
  validation {
    condition     = abs(sum(values(var.budget_split)) - 1) < 0.001
    error_message = "budget_split must add up to 1."
  }
}

variable "budget_start_date" {
  description = "First day of the first budget month (RFC 3339)."
  type        = string
  default     = "2026-12-01T00:00:00Z"
}

variable "enable_dr" {
  description = "Secondary SQL server + auto-failover group in the DR region."
  type        = bool
  default     = true
}
