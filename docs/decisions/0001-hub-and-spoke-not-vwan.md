# ADR 0001: Customer-managed hub-and-spoke rather than Virtual WAN

**Status:** accepted

**Context.** One factory site, one primary region, a handful of spokes. The factory needs fine-grained OT conduits and must be able to read the routing.

**Decision.** Use a customer-managed hub VNet with Azure Firewall Premium, ExpressRoute and VPN gateways, and UDRs.

**Why.**
- **Full control** over route tables (BGP propagation off on spokes), GatewaySubnet routes and DNS.
- **Every path is visible in code** and asserted by tests.
- **Cost:** Virtual WAN's managed routing and hub-to-hub transit pay off with many sites and regions, but this design has one site and one primary region.

**Revisit when** more than about three factory sites or a second active region join. Virtual WAN with routing intent and secured hubs then simplifies transit.
