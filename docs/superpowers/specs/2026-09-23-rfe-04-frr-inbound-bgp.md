# RFE-4: FRR-k8s inbound BGP on port 179

**Priority:** P3  
**Catalog:** [2026-09-23-evpn-attempt-catalog.md](2026-09-23-evpn-attempt-catalog.md)  
**Deck:** [evpn-fabric-integration-rfe-23-sep-26.html](../../presentations/evpn-fabric-integration-rfe-23-sep-26.html)

## Summary

Make FRR-k8s (or the OVN-K EVPN BGP stack) able to **accept inbound BGP peers on TCP 179**, or ship a first-class Route Reflector / Service DNAT story, so OpenShift leaf-tier nodes can peer like other VTEPs without forcing outbound-only sessions or third-party RRs.

## Problem

FRR-k8s listens on **50179**, not 179. Fabric leaves, RRs, and other clusters expect standard BGP. Workarounds:

- Outbound-only sessions from every node to fabric leaf loopbacks (works but awkward at scale)
- External RR that initiates to nodes (T1)
- Peer ranges for dynamic node IPs still assume someone can dial the cluster

**Evidence:** Hurdles **H1, H2, H16**; `NOTES.md` / `README.md` in rosa-evpn; transcript [613e2acf](613e2acf-27ad-4299-835e-a3fe6a412837).

## Requested capability

- Accept inbound BGP on **:179** (hostNetwork, LoadBalancer/NodePort DNAT, or documented equivalent), **or**
- First-class supported RR / listen-range pattern for multi-cluster EVPN without requiring customers to run ad-hoc RRs.

Also: selective FRRConfiguration binding so default-VRF configs with `nodeSelector: {}` do not match unintended VRF configs (H16).

## Acceptance criteria

1. A fabric leaf (or RR) can initiate BGP to a cluster node / service on port 179 and establish EVPN AF successfully.
2. Documented pattern for dynamic-IP worker fleets without per-node static peer list churn.
3. FRRConfiguration selectors do not silently attach unrelated configs when `{}` is used on one object.

## Non-goals

- Replacing FRR with another daemon as the only answer
- Fabric underlay design changes
- Solving VTEP routing (H3/H6) — separate ops concern

## Scale context

OpenShift nodes as an extra EVPN leaf tier; several clusters peering to the same fabric leaf / RR set.
