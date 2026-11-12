# dl380 — virtualization and MTV source-side examples

Rendered objects from the on-prem OpenShift Virtualization cluster that help
colleagues understand **migration source** behavior: KubeVirt bindings, guest
namespaces on CUDNs, and any MTV-facing namespace material.

We used **ACM** where addons applied cluster-wide; this file lists what belongs
here once exported. **No invented secrets or live credentials.**

## Already in this repo (not duplicated here)

| Artifact | Location | Role |
|----------|----------|------|
| KubeVirt `l2bridge` + default interface patch | [02-kubevirt-default-l2bridge.yaml](../02-kubevirt-default-l2bridge.yaml) | Guest L2 for live migration on shared macVRF |
| Example VM on Phase 1 yellow CUDN | [vm-yellow-1.yaml](../vm-yellow-1.yaml) | Namespace / interface shape |
| Fabric blue-320 CUDN | [cudn-evpn-blue-320.yaml](../cudn-evpn-blue-320.yaml) | Primary CUDN namespaces (`primary-cudn: blue-320`) |

ROSA-side mirror of l2bridge, example VM, and optional **StorageMap** fix:
[rosa-cluster/](../../rosa-cluster/README.md) and
[StorageMapFixforbadmigration.yaml](../../rosa-cluster/StorageMapFixforbadmigration.yaml)
(`px-rwx-block-kubevirt` → `efs-sc` for `dl380-mtv` / `rosa-virt-mtv` providers).

## Checklist — paste when exported

| Example filename (suggested) | Kind / area | Why keep it |
|------------------------------|-------------|-------------|
| `namespace-blue-mtv.yaml` | `Namespace` | Lab guest namespace used in live migration (`blue`, labels for CUDN) |
| `vm-fleet-db-source.yaml` | `VirtualMachine` / `VirtualMachineInstance` | Source VM shape during forklift run (scrub secrets) |
| `vmim-forklift-*.yaml` | `VirtualMachineInstanceMigration` | Source-side migration CR created by forklift |
| `networkattachment-*.yaml` | `NetworkAttachmentDefinition` | Secondary nets if used beside Primary CUDN |
| `serviceaccount-importer.yaml` | `ServiceAccount` / `RoleBinding` | Only if you rely on custom RBAC for MTV/CDI importers |
| `virt-handler-debug-notes.md` | (notes) | Optional: node selector / `virt-handler` pod on migration node |

Warm/cold paths may also use **importer** / **virt-v2v** pods (see connection
table in [NOTES.md](../../NOTES.md)). Capture Service or Route objects only if
they differ from defaults.

## Related workarounds

- **Submariner** — needed today so source `virt-handler` can dial ROSA pod
  migration listeners; hub holds mesh CRs: [hub/README.md](../../hub/README.md).
  Full narrative: [migration](../../docs/migration.md).
- **Cold migration on a Primary CUDN** — land on default network first, then
  move onto the CUDN; same doc: [migration](../../docs/migration.md#why-cold-migration-fails-for-vms-already-on-a-cudn).

## Read next

- On-prem EVPN apply order and DNS hacks: [on-prem README](../README.md)
- Hub forklift + Submariner rendered slot: [hub/README.md](../../hub/README.md)
