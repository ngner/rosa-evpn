# EVPN attempt catalog — OpenShift as a leaf tier on a standard EVPN fabric

**Date:** 2026-09-23 (revised 2026-09-24)  
**Companion decks:** [RFE / product ask](../../presentations/evpn-fabric-integration-rfe-23-sep-26.html) · [Engineering show-and-tell journey](../../presentations/evpn-cudn-journey-show-and-tell-24-sep-26.html)

## Integration question

Can current OVN-Kubernetes **EVPN CUDN** capabilities (Primary Layer2 + optional ipVRF, FRR-k8s, RouteAdvertisements) integrate OpenShift nodes as an **extra tier of leaves** on a **standard leaf–spine EVPN fabric**?

A standard fabric here means:

- Leaf–spine underlay
- EVPN/VXLAN overlay with Type-2 / Type-5
- Symmetric IRB (CRB-style anycast GW on leaves or borders)
- **Many VLANs (~100s) into few VRFs (~10)**
- External workloads and other VTEPs already on the same fabric
- OpenShift nodes peer EVPN to fabric leaves and act as VTEPs for pods/VMs

Lab evidence (DL380 ASN 65020, ROSA ASN 65021, fabric ASN 65004 / `Vrf_CORE` L3VNI `10000`) is used only to answer that product question — not to catalogue access-switch platform bugs.

**Verdict (summary):** Same-subnet L2 stretch *technically* works but is **not a usable leaf mode** — Primary CUDN keeps OVN IPAM and OVN `.1`; the fabric switch GW is unreachable; the OVN GW has no external routes, so pods cannot leave the subnet. Single-CUDN L3 into one fabric VRF can work with matching ipVRF. **Multi-VLAN / multi-VRF integration matching a standard fabric does not** — see RFEs 1–3.

---

## Scale goal

| Dimension | Lab today | Standard fabric target |
|-----------|-----------|------------------------|
| Role of OCP nodes | VTEPs peering to fabric leaves | Extra leaf tier |
| L2 segments (CUDNs) | ~3 (yellow, blue-320, green-319) | ~100s of VLANs |
| Fabric VRFs | `Vrf_CORE` (+ default) | ~10 VRFs |
| External workloads | Servers / VMs on the same EVPN segments | Same fabric |
| Clusters | On-prem + ROSA partners | Several clusters |

---

## What current CUDN EVPN can do (as a leaf)

| Capability | Status | Notes |
|------------|--------|-------|
| eBGP (or iBGP) EVPN peering to fabric leaves | **Works** | Multihop to leaf loopbacks; RA + CUDN labels required |
| Type-2 / same-subnet L2 stretch | **Technically works — useless alone** | OVN owns `.1` + IPAM; fabric GW unreachable; OVN GW has no external routes; Primary cannot disable IPAM |
| Leave subnet via fabric leaf anycast | **Does not work** | H10 — needs RFE-3 |
| One CUDN joins one fabric VRF (matching L3VNI + RT) | **Works** | e.g. ipVRF VNI `10000` / RT `65004:10000` → `Vrf_CORE` |
| Many CUDNs as members of one fabric VRF | **Does not work** | H7–H9, H12 — needs RFE-1 + RFE-2 |
| Use fabric anycast SVI as Primary default GW | **Does not work** | H10 — needs RFE-3 |
| Intervlan between CUDNs via fabric CRB | **Does not work** | Blocked by H10 and/or H7–H9 |
| Multi-cluster shared `/24` IPAM | **Manual only** | Complementary `reservedSubnets` — RFE-5 |

---

## Topology attempts (CUDN ↔ fabric)

| ID | Attempt | Outcome |
|----|---------|---------|
| T1 | iBGP via external RR (outbound-only FRR) | Partial — abandoned for direct leaf eBGP |
| T2 | eBGP multihop to fabric leaves | **Worked** — sessions + Type-2/Type-5 |
| T3 | Stretched L2 macVRF | **Same-subnet only** — cannot leave (OVN GW / no fabric GW) |
| T4 | macVRF + ipVRF = fabric L3VNI | **Worked** — **one** CUDN off-subnet |
| T5 | Unique ipVRF VNIs + shared fabric RT | **Failed** — RIB OK, demux fails |
| T6 | Two CUDNs both on fabric L3VNI | **Failed** — OVN VNI overlap reject |
| T7 | macVRF-only (no ipVRF) | L2 on-subnet only; **useless** as a leaf — no off-subnet path |
| T8 | macVRF + `defaultGatewayIPs` | **Failed** — OVN still owns `.1`; fabric GW unreachable |
| T9 | Per-CUDN fabric VRFs + leak into CORE | Not a standard ~10-VRF design; not closed for pods |
| T10 | Fabric CRB + Type-5 (single CUDN) | **Worked** with T4 |
| T11 | Hairpin to fabric IRB without ipVRF | **Failed** / unsupported on Primary |
| T12 | Asymmetric IRB (whole `Vrf_CORE`) | **Platform-blocked** (2026-09-24) — Asterfusion SONiC has no asymmetric/IRB mode CLI; guide states symmetric IRB only. `no vni 10000` is possible but is not asymmetric mode; briefly tested and restored. Activity log: `network-config/docs/activity-logs/t12-asymmetric-vrf-core.log` |
| T13 | VTEP underlay reachability | **Required** for VXLAN; must be bidirectionally routable |

---

## Hurdles (product + integration)

| ID | Hurdle | Relevance to leaf-tier integration |
|----|--------|--------------------------------------|
| H1 | FRR-k8s no inbound BGP on :179 | Peering ergonomics as a leaf (RFE-4) |
| H2 | Dynamic node IPs (e.g. ROSA) | Leaf peer stability (RFE-4) |
| H3 | VTEP CIDR must be fabric-routable | Standard underlay prerequisite |
| H4 | Shared-segment IPAM collisions | Multi-leaf / multi-cluster (RFE-5) |
| H5 | RA label mismatch → no Type-5 | Ops / config |
| H6 | VXLAN underlay path ≠ BGP path | Underlay must reach node VTEPs |
| H7 | Unique ipVRF VNI per CUDN — cannot share fabric L3VNI | **Blocks** many VLANs → one VRF |
| H8 | Shared RT ≠ shared L3 VNI under symmetric IRB | **Blocks** RT-only join of fabric VRF |
| H9 | 1:1 macVRF ↔ ipVRF | **Blocks** multi-VLAN shared router |
| H10 | OVN owns Primary GW `.1` | **Blocks** fabric anycast leaf GW |
| H11 | Route-leak / hub-spoke as substitute for shared VRF | Not how a standard ~10-VRF fabric is built |
| H12 | One fabric VRF ↔ one L3VNI | Standard EVPN; OVN must membership-map into it |
| H13 | Dropping fabric L3VNI / chasing asymmetric IRB does not unlock multi-CUDN | **Confirmed platform-blocked on Asterfusion** (T12 2026-09-24): no asymmetric IRB mode; removing L3VNI alone is not a supported substitute and must not be left half-applied |
| H14 | Underlay vs cluster API path conflicts | Ops (not CUDN model) |
| H15 | Manual / fragile IPAM and immutable CUDN fields | Ops + RFE-5 |
| H16 | Broad FRRConfiguration selectors | Ops (RFE-4 related) |

---

## Still does not work (relative to a standard fabric)

| Gap vs standard leaf–spine expectation | Hurdles | RFE |
|----------------------------------------|---------|-----|
| Many L2 segments in one fabric VRF | H7–H9, H12 | 1, 2 |
| Intervlan via fabric anycast (or shared OVN VRF) | H7–H10, H12 | 1, 2, 3 |
| Primary CUDN uses fabric leaf GW | H10 | 3 |
| Scale ~100s VLANs / ~10 VRFs across clusters | H7–H10, H4 | 1, 2, 5 |
| First-class multi-cluster IPAM on shared segments | H4, H15 | 5 |
| Inbound BGP / simpler leaf peering | H1, H2 | 4 |

---

## Five RFEs (index)

| ID | Title | Priority | File |
|----|-------|----------|------|
| RFE-1 | Multiple Layer2 UDNs into one shared IP-VRF | P1 | [2026-09-23-rfe-01-multi-l2-shared-ipvrf.md](2026-09-23-rfe-01-multi-l2-shared-ipvrf.md) |
| RFE-2 | Fabric L3VNI / VRF membership (symmetric IRB shared L3VNI) | P1 | [2026-09-23-rfe-02-fabric-l3vni-membership.md](2026-09-23-rfe-02-fabric-l3vni-membership.md) |
| RFE-3 | Primary UDN fabric anycast / bridge-only GW | P1 | [2026-09-23-rfe-03-primary-external-gw.md](2026-09-23-rfe-03-primary-external-gw.md) |
| RFE-4 | FRR-k8s inbound BGP on :179 | P3 | [2026-09-23-rfe-04-frr-inbound-bgp.md](2026-09-23-rfe-04-frr-inbound-bgp.md) |
| RFE-5 | First-class multi-cluster IPAM | P2 | [2026-09-23-rfe-05-multicluster-ipam.md](2026-09-23-rfe-05-multicluster-ipam.md) |

### Desired model — symmetric IRB, shared L3VNI

Standard leaf–spine CRB: **several VRFs**, each with **one L3VNI**; intervlan at fabric IRB; return on that L3VNI (symmetric). For OpenShift as an extra leaf tier:

- Many CUDN VLANs **membership-map** into those few fabric VRFs / shared L3VNIs ([RFE-2](2026-09-23-rfe-02-fabric-l3vni-membership.md)).
- **Inter-CUDN and off-subnet traffic go via the L3VNI to fabric gateways** — routing and inter-VRF policy stay on the fabric, not as OVN-local routing between CUDNs.
- Alternative entry: L2 hairpin to fabric anycast ([RFE-3](2026-09-23-rfe-03-primary-external-gw.md)) when Primary can shed OVN `.1`.

Blocked today by H7–H10 / H12. Contrast: one-VLAN–one-ipVRF + **VRF route-leak** into a core VRF “works” for a single CUDN but does not scale to ~100s of VLANs.

### Why “fix it on the fabric” is not enough (RFE-1 / 2 / 3)

A standard fabric already has few VRFs and anycast SVIs. Externalizing CUDN L3 onto that design fails for product reasons:

1. **Cannot use fabric leaf SVIs** — OVN owns Primary `.1` (RFE-3 / H10).
2. **Cannot invent ~100 fabric VRFs + leak** — contradicts ~10-VRF leaf–spine / symmetric IRB design (RFE-1 / H11–H12).
3. **Cannot RT-import unique OVN L3 VNIs into one fabric VRF** — demux fails under symmetric IRB; fabric gateways cannot complete inter-CUDN round trips (RFE-2 / H7–H8).

**Result:** “L2 stretch works” is not integration success — Primary CUDN leaves pods trapped on-subnet (OVN GW, no external routes, IPAM mandatory). With matching ipVRF, **one** network can join **one** fabric VRF. OpenShift is not yet a peer leaf for **standard many-VLAN / few-VRF symmetric IRB** fabrics without the P1 RFEs.

---

## Evidence (agent transcripts)

| Topic | Transcript |
|-------|------------|
| IPAM, eBGP leaves, Vrf_CORE, Type-5, underlay | [ROSA EVPN IPAM and ToR peering](613e2acf-27ad-4299-835e-a3fe6a412837) |
| Multi-CUDN L3, VNI overlap, macVRF-only pivot | [Blue/green intervlan and ipVRF](010dae1f-6ce2-4c58-b8db-463e3332fa2e) |
| Partner CUDNs, reachability, OVN `.1` | [ROSA partner CUDNs](c1fa8e94-9563-4d81-b5a4-e0d5a3955d88) |
| Underlay vs API routing | [Custom DNS and 10.10 routing](db47f69d-f3f4-478f-a43b-a2e4e100a237) |
| OpenShift CUDN / ASN RT | [OpenShift CUDN VLAN320](8cba2da0-2374-4e06-bdef-c3fa30557496) |
| ROSA Type-2 gap (earlier) | [ROSA multi-cluster EVPN](211feee5-18e5-42d3-a123-116651a99039) |
| PolicyGenerator EVPN stack | [EVPN PolicyGenerator conversion](c986e595-fa98-4666-97d5-a9a2a7fba620) |
| T12 asymmetric IRB Stage 0 (platform-blocked) | Activity log: `lab-infra-ocp` sibling `network-config/docs/activity-logs/t12-asymmetric-vrf-core.log` (2026-09-24) |
