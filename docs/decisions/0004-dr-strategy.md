# ADR 0004: Regional DR: geo-replicated data, rebuildable compute

**Status:** accepted

| Tier | Approach | RPO | RTO |
|---|---|---|---|
| Azure SQL | Auto-failover group to North Europe; automatic after a **60-minute grace period** | seconds | ~1 h (or minutes, by planned failover) |
| Data lake | RA-GZRS (readable in the secondary region at all times) | ~15 min (async) | immediate read; account failover for write |
| VM backups | Geo-redundant Recovery Services vault with cross-region restore | ≤ 24 h | hours |
| AKS, network, gateways | Rebuilt from this Terraform in the secondary region | n/a (stateless) | hours |

**Why the grace period:** a short regional blip shouldn't trigger an unplanned failover and its data loss. For a real outage, run the planned-failover runbook.

**The factory keeps running without Azure.** Production control stays in the plant: OT doesn't depend on the cloud. An Azure outage delays analytics and reporting, never production. This is the most important DR property of the whole design.
