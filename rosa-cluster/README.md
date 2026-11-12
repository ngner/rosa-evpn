# ROSA-virt EVPN example bundle

These are the rendered objects we applied on rosa-virt (via ACM in the lab).
This folder is the readable result — the policy definitions live elsewhere.

This is the **current** fabric path (Phase 2). Historical route-reflector
lab: [`route-reflector-example/`](../route-reflector-example/README.md).

## How this differs from dl380

| Item | dl380 | rosa-virt |
|------|-------|-----------|
| BGP ASN | `65020` | `65021` (`ROSA_EVPN` on the TORs) |
| VTEP CIDR | `10.101.103.0/24` (node loopbacks) | `10.10.0.0/17` (machine/VPC IPs) |
| BGP `sourceaddress` | `lo` (Lo0 VTEPs) | **unset** — must source from br-ex VPC IP |
| CUDNs | yellow + green-319 + blue-320 | green-319 + blue-320 only |
| Peers | TOR Lo0 `10.101.103.3` / `.4` | same (no switch changes) |

Setting `sourceaddress: lo` on ROSA makes BGP SYN from OVN's host loopback
(e.g. `172.20.0.1`), which the fabric does not route — sessions stay `Connect`.
Leave `sourceaddress` unset so TCP uses the node VPC address on br-ex.

## Apply

For a one-shot lab apply, use `combined.yaml` or apply in this order:

1. `network-operator-evpn.yaml` — FRR provider + routeAdvertisements + local gateway (`routingViaHost`, Global IP forwarding). Partial `Network` spec: server-side apply keeps unrelated fields.
2. `evpn-vtep.yaml` — VTEP `10.10.0.0/17`, mode `Unmanaged`
3. `cudn-evpn-green-319.yaml` / `cudn-evpn-blue-320.yaml`
4. `frrconfiguration-peering.yaml` — ASN 65021, eBGP multihop to TOR Lo0 `10.101.103.3` / `.4` (ASN 65004), `sourceaddress` unset
5. `routeadvertisement-evpn.yaml` — selects `advertise: evpn` CUDNs (`advertise-evpn-rosa`)
6. `kubevirt-default-l2bridge.yaml` — VM `l2bridge` binding (`managedTap`, `migration: {}`)
7. Optional: `namespace-evpn-example.yaml`, `vm-test-evpn.yaml`
8. Optional: `StorageMapFixforbadmigration.yaml` — MTV `StorageMap` sample in `mtv-integrations` (`px-rwx-block-kubevirt` → `efs-sc`). Not included in `combined.yaml`.

`combined.yaml` is items 1–6 only.

```bash
oc apply --server-side --force-conflicts -f network-operator-evpn.yaml
oc apply -f evpn-vtep.yaml
oc apply -f cudn-evpn-green-319.yaml -f cudn-evpn-blue-320.yaml
oc apply -f frrconfiguration-peering.yaml
oc apply -f routeadvertisement-evpn.yaml
oc apply -f kubevirt-default-l2bridge.yaml
```

## Labels

- CUDNs: `evpn: "true"`, `advertise: "evpn"`
- FRRConfiguration: `evpn: "true"`
- Namespaces on a CUDN: `primary-cudn: <cudn-name>` plus `k8s.ovn.org/primary-user-defined-network: ""`

## Read next

- What else rosa-virt needs beyond this folder: [rosa-virt component inventory](../docs/rosa-virt-components.md)
- RR vs fabric, and why `sourceaddress` stays unset here: [peering models](../docs/peering-models.md)
- How we got from the route reflector to this bundle: [evolution](../docs/evolution.md)
