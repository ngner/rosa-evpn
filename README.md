# Cross-Cluster EVPN: On-Prem OpenShift + ROSA

Extends a Layer 2 EVPN overlay (VNI 100) between an on-premises OpenShift cluster
and a Red Hat OpenShift Service on AWS (ROSA) cluster, enabling VM-to-VM
connectivity across sites using BGP EVPN with VXLAN data plane.

## Architecture

```
┌─────────────────────┐         ┌─────────────────────┐
│   On-Prem OpenShift │         │     ROSA Cluster    │
│                     │         │                     │
│  CUDN "yellow"      │         │  CUDN "evpn-on-prem"│
│  10.100.1.0/24      │         │  10.100.1.0/24      │
│  macVRF VNI 100     │         │  macVRF VNI 100     │
│  RT 65512:100       │         │  RT 65512:100       │
│                     │         │                     │
│  FRR-k8s ASN 65512  │         │  FRR-k8s ASN 65512  │
│  VTEP: 192.168.188.x│         │  VTEP: 10.0.x.x    │
└────────┬────────────┘         └──────────┬──────────┘
         │ iBGP (outbound to RR)            │ iBGP (outbound to RR)
         │                                  │
         ▼                                  ▼
┌─────────────────────────────────────────────────────┐
│            iBGP Route Reflector (FRR)                │
│            Containerlab · 192.168.188.152            │
│            ASN 65512 · L2VPN EVPN AF                 │
└─────────────────────────────────────────────────────┘
```

Both clusters peer **outbound** to the Route Reflector on port 179. The RR
reflects EVPN type-2 (MAC/IP) and type-3 (IMET) routes between sites.
VXLAN-encapsulated data plane traffic flows directly between VTEP IPs.

## Prerequisites

| Component | Version |
|-----------|---------|
| OpenShift (on-prem) | 4.22+ |
| ROSA | 4.22+ with OVN-Kubernetes |
| OpenShift Virtualization (KubeVirt) | 4.22+ |
| FRR-k8s (MetalLB operator) | Installed on both clusters |
| Containerlab | v0.56+ |
| Site-to-site connectivity | VPN or direct link between on prem (here 192.168.188.0/24) and AWS VPC (here 10.0.[1,2,3].0/24) |

## Directory Layout

```
├── route-reflector/      # Containerlab iBGP Route Reflector
├── on-prem-cluster/      # On-prem OpenShift manifests
├── rosa-cluster/         # ROSA cluster manifests
└── NOTES.md              # Operational notes and lessons learned
```

## Deployment Order

### 1. Deploy the Route Reflector

!NOTE - to be deployed on a node on-prem at present (in this case in 192.168.188.152)

```bash
cd route-reflector
sudo containerlab deploy -t evpn-rr.clab.yml
./attach-to-br0.sh
```

### 2. Configure the On-Prem Cluster

```bash
export KUBECONFIG=/path/to/on-prem/kubeconfig

# Enable FRR and route advertisements
oc patch network.operator.openshift.io cluster \
  --type=merge --patch-file on-prem-cluster/00-enable-frr-route-advertisements.yaml

# Enable local gateway mode
oc patch network.operator.openshift.io cluster \
  --type=merge --patch-file on-prem-cluster/01-local-gateway.yaml

# Configure KubeVirt l2bridge binding
oc patch kubevirt kubevirt-kubevirt-hyperconverged -n openshift-cnv \
  --type=merge --patch-file on-prem-cluster/02-kubevirt-default-l2bridge.yaml

# Deploy EVPN networking
oc apply -f on-prem-cluster/cudn-evpn-yellow.yaml
oc apply -f on-prem-cluster/evpn-vtep.yaml
oc apply -f on-prem-cluster/frrconfiguration-peering-rosa.yaml
oc apply -f on-prem-cluster/routeadvertisement-evpn.yaml

# Deploy test VM
# presumes a namespace with request primary cudn labels etc.
oc apply -f on-prem-cluster/vm-yellow-1.yaml
```

### 3. Configure the ROSA Cluster

```bash
export KUBECONFIG=/path/to/rosa/kubeconfig

# Enable local gateway mode
oc patch network.operator.openshift.io cluster \
  --type=merge --patch-file rosa-cluster/01-local-gateway.yaml

# Configure KubeVirt l2bridge binding
oc patch hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  --type=merge --patch-file rosa-cluster/patch-hco-l2bridge.yaml

# Deploy EVPN networking
oc apply -f rosa-cluster/namespace-evpn-on-prem.yaml
oc apply -f rosa-cluster/evpn-layer2-cudn.yaml
oc apply -f rosa-cluster/evpn-vtep.yaml
oc apply -f rosa-cluster/frrconfiguration-on-prem-evpn.yaml
oc apply -f rosa-cluster/routeadvertisement-evpn-cudn.yaml


# Deploy test VM
oc apply -f rosa-cluster/vm-test-evpn.yaml

## Enable BGP with AWS route-server (not fully tested)
oc apply -f rosa-cluster/frrconfiguration-all-nodes.yaml
oc apply -f rosa-cluster/routeadvertisements-default.yaml
```

### 4. Verify

```bash
# Check BGP sessions on the Route Reflector
sudo podman exec clab-evpn-rr-rr vtysh -c "show bgp summary"
sudo podman exec clab-evpn-rr-rr vtysh -c "show bgp l2vpn evpn"

# Check EVPN routes on a cluster node's FRR pod
oc exec -n openshift-frr-k8s <frr-pod> -c frr -- vtysh -c "show bgp l2vpn evpn"
```

## Key Design Decisions

**Why a Route Reflector?**
FRR-k8s pods cannot accept inbound BGP connections (they listen on port 50179
internally, and there is no DNAT/Service exposing port 179 externally). Both
clusters must initiate outbound connections to port 179 on the RR.

**VTEP CIDR Selection**
Each cluster's VTEP CIDR must be bidirectionally routable from the other site.
On-prem uses `192.168.188.0/24` (the br-ex management network routed over VPN)
rather than `10.0.101.0/24` (br-lab VLAN 101) which is not reachable from AWS.

**Shared Subnet / IPAM**
Both clusters allocate from `10.100.1.0/24` independently. There is no
cross-cluster IPAM coordination — use `reservedSubnets` or static IP
annotations to avoid collisions in production.

## Known Limitations

- IPAM address collisions are possible when both clusters auto-assign from the same /24
- The `frrconfiguration-all-nodes.yaml` on ROSA contains environment-specific AWS VPC router IPs that must be updated per deployment
    - Example Terrraform exists to handle this which I hope to get hold of.
- VTEP-to-VTEP reachability depends on VPN routing tables including the correct CIDRs
- FRR-k8s `nodeSelector: bgp_router: "true"` label must be applied to ROSA nodes participating in EVPN

## License

Apache-2.0
