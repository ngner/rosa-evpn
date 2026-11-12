# rosa-virt component inventory

What this repo actually snapshots for rosa-virt, and what has to exist on the
cluster for the migration story to work. Rendered objects we applied are
under [`rosa-cluster/`](../rosa-cluster/README.md).

## Documented in `rosa-cluster/`

- **Network operator** (`network-operator-evpn.yaml`) — FRR provider, `routeAdvertisements: Enabled`, local gateway (`routingViaHost: true`, `ipForwarding: Global`).
- **VTEP** (`evpn-vtep.yaml`) — `Unmanaged`, CIDR `10.10.0.0/17` (machine/VPC addresses). OVN uses an address already on the node; it does not allocate a new loopback.
- **CUDNs** (`cudn-evpn-blue-320.yaml`, `cudn-evpn-green-319.yaml`) — Primary L2, MTU 1350, EVPN transport on `evpn-vtep`. blue-320 is `172.25.220.0/24` (macVRF VNI 10320 / RT `65004:10320`). green-319 is `172.25.219.0/24` (macVRF VNI 10319 / RT `65004:10319`). Each also has a per-CUDN ipVRF (20320 / 20319).
- **FRRConfiguration** (`frrconfiguration-peering.yaml`) — underlay peers: local ASN 65021, eBGP multihop to TOR loopbacks `10.101.103.3` and `10.101.103.4` (ASN 65004). `sourceaddress` is unset. Label `evpn: "true"`.
- **RouteAdvertisement** (`routeadvertisement-evpn.yaml`) — `advertise-evpn-rosa` advertises `PodNetwork` for CUDNs labeled `advertise: evpn` into that FRRConfiguration. `targetVRF: auto`.
- **KubeVirt l2bridge** (`kubevirt-default-l2bridge.yaml`) — binding `l2bridge` with `domainAttachmentType: managedTap` and `migration: {}` on `kubevirt-kubevirt-hyperconverged` in `openshift-cnv`.
- **Example namespace and VM** (`namespace-evpn-example.yaml`, `vm-test-evpn.yaml`) — namespaces selected with `primary-cudn`, plus a small smoke VM on blue-320.
- **StorageMap fix sample** (`StorageMapFixforbadmigration.yaml`) — Forklift `StorageMap` `storage-map-dl380-to-rosa-efs` in `mtv-integrations`: source storage class `px-rwx-block-kubevirt` to destination `efs-sc` (RWX filesystem). Providers named in the map: `dl380-mtv` and `rosa-virt-mtv`.
- **`combined.yaml`** — ordered one-shot of the network, VTEP, both CUDNs, FRRConfiguration, RouteAdvertisement, and KubeVirt binding. It omits the example namespace, VM, and StorageMap.

## Required on rosa-virt for the full story but not fully snapshotted here

These have to be present on the cluster. This repo does not carry a full export of them.

- **OpenShift Virtualization** — operator subscription and HyperConverged (HCO) in `openshift-cnv`. The KubeVirt manifest above only sets the l2bridge binding; it assumes the operator is already installed.
- **MTV provider-side objects** — the StorageMap sample points at providers `rosa-virt-mtv` and `dl380-mtv` in `mtv-integrations`. The Provider CRs, credentials, and any NetworkMap are not in this folder. The forklift controller itself runs on the hub.
- **Submariner gateway and routeagent** — the live-migration workaround mesh. We installed it with ACM. Readable examples belong under [`hub/`](../hub/README.md). Why it is in the path: [migration notes](migration.md).
- **Node labels and VPN routing** — VTEP and BGP only work on nodes whose machine address in `10.10.0.0/17` is reachable from on-prem over the site VPN. The snapshot FRRConfiguration uses `nodeSelector: {}` (all nodes). In the lab, when some workers had no path to the TOR loopbacks, we limited BGP to nodes labeled `bgp_router: "true"`. That label selector is not in the YAML here. The VPN and any source-routing that sends API traffic out br-ex are cluster/host config, not objects in this folder.

## Operational gotchas

- **`sourceaddress` unset.** Do not set `sourceaddress: lo` on rosa-virt. `lo` sources BGP from an OVN host loopback the fabric does not route, and the session stays `Connect`. Unset lets TCP use the br-ex VPC address. dl380 loopback VTEPs are a different case — see [peering models](peering-models.md).
- **VTEP `10.10.0.0/17`.** Copying the dl380 loopback range `10.101.103.0/24` onto ROSA points VXLAN at addresses the nodes do not own.
- **ASN 65021.** Local router ASN on the FRRConfiguration. TOR neighbors stay ASN 65004. The peer-group on the switches is already `ROSA_EVPN`.
- **MTU 1350 on the CUDNs.** Both green-319 and blue-320 set `mtu: 1350` so guest frames fit the VPN / VXLAN path.
- **Complementary `reservedSubnets` vs dl380.** Both CUDNs keep ROSA’s own pools (static `.32–.63`, auto-assign `.160–.191`) and keep dl380’s ranges out of ROSA’s allocator. The exact prefixes differ by CUDN — blue-320 reserves dl380 static `.64–.95`; green-319 leaves `.64–.95` and auto-assign `.128–.159` unreserved for dl380. Read the comments in each file before editing IPAM. The on-prem blue-320 manifest uses the same subnet with its own reserve list; treat the two files as a pair.
