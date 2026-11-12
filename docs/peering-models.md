# Peering models: route reflector vs network fabric

## Route reflector (Phase 1)

| | |
|--|--|
| **Control plane** | Both clusters initiate iBGP to an external RR on :179 |
| **Why** | FRR-k8s cannot take inbound BGP; RR also absorbs dynamic peer IPs |
| **Data plane** | VXLAN between VTEPs if underlay routes exist |
| **Fabric relationship** | None — overlay is independent of switch VLAN/SVI membership |

### Limits that matter for migration and VLANs

- You do **not** expose or join an *actual* fabric VLAN by peering only an RR.
  Guests on a CUDN may share a stretched L2 with the other cluster, but they
  are not leaf members of the lab’s VLAN/SVI/IRB design.
- Off-subnet / intervlan via fabric anycast gateways is unavailable in this
  model (and still limited even with fabric peering — see RFE docs).
- Live migration still needs **pod-network** reachability between clusters
  (virt-handler → receiver :9185). EVPN guest L2 does not replace that path.

## Network fabric (Phase 2 — current lab path)

| | |
|--|--|
| **Control plane** | Cluster FRR peers fabric route-reflector TORs (eBGP multihop to Lo0) |
| **Why** | Match fabric macVRF / ipVRF RTs so CUDNs participate in lab VNIs |
| **Data plane** | VXLAN using cluster VTEP CIDRs routable to the fabric / peer site |
| **Fabric relationship** | CUDN RTs aligned with fabric (e.g. 319/320 families) |

### Still not “full leaf”

Fabric peering is necessary to *aim at* real VLAN/VNI membership, but today
OVN Primary CUDN behaviour (OVN-owned `.1`, 1:1 macVRF↔ipVRF, etc.) still
blocks standard many-VLAN / few-VRF leaf behaviour. Deep dive:
[evpn-attempt-catalog](superpowers/specs/2026-09-23-evpn-attempt-catalog.md).

### ROSA-specific peering note

Do **not** set `sourceaddress: lo` on rosa-virt. VTEPs are VPC/machine IPs;
forcing `lo` sources BGP from an OVN host loopback the fabric does not route.
Leave source unset so TCP uses br-ex. dl380 may use `lo` when VTEPs are
node loopbacks — see site READMEs.

## Choosing a model

| Need | Prefer |
|------|--------|
| Demo outbound-only BGP / no fabric change | Phase 1 RR (`route-reflector-example/`) |
| Join lab VNIs 319/320 with dl380 / external VTEPs | Phase 2 fabric (`rosa-cluster/`) |
| Expose a real switch VLAN/SVI as if OCP were a leaf | Fabric membership **and** product gaps in RFE-1/2/3 — RR alone cannot |
