# Runbook: ExpressRoute down: running on the VPN

**Signal:** the alert `alert-mfg-prod-er-bgp-down` (severity 1) fires.

## Steps
1. **Confirm traffic moved to the VPN.** Check the VPN connection status and tunnel bandwidth in the hub resource group, or run:
   ```bash
   az network vpn-connection show -g rg-mfg-prod-connectivity -n conn-mfg-prod-vpn-factory --query connectionStatus
   ```
2. **Factory side:** check the edge router now uses the VPN-learned Azure routes. If it still prefers a stale ExpressRoute path, that's a local-preference or BFD issue. Fix it there.
3. **Expect reduced bandwidth.** Telemetry buffers at the edge gateway. Pause or reschedule large batch copies (Data Factory) until ExpressRoute recovers.
4. **Open a case** with the connectivity provider, using the circuit service key.

## Back on ExpressRoute
When BGP availability is back to 100%, traffic returns automatically:
- **Azure → factory:** Azure prefers ExpressRoute.
- **Factory → Azure:** the higher local preference on the factory router does the same.

Then confirm with:
```bash
az network express-route show -g rg-mfg-prod-connectivity -n erc-mfg-prod-factory
```

## Practise
Twice a year, in a maintenance window, disable private peering and confirm the failover time is within target.
