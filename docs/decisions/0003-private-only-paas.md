# ADR 0003: Private-only PaaS with Entra ID authentication

**Status:** accepted

**Decision.**
- Every PaaS service is private: public network access is disabled, it's reached through a private endpoint, and its DNS is in the hub.
- **Shared keys are disabled** everywhere: SQL logins, storage account keys, Event Hubs SAS and the ACR admin user. Workloads use managed or workload identities.
- **Azure Policy denies** public access on every PaaS type used here, so the rule also holds for resources created outside this repository.

**Why.** Factory data reaches Azure only over ExpressRoute/VPN, so a public endpoint would be a second, unmonitored way in. Keys leak; identities don't need to be stored anywhere.
