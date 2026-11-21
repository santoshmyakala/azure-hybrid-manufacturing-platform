# Hybrid network design

## Address plan

| Range | Purpose |
|---|---|
| `10.10.0.0/16` | Factory **OT control** (Purdue levels 0–2): PLCs, SCADA, HMIs. Never routed to or from Azure. |
| `10.20.0.0/24` | Factory **industrial DMZ** (level 3.5): historian replica, edge gateways, Data Factory self-hosted IR |
| `10.30.0.0/16` | Factory **corporate IT** (level 4): AD domain controllers, DNS, MES users |
| `10.100.0.0/22` | Azure **hub**: GatewaySubnet `/26` (ExpressRoute + VPN), AzureFirewallSubnet `/26`, AzureBastionSubnet `/26`, DNS resolver inbound/outbound `/28` |
| `10.110.0.0/20` | **Application spoke**: AKS nodes `/22` (pods use an overlay CIDR), private endpoints `/24` |
| `10.120.0.0/22` | **Data spoke**: private endpoints, integration |
| `10.130.0.0/24` | **Shared services spoke**: management, private endpoints |

Nothing overlaps, so every range can be routed and every firewall rule names a real zone. The tests check the derived subnets and IPs.

## Routing: every flow crosses the firewall

| From → to | Path | How it's enforced |
|---|---|---|
| Spoke → anything | Spoke UDR `0.0.0.0/0` → firewall `10.100.0.68` | **BGP route propagation is off** on spoke route tables, so the more specific factory routes learned over ExpressRoute can't bypass the firewall |
| Factory → spoke | Gateway → **GatewaySubnet UDR** (each spoke prefix → firewall) → spoke | `azurerm_route_table.gateway` |
| Spoke ↔ spoke | Spoke → firewall → spoke | Hub-and-spoke peering doesn't propagate between spokes |
| Spoke → internet | Firewall (FQDN tags for AKS and OS updates only) | `internet-egress` rule collection |

The firewall's private IP is the first usable address of `AzureFirewallSubnet`, which is how Azure assigns it. Terraform computes it, so routes are known at plan time, and a postcondition checks it after apply.

## ExpressRoute primary, VPN backup

- Both gateways share the hub's **GatewaySubnet** (`/26`; coexistence needs at least `/27`), and both are zone-redundant.
- **Azure → factory:** for the same prefix, Azure prefers ExpressRoute over VPN automatically.
- **Factory → Azure:** the factory edge router must prefer ExpressRoute. Give its routes a higher BGP local preference, or AS-path-prepend the VPN advertisements. This is the step most often forgotten, and it's in the [failover runbook](runbooks/expressroute-failover.md).
- **The VPN** is active-active, uses BGP and has an explicit IKEv2 / GCM-AES-256 / DH group 24 policy, so failover needs no manual route changes.
- **Alerts** fire on ExpressRoute BGP and ARP availability, and when the VPN tunnel carries no traffic. The goal is to know the backup path works *before* you need it.

## DNS

| Question | Answered by |
|---|---|
| Azure workload resolves `*.privatelink.*` | Firewall DNS proxy → DNS Private Resolver → private DNS zones (linked to the hub) |
| Azure workload resolves `corp.example.com` | Forwarding ruleset (outbound endpoint) → factory domain controllers |
| Factory machine resolves a private endpoint | Factory DNS conditional forwarder for each `privatelink.*` zone → **resolver inbound endpoint `10.100.0.196`** (static) |

Spokes point at the firewall's DNS proxy, so FQDN-based rules resolve exactly what the client resolves.
