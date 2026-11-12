# RFE-1: Multiple Layer2 UDNs into one shared IP-VRF

**Priority:** P1  
**Catalog:** [2026-09-23-evpn-attempt-catalog.md](2026-09-23-evpn-attempt-catalog.md)  
**Deck:** [evpn-fabric-integration-rfe-23-sep-26.html](../../presentations/evpn-fabric-integration-rfe-23-sep-26.html)  
**Related:** [RFE-2](2026-09-23-rfe-02-fabric-l3vni-membership.md) (fabric L3VNI membership), [RFE-3](2026-09-23-rfe-03-primary-external-gw.md) (fabric GW)

## Summary

Allow many Primary Layer2 CUDNs / UDNs (macVRFs) to attach to a single shared IP-VRF (router) inside OVN-Kubernetes EVPN, so OpenShift nodes can behave like a **standard EVPN leaf**: many VLANs into few VRFs when peering into a leaf–spine fabric.

## Problem

A standard leaf–spine EVPN fabric maps **many VLANs into few VRFs** (~100s → ~10). OVN-K today enforces a **1:1 macVRF ↔ ipVRF** relationship. Blue-320 and green-319 cannot share a router: green cannot attach to blue’s IP-VRF, and two CUDNs cannot share one logical L3 domain — so the cluster cannot present as a normal multi-VLAN leaf into an existing fabric VRF.

**Evidence:** Hurdles **H7, H9, H12**; topologies T5–T9; transcript [Blue/green intervlan and ipVRF](010dae1f-6ce2-4c58-b8db-463e3332fa2e). OKEP acknowledges then rules out multi-L2 → one IP-VRF.

## Why this cannot be externalized to the fabric

Pushing “one VRF per CUDN” onto fabric leaves (hub-and-spoke VRFs + RT import or static leak into a core VRF — T9) is **not** how a standard ~10-VRF leaf–spine is designed. Lab attempts confirm that path does not close multi-CUDN L3:

| Constraint | Source | Effect |
|------------|--------|--------|
| Target fabric is ~**10 VRFs**, not ~100s | Standard fabric design | One OVN CUDN → one fabric VRF would require ~100s of leaf VRFs |
| **One fabric VRF ↔ one L3VNI** | H12, symmetric IRB | Cannot collapse many per-CUDN L3VNIs into one fabric VRF without membership mapping ([RFE-2](2026-09-23-rfe-02-fabric-l3vni-membership.md)) |
| Multi-RT import ≠ multi-VNI demux | H8, H12 | Importing several CUDN RTs into one fabric VRF can look fine in the RIB while VXLAN return still fails |
| Route-leak as substitute for shared VRF | H11 | Fragile at scale; not a productized leaf–spine pattern for 100s of VRFs |
| Fabric anycast intervlan also unavailable | H10 / [RFE-3](2026-09-23-rfe-03-primary-external-gw.md) | Pods never reach leaf anycast `.1` — so “just let the fabric route between VLANs” is closed too |

**Bottom line:** Because we cannot stand up ~100 fabric VRFs with route-leak, and because we cannot use the fabric’s SVIs for intervlan ([RFE-3](2026-09-23-rfe-03-primary-external-gw.md)), **CUDNs never get a shared L3 domain** — neither in OVN nor via fabric **symmetric IRB**. RFE-1 lets many L2 segments share one IP-VRF *on the OpenShift leaf tier*; [RFE-2](2026-09-23-rfe-02-fabric-l3vni-membership.md) then maps that into a **shared fabric L3VNI** so inter-CUDN traffic is routed at fabric gateways (standard CRB), not via per-VLAN VRF leaking.

## Requested capability

- Support **N Primary Layer2 EVPN networks → 1 IP-VRF** (or equivalent shared router) within a cluster.
- Intervlan between those L2 networks must use the shared IP-VRF (OVN L3 or delegated fabric L3 — see RFE-2 / RFE-3).
- API should make VRF membership explicit (e.g. shared `ipVRF` identity / reference), not implied 1:1 with the CUDN.

## Acceptance criteria

1. At least two Primary Layer2 EVPN CUDNs on different subnets attach to one IP-VRF and pass pod↔pod intervlan.
2. Adding a third L2 CUDN to the same IP-VRF does not require a new L3 VNI uniqueness conflict for the *logical* VRF membership (see RFE-2 for fabric VNI mapping).
3. Documented scale smoke: ≥50 L2 CUDNs into ≤5 IP-VRFs on a single cluster (or stated supported limit with rationale).

## Non-goals

- Asymmetric IRB as the required datapath
- Replacing the customer’s leaf–spine / CRB design
- Vendor-specific switch platform fixes
- Mandating ~100s of fabric VRFs as the supported integration model

## Scale context

OpenShift nodes as an extra EVPN leaf tier; ~100s VLANs into ~10 fabric VRFs; several clusters + external VTEPs.
