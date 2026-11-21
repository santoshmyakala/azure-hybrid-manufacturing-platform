# Runbook: isolate the plant from Azure (security incident)

Use this when there's suspected compromise in Azure, or in the industrial DMZ, and the OT owner asks for isolation. **Production keeps running:** nothing in the plant depends on Azure.

1. **Cut the conduit at the cloud side (seconds).** Disable the rule collection `dmz-to-data-spoke` in the portal, or change its action to Deny via an emergency PR. All other OT traffic is already denied.
2. **Cut at the plant side.** The OT team blocks the DMZ firewall's outbound rule to the ExpressRoute and VPN next hops.
3. **Freeze identities.** Disable the edge gateway's managed identity, and the self-hosted IR node in Data Factory.
4. **Preserve evidence.** Firewall logs (dedicated tables), NSG flow logs and Defender alerts are in Log Analytics. Export them before retention expires.
5. **Restore in reverse order** once the OT owner and security team agree. Re-enable the plant side first, then the cloud conduit, and watch the firewall logs for unexpected flows.
