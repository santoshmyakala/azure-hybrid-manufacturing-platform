# Runbook: Sweden Central unavailable

1. **Decide.** Check Azure Service Health. For a short incident, wait: the SQL group fails over by itself after 60 minutes.
2. **SQL (planned, no data loss)** if the primary is reachable:
   ```bash
   az sql failover-group set-primary -g rg-mfg-prod-dr -s sql-mfg-prod-dr-<suffix> -n fog-mfg-prod
   ```
   For a **forced** failover (primary unreachable), add `--allow-data-loss`. Applications use the listener `fog-mfg-prod.database.windows.net` and need no changes.
3. **Lake.** Reads work immediately from the secondary endpoint. For writes, start a customer-managed account failover.
4. **Compute.** Apply this Terraform with `location = "northeurope"` in a new state key to rebuild the hub, spokes and AKS. Then redeploy the applications from the registry; geo-replicate ACR if this must be faster.
5. **Connectivity.** The factory's ExpressRoute circuit can connect to the new hub's gateway. The circuit is global within its geopolitical region with the Standard SKU, and Premium covers more. Until then, use the VPN.
