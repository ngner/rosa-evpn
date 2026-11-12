# Hub (apac-tech-lab) — MTV and mesh rendered examples

The hub cluster runs **MTV forklift** (`forklift-controller` in `openshift-mtv` /
`mtv-integrations`). It reconciles `Plan` and `Migration` objects and talks to
both cluster APIs on **TCP 6443** to create source VMIMs, target VMs/PVCs, and
receiver state. That control-plane role is separate from guest L2 on the CUDNs.

We used **ACM** in the lab to install and configure **Submariner** on the
managed clusters. This folder is for the **readable rendered objects** on the
hub after ACM applied them — not policy-generator definitions or placement
wrappers.

## Submariner here (workaround mesh)

Submariner exists so cross-site paths can reach foreign **pod** IPs (migration
listener `:9185`, importers). It is a **connectivity workaround**, not the
long-term MTV or CUDN story. Rationale and removal criteria:
[docs/migration.md](../docs/migration.md).

## Expected rendered objects (checklist)

Paste exported YAML here when available. Do not commit cluster-specific secrets
or tokens; scrub before check-in.

| Example filename (suggested) | API kind | Why keep it |
|------------------------------|----------|-------------|
| `submariner-broker.yaml` | `Broker` (`submariner.io/v1alpha1`) | Broker token / service discovery anchor for joining clusters |
| `submariner-config-dl380.yaml` | `SubmarinerConfig` (`submarineraddon.open-cluster-management.io/v1alpha1`) | ACM addon config for the on-prem managed cluster (CIDRs, cable driver, NAT) |
| `submariner-config-rosa.yaml` | `SubmarinerConfig` | Same for the ROSA managed cluster |
| `managed-cluster-addon-submariner-*.yaml` | `ManagedClusterAddOn` | ACM view of Submariner enablement per cluster |
| `mtv-plan-*.yaml` | `Plan` (`forklift.konveyor.io/v1beta1`) | Example migration plan shape (optional; plans often stay on hub MTV UI) |
| `mtv-provider-*.yaml` | `Provider` | Hub-side provider entries pointing at `dl380-mtv` / `rosa-virt-mtv` (if exported) |

Until exports land, the table above is the inventory — **no invented CRs** in
this folder.

## MTV control path (from lab notes)

| Cluster | Namespace | Component | Role |
|---------|-----------|-----------|------|
| Hub | `openshift-mtv` | `forklift-controller` | Monitors plan progress; creates VMIM / target VM via APIs |
| Source (dl380) | VM namespace | `virt-handler`, `virt-launcher` | Outbound migration stream |
| Destination (ROSA) | VM namespace | `virt-controller`, receiver listener | `WaitAsReceiver` until sync |

Connection and failure traces: root [NOTES.md](../NOTES.md) (hub diagram and
`DecentralizedNotLiveMigratable` example).

## Read next

- Migration workarounds (Submariner, cold CUDN landing): [migration](../docs/migration.md)
- dl380 EVPN and patches: [on-prem](../on-prem/README.md)
- ROSA rendered stack and optional StorageMap sample: [rosa-cluster](../rosa-cluster/README.md)
- Component inventory (MTV providers, mesh MTU): [rosa-virt-components](../docs/rosa-virt-components.md)
