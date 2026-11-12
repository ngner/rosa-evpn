# Evolution of this lab

This repo captures what we tried and what we run now for cross-site EVPN
and VM migration between on-prem OpenShift (dl380) and ROSA (rosa-virt).

**Provenance:** In the lab we used ACM to install Submariner and to render/apply
the networking objects. This repository keeps the **resulting** YAML (and notes)
for readability — not the PolicyGenerator / policy definitions.

## Phase 1 — Cross-cluster EVPN via route reflector

**Problem:** FRR-k8s does not accept inbound BGP on TCP 179 (listens on
50179 with no external DNAT). Dynamic ROSA node IPs make static peer lists
painful. Both sites needed a place that *listens* on 179.

**What we did:** Run a Containerlab FRR iBGP route reflector on-prem
(example under `route-reflector-example/`). Both clusters dial out to the
RR; VXLAN data plane still goes VTEP-to-VTEP when underlay routing allows.

**What it proved:** L2 EVPN stretch between sites can work without each
cluster accepting inbound BGP.

**What it did not give us:** Membership in the lab network fabric’s VLANs /
SVIs. An RR-only overlay is not the same as OpenShift acting as a fabric
leaf. See [peering-models.md](peering-models.md).

Rendered artefacts: `route-reflector-example/`, early `on-prem/` peering
toward `192.168.188.152` (ASN 65512).

## Phase 2 — Peer the lab EVPN fabric (current)

**Problem:** We needed CUDNs that join the same VNIs/RTs as the lab fabric
(e.g. green-319 / blue-320) so VMs could talk like other VTEPs on those
segments — and so live migration could share that L2.

**What we did:** On rosa-virt, rendered Network/VTEP/CUDN/FRRConfiguration/
RouteAdvertisement/KubeVirt objects under `rosa-cluster/` peer TOR
loopbacks (`10.101.103.3` / `.4`, fabric ASN 65004) from rosa ASN 65021.
On-prem uses complementary CUDNs and fabric-oriented peering where applied.

**What it proved:** Same-subnet L2 EVPN with fabric RTs works for the lab
segments we configured; complementary `reservedSubnets` avoid IPAM clashes.

**Remaining gaps:** Multi-VLAN / shared ipVRF fabric leaf behaviour, fabric
gateway handoff, and inbound BGP on nodes — see `docs/superpowers/specs/`
RFEs. Migration still needs a pod-network path between clusters — see
[migration.md](migration.md).

## How to read the tree

| Folder | Era | Role |
|--------|-----|------|
| `route-reflector-example/` | Phase 1 | Historical RR lab |
| `on-prem/` (RR-era peering files) | Phase 1 | Kept for evolution |
| `rosa-cluster/` | Phase 2 (current) | rosa-virt rendered EVPN bundle |
| `on-prem/` CUDN blue/yellow (+ future green) | Mixed | dl380 examples |
| `hub/` | Cross-cutting | Hub MTV / Submariner examples |
