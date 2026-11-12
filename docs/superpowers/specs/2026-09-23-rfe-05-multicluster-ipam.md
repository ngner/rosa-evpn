# RFE-5: First-class multi-cluster IPAM for shared EVPN segments

**Priority:** P2  
**Catalog:** [2026-09-23-evpn-attempt-catalog.md](2026-09-23-evpn-attempt-catalog.md)  
**Deck:** [evpn-fabric-integration-rfe-23-sep-26.html](../../presentations/evpn-fabric-integration-rfe-23-sep-26.html)

## Summary

Provide first-class **multi-cluster IPAM** for shared EVPN Layer2 segments so partner clusters (and external static ranges) do not rely solely on manually mirrored complementary `reservedSubnets`.

## Problem

Stretched L2 CUDNs share a `/24` across on-prem and ROSA. Without coordination, auto-assign collides. Current mitigation: complementary `reservedSubnets` (e.g. on-prem `.128/27`, ROSA `.160/27`) maintained by hand in two repos / ACM policies. Invalid or non-aligned CIDRs break CUDN create; immutable fields need recreate (H15).

**Evidence:** Hurdles **H4, H15**; design [2026-09-23-rosa-partner-cudns-design.md](2026-09-23-rosa-partner-cudns-design.md); transcripts [613e2acf](613e2acf-27ad-4299-835e-a3fe6a412837), [c1fa8e94](c1fa8e94-9563-4d81-b5a4-e0d5a3955d88).

## Requested capability

- Declare a **shared segment identity** (EVPN VNI / RT / subnet) and **cluster-scoped pools** without duplicating fragile reserve lists.
- Optional: claim/release API, or integration with existing IPAM (Whereabouts / MetalLB-style pool CRDs / OVN IPAM) for multi-cluster EVPN.
- Clear handling of infrastructure / static / external ranges alongside auto-assign pools.

## Acceptance criteria

1. Two clusters can share an EVPN `/24` with non-overlapping auto-assign without manually editing peer `reservedSubnets` on every change.
2. Adding a third cluster claims a free pool without conflict.
3. Invalid CIDR alignment is rejected with actionable errors; pool changes do not require opaque CUDN recreate when avoidable.

## Non-goals

- Replacing all Kubernetes IPAM
- External DHCP for fabric hosts (out of OVN scope)
- Solving L3 VRF membership (RFE-1/2)

## Scale context

OpenShift nodes as an extra EVPN leaf tier; several clusters + external hosts on shared segments.
