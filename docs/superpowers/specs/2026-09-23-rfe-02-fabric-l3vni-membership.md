# RFE-2: Fabric L3VNI / VRF membership

**Priority:** P1  
**Catalog:** [2026-09-23-evpn-attempt-catalog.md](2026-09-23-evpn-attempt-catalog.md)  
**Deck:** [evpn-fabric-integration-rfe-23-sep-26.html](../../presentations/evpn-fabric-integration-rfe-23-sep-26.html)  
**Related:** [RFE-1](2026-09-23-rfe-01-multi-l2-shared-ipvrf.md) (multi-L2 shared IP-VRF), [RFE-3](2026-09-23-rfe-03-primary-external-gw.md) (fabric GW)

## Summary

Let a cluster IP-VRF join an **existing fabric L3VNI and route-target** on a standard leaf–spine EVPN fabric (one L3VNI per VRF, **symmetric IRB**) without requiring a unique OVN L3 VNI that the fabric cannot demux. OpenShift nodes act as an extra leaf tier that must **membership-map** into the fabric’s few VRFs so **inter-CUDN / intervlan routing happens on the fabric**, not as OVN-local routing between CUDNs.

## Desired model — symmetric IRB, shared L3VNI

On a standard CRB fabric, each tenant VRF has **one L3VNI**. Inter-subnet traffic is routed at the fabric IRB; return uses that same L3VNI (symmetric). Applied to OpenShift:

1. Many Primary L2 CUDNs (VLANs) are members of **one** fabric VRF / **one** shared L3VNI (+ RT).
2. Pods send off-subnet / inter-CUDN traffic into that VRF membership (Type-5 toward fabric, or via fabric anycast — see [RFE-3](2026-09-23-rfe-03-primary-external-gw.md)).
3. **Fabric gateways** perform intervlan and inter-VRF policy (the ~10 fabric VRFs). Cluster nodes do not become the inter-CUDN router of record.
4. Return traffic arrives on the **shared L3VNI** and demuxes correctly to the OpenShift VTEP / CUDN — the property that failed when OVN used unique L3 VNIs with only a shared RT (H8).

That is the opposite of today’s forced workaround: one VLAN → one CUDN ipVRF → one fabric VRF → **route-leak** into a core VRF (does not scale to ~100s of VLANs).

## Problem

Standard leaf–spine EVPN uses **one L3VNI per VRF**. OVN requires **unique L3 VNIs per CUDN ipVRF**. Attempts:

- Two CUDNs with the fabric’s L3 VNI → **VNI Overlap** reject (H7 / T6).
- Unique OVN VNIs + shared fabric RT → RIB may import; return traffic on the fabric L3VNI does not demux into the CUDNs (H8 / T5). Quote: *“Sharing RT is not the same as sharing L3 VNI.”*

**Evidence:** Hurdles **H7, H8, H12, H13**; transcripts [010dae1f](010dae1f-6ce2-4c58-b8db-463e3332fa2e), [613e2acf](613e2acf-27ad-4299-835e-a3fe6a412837).

## Why this cannot be externalized without product change

The fabric already has the standard shape: **few VRFs**, one L3VNI each, Type-5, symmetric IRB. Fabric-only tweaks cannot make multiple OVN CUDNs equal members of one of those VRFs:

| Constraint | Source | Effect |
|------------|--------|--------|
| Symmetric IRB demux is by **L3VNI**, not RT alone | H8, H12 | Unique OVN L3 VNIs + shared RT → return VXLAN on the fabric L3VNI has nowhere to land in the cluster — so fabric gateways cannot complete the round trip |
| OVN forbids two CUDNs on the same L3 VNI | H7 / T6 | Blocks the shared-L3VNI membership model above |
| Per-CUDN fabric VRFs + leak | T9, H11, H12 | Moves “inter-VRF” onto leak policy across ~100s of VRFs — not symmetric IRB into several shared VRFs |
| Disable fabric L3VNI / chase asymmetric IRB | H13 / T12 | Abandons the standard model this RFE targets |
| Fabric anycast as L2 hairpin | H10 / [RFE-3](2026-09-23-rfe-03-primary-external-gw.md) | Complementary path; also blocked while OVN owns `.1` |

**Bottom line:** Symmetric IRB with a **shared L3VNI** is how standard fabrics do inter-subnet (and how inter-CUDN should leave the cluster to fabric gateways). Without cluster-side **membership mapping** into that L3VNI/RT (this RFE) — and often shared IP-VRF ([RFE-1](2026-09-23-rfe-01-multi-l2-shared-ipvrf.md)) or GW handoff ([RFE-3](2026-09-23-rfe-03-primary-external-gw.md)) — OpenShift cannot adopt that model.

## Requested capability

- Map cluster IP-VRF membership to an **external fabric L3VNI + RT** (import/export) so Type-5 and **symmetric IRB** return path work.
- Avoid forcing a unique OVN VNI that collides with fabric demux, **or** provide an explicit VNI alias / membership model the fabric understands.
- Support multiple L2 CUDNs (with RFE-1) as equal members of one fabric VRF so **inter-CUDN traffic is routed on the fabric** via the shared L3VNI / fabric gateways.

## Acceptance criteria

1. Two (or more) Primary EVPN CUDNs participate in one fabric VRF (same L3VNI/RT as fabric leaves) with working Type-5 off-subnet / inter-CUDN via fabric gateways and return path.
2. No “RIB looks good, dataplane blackhole” for shared-RT / unique-VNI configurations — either API rejects unsafe combos or dataplane works.
3. Documented pattern for joining existing fabric VRFs without per-CUDN switch VRF hub-and-spoke + route-leak as the only option.
4. Explicit non-requirement: inter-CUDN routing need not be performed inside OVN if fabric symmetric IRB owns it.

## Non-goals

- Asymmetric IRB as the primary design
- Vendor-specific switch workarounds
- Requiring one OVN CUDN = one fabric VRF forever
- Replacing fabric inter-VRF policy with cluster-local routing

## Scale context

OpenShift as an extra EVPN leaf tier; ~100s VLANs into ~10 fabric VRFs via shared L3VNI membership; several clusters + external VTEPs; inter-subnet on fabric gateways.
