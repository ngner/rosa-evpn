# ROSA partner CUDNs for blue-320 and green-319

## Goal

Add ROSA-side partner `ClusterUserDefinedNetwork` manifests for the lab EVPN segments `blue-320` and `green-319`, with complementary `reservedSubnets` so on-prem and ROSA auto-assign from non-overlapping pools in the shared `/24`s. Supersede `rosa-cluster/evpn-layer2-cudn.yaml` with the blue-320 partner file.

## Decisions

- **Naming:** Align with lab — files `cudn-evpn-blue-320.yaml` / `cudn-evpn-green-319.yaml`, `metadata.name` `blue-320` / `green-319`.
- **Labels:** Keep both sets for compatibility:
  - `network: "evpn-on-prem"` (existing ROSA selectors / docs)
  - `evpn: "true"`
  - `advertise: "evpn"`
- **VNIs / route targets:** Match lab partners (update ROSA blue ipVRF from `10000` to `50320`).
- **IPAM pattern:** Reserve the peer cluster’s auto-assign pool; leave this cluster’s pool unreserved.
- **Refs:** Update `README.md` apply paths and the blue CUDN block in `comined.yaml`; add green to `comined.yaml`.

## IPAM pairing

| Segment | Subnet | On-prem auto-assign (free on lab, reserved on ROSA) | ROSA auto-assign (free on ROSA, reserved on lab) |
|---------|--------|-----------------------------------------------------|--------------------------------------------------|
| blue-320 | `172.25.220.0/24` | `172.25.220.128/27` | `172.25.220.160/27` |
| green-319 | `172.25.219.0/24` | `172.25.219.128/27` | `172.25.219.160/27` |

Shared on both sides (unchanged from lab): infrastructure `.0/28`, static `.16/28` + `.32/27` + `.64/28`, unallocated `.80/28`–`.112/28`, headroom `.192/26`. MTU `1400`, `ipam.lifecycle: Persistent`, `role: Primary`, `topology: Layer2`, `transport: EVPN`, `vtep: evpn-vtep`.

## EVPN identity (match lab)

| Segment | macVRF VNI / RT | ipVRF VNI / RT |
|---------|-----------------|----------------|
| blue-320 | `10320` / `65004:10320` | `50320` / `65004:10000` |
| green-319 | `10319` / `65004:10319` | `50319` / `65004:10000` |

## File changes

1. **Add** `rosa-cluster/cudn-evpn-blue-320.yaml` — ROSA partner of lab blue-320.
2. **Add** `rosa-cluster/cudn-evpn-green-319.yaml` — ROSA partner of lab green-319.
3. **Delete** `rosa-cluster/evpn-layer2-cudn.yaml`.
4. **Update** `README.md` — replace `oc apply -f rosa-cluster/evpn-layer2-cudn.yaml` with applies for both new CUDN files.
5. **Update** `rosa-cluster/comined.yaml` — replace `evpn-on-prem-cudn` block with blue-320 partner content; append green-319 partner CUDN.

## Out of scope

- Applying manifests to a live cluster
- New green namespace / test workload manifests
- VTEP, FRR, or RouteAdvertisements changes (already select `evpn: "true"`)
- Changes under lab-infra-ocp or `on-prem-cluster/`

## Live-cluster migration note (operators only)

If `ClusterUserDefinedNetwork/evpn-on-prem-cudn` already exists, apply creates `blue-320` as a new object (no rename). Delete the old CUDN only after confirming workloads use `primary-cudn: blue-320`. Expect EVPN re-convergence when blue ipVRF VNI changes `10000` → `50320`. Green binds only after a namespace carries `primary-cudn: green-319`.

## Success criteria

- ROSA blue/green CUDN files mirror lab except complementary auto-assign reservation and retained `network: "evpn-on-prem"` label.
- No remaining references to `evpn-layer2-cudn.yaml` in README apply steps.
- `comined.yaml` reflects the same blue and green partner specs.
