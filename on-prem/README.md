# On-prem (dl380) examples

Rendered objects and a few lab helpers from the on-prem OpenShift cluster
(dl380). We used ACM in the lab to render and apply these too. This folder
is the readable result.

The **current** cross-site path is fabric peering on rosa-virt
([`rosa-cluster/`](../rosa-cluster/README.md)). Several files here are the
Phase 1 route-reflector era, kept so that path stays readable. There is no
TOR-loopback FRRConfiguration in this folder.

Virt-side notes beyond the l2bridge patch: [virt/README.md](virt/README.md).

## Which era

| File | Era | Role |
|------|-----|------|
| `00-enable-frr-route-advertisements.yaml` | Prerequisite | Network patch: FRR provider + route advertisements |
| `01-local-gateway.yaml` | Prerequisite | Network patch: `routingViaHost` + Global IP forwarding |
| `02-kubevirt-default-l2bridge.yaml` | Prerequisite | KubeVirt `l2bridge` binding and default interface |
| `frrconfiguration-peering-rosa.yaml` | Phase 1 RR | iBGP ASN 65512 to RR `192.168.188.152` |
| `evpn-vtep.yaml` | Phase 1 RR | VTEP `192.168.188.0/24` (br-ex, VPN-routable), `Unmanaged` |
| `cudn-evpn-yellow.yaml` | Phase 1 | Early stretch segment, subnet `10.100.1.0/24`, macVRF VNI 100 |
| `vm-yellow-1.yaml` | Phase 1 | Example VM in namespace `yellow` |
| `routeadvertisement-evpn.yaml` | Shared selector | Advertises `advertise: evpn` CUDNs into FRRConfigurations labeled `evpn: "true"` (the RR peer in this folder) |
| `cudn-evpn-blue-320.yaml` | Fabric-shaped CUDN | `172.25.220.0/24`, macVRF VNI 10320, RT `65004:10320`, `reservedSubnets` paired with rosa-virt |
| `DNS-hacks/` | Operational | On-prem DNS so dl380 can resolve ROSA API and VPC-endpoint names |

`cudn-evpn-blue-320.yaml` carries fabric route targets. With the
FRRConfiguration checked in here, RouteAdvertisement still injects it toward
the route reflector, not toward TOR Lo0 `10.101.103.3` / `.4`. green-319 is
not in this folder.

`frrconfiguration-peering-rosa.yaml` leaves `sourceaddress` unset: the RR
address is on-link on `192.168.188.0/24`. The dl380 `sourceaddress: lo` case
is fabric loopback VTEPs (`10.101.103.0/24`), described in the rosa-virt
comparison table. That peering object is not in this folder.

## Apply

Patches (do not client-apply these as full objects):

```bash
oc patch network.operator.openshift.io cluster --type=merge --patch-file 00-enable-frr-route-advertisements.yaml
oc patch network.operator.openshift.io cluster --type=merge --patch-file 01-local-gateway.yaml
oc patch kubevirt kubevirt-kubevirt-hyperconverged -n openshift-cnv \
  --type=merge --patch-file 02-kubevirt-default-l2bridge.yaml
```

Phase 1 objects:

```bash
oc apply -f evpn-vtep.yaml
oc apply -f cudn-evpn-yellow.yaml
oc apply -f frrconfiguration-peering-rosa.yaml
oc apply -f routeadvertisement-evpn.yaml
oc apply -f vm-yellow-1.yaml
```

`vm-yellow-1` expects namespace `yellow`. The yellow CUDN selects namespaces
with label `name` in `blue` or `yellow` (it does not use `primary-cudn`).

Fabric-shaped CUDN, same subnet family as rosa-virt blue-320:

```bash
oc apply -f cudn-evpn-blue-320.yaml
```

Namespaces for blue-320 use `primary-cudn: blue-320`. On-prem auto-assign
for that CUDN is `172.25.220.128/27`; ROSA’s auto-assign `.160–.191` is
reserved here. Read both blue-320 files before changing IPAM.

### `DNS-hacks/`

Lab DNS so this cluster can resolve ROSA names that public resolvers miss.

- `custom-dns-configmap.yaml` — Corefile, hosts for the ROSA API/console names, and a VPC-endpoint zone
- `custom-dns-deployment.yaml` — CoreDNS `Deployment` and `Service` `dns` in namespace `custom-dns` (port 8053)
- `custom-dns-operator-config.yaml` — cluster `DNS` `default` forwards `ap-southeast-1.vpce.amazonaws.com` and `p3.openshiftapps.com` at that Service

Apply the namespace, ConfigMap, and Deployment before the operator DNS
servers block, or the forward target has nowhere to go.

## Read next

- Timeline, including this RR-era peering: [evolution](../docs/evolution.md)
- Why the RR path does not join fabric VLANs: [peering models](../docs/peering-models.md)
- Migration, Submariner, and the cold-CUDN landing step: [migration](../docs/migration.md)
- Containerlab RR that `192.168.188.152` points at: [route-reflector example](../route-reflector-example/README.md)
