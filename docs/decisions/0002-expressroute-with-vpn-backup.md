# ADR 0002: ExpressRoute primary, site-to-site VPN as backup

**Status:** accepted

**Context.** Plant telemetry and MES integration need predictable latency and private connectivity. A single circuit, or a single provider, is a single point of failure.

**Decision.**
- **ExpressRoute** (private peering, zone-redundant gateway) carries all traffic normally.
- An **active-active BGP VPN** on separate internet links takes over automatically if ExpressRoute fails.
- Both gateways coexist in one GatewaySubnet.

**Consequences.**
- The factory edge must prefer ExpressRoute routes (local preference); see the runbook.
- Failover is fast but lowers bandwidth. Telemetry buffers at the edge gateway, and batch copies pause.
- For higher availability, add a second circuit at a different peering location, or use ExpressRoute Metro.
