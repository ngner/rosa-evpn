# RFE-3: Primary UDN fabric anycast / bridge-only gateway

**Priority:** P1  
**Catalog:** [2026-09-23-evpn-attempt-catalog.md](2026-09-23-evpn-attempt-catalog.md)  
**Deck:** [evpn-fabric-integration-rfe-23-sep-26.html](../../presentations/evpn-fabric-integration-rfe-23-sep-26.html)  
**Related:** [RFE-1](2026-09-23-rfe-01-multi-l2-shared-ipvrf.md), [RFE-2](2026-09-23-rfe-02-fabric-l3vni-membership.md)

## Summary

Allow Primary EVPN CUDNs to use the **fabric leaf anycast IRB** as the default gateway (or an explicit **bridge-only L2** mode) so OpenShift nodes can stretch L2 like a host leaf while the **standard fabric** owns intervlan / off-subnet routing. Today OVN always owns `.1` and answers ARP, so traffic never reaches the fabric SVI.

## Problem

On a standard CRB / symmetric-IRB leaf–spine, anycast gateways sit on fabric leaves. Classic host integration: L2 stretch + fabric GW for L3. On Primary CUDNs:

- Pods ARP OVN MAC (`0a:58:…`) for `.1`, not fabric anycast.
- `defaultGatewayIPs` still leaves OVN as the L3 owner (T8 / T11).
- Off-subnet from macVRF-only CUDNs fails (Destination Host Unreachable from OVN).

**Evidence:** Hurdle **H10**; topologies T7, T8, T11; transcript [ROSA partner CUDNs](c1fa8e94-9563-4d81-b5a4-e0d5a3955d88).

## Why this cannot be externalized to the fabric

The fabric **already** provides anycast SVIs and intervlan in its VRFs. No fabric feature unlocks CUDN intervlan while OVN keeps L3 on the Primary UDN:

| Constraint | Source | Effect |
|------------|--------|--------|
| OVN owns Primary GW `.1` and answers ARP | H10, T8, T11 | Packets never leave the node toward fabric leaf anycast |
| `defaultGatewayIPs` does not change ownership | T8 | Config looks like “use fabric GW”; dataplane still OVN |
| External hosts *can* use fabric SVIs | Standard CRB | Proves the fabric path; the break is the Primary UDN L3 model |
| Without fabric GW, intervlan needs OVN shared IP-VRF or Type-5 join | [RFE-1](2026-09-23-rfe-01-multi-l2-shared-ipvrf.md), [RFE-2](2026-09-23-rfe-02-fabric-l3vni-membership.md) | Those are also blocked today |
| Fabric-side “more VRFs + leak” | H11, H12, scale goal | Does not help if packets never reach the leaf; fails ~10-VRF design |

**Bottom line:** Because pods cannot use the fabric’s SVIs, and because we cannot create ~100 fabric VRFs with route-leak as a substitute ([RFE-1](2026-09-23-rfe-01-multi-l2-shared-ipvrf.md)), **CUDNs never route to each other** via a standard leaf–spine design until OVN hands off the gateway (this RFE) **or** adopts **symmetric IRB shared-L3VNI membership** so Type-5 / fabric gateways own intervlan ([RFE-2](2026-09-23-rfe-02-fabric-l3vni-membership.md)).

Both paths put **inter-CUDN L3 on the fabric**, not as OVN-local routing between CUDNs — they differ in how packets enter the fabric (L2 to anycast vs L3VNI membership).

## Requested capability

One of (product may choose):

1. **External / fabric gateway mode** for Primary EVPN UDN: do not ARP-respond as `.1`; learn / use fabric anycast GW MAC; or
2. **Bridge-only L2 Primary** mode: no OVN L3 on the segment; default route points at fabric SVI.

Either must work with EVPN Type-2 stretch to external hosts and multi-cluster partners.

## Acceptance criteria

1. Pod on Primary EVPN CUDN ARPs fabric anycast MAC for the configured GW IP (or equivalent documented behavior).
2. Off-subnet / intervlan via fabric CRB succeeds without a per-CUDN OVN ipVRF when that is the chosen mode.
3. `defaultGatewayIPs` (or successor field) has documented semantics that match observed dataplane — no silent OVN ownership of `.1`.

## Non-goals

- Replacing OVN L3 for customers who want Type-5 / ipVRF (RFE-1/2 remain valid)
- Secondary/localnet-only workarounds as the supported answer for Primary tenants
- Asymmetric IRB
- Additional fabric SVI/VRF features as a substitute for OVN GW handoff

## Scale context

OpenShift as an extra EVPN leaf tier; external workloads and pods share VLANs; fabric IRB is the natural L3 for ~10 VRFs.
