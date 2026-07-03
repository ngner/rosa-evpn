# Lessons Learned and Troubleshooting

## ROSA Dynamic Node IPs is a pain for BGP peers

A route refelctor with IP range for peers was a great answer.  Which also solved inbound BGP TCP connections issue below.


## FRR-k8s Cannot Accept Inbound BGP

FRR-k8s pods listen on port 50179 internally (not 179 externally). There is no
DNAT rule or Kubernetes Service exposing port 179 to external peers.
This means both ends of a cross-cluster BGP peering can only
**initiate outbound** connections — they cannot receive them.

**Solution**: Deploy an iBGP Route Reflector (e.g. Containerlab FRR) that
listens on standard port 179. Both clusters connect outbound to the RR (also solve dynamic IP issue).

## Default VRF frrConfiguration nodeselectors

We have to use FRR rawconfig to enable the right type of redistribution and learning routes back in to the EVPN VRF is not yet tested (DEFAULT ??).  Need to consider overlaps of IP ranges in ROSA maybe as well.
Acceptable path for routing, onsite vs ROSA, should just manage itself.
If you advertise routes in the default VRF (`frrConfigurationSelector: {}`) 
it will match ALL FRRConfigurations. Need to test further on these Frr cofnigs.



## Node Selector Considerations on ROSA

Using `nodeSelector: {}` (all nodes) for the EVPN FRRConfiguration on ROSA
can cause issues because some nodes may not have VPN connectivity to the
Route Reflector. Use `bgp_router: "true"` labels on nodes that have the
required network path.

## IPAM / Address Collision

Both clusters independently allocate from `10.100.1.0/24`. Without
cross-cluster IPAM coordination, address collisions are possible.

**Mitigations**:
- Use `reservedSubnets` in the CUDN spec to carve out static ranges
- Use `v1.multus-cni.io/default-network` annotation for static IP assignment
- Split the /24 into non-overlapping ranges per cluster

## VTEP CIDR Must Be Bidirectionally Routable

The VTEP CIDR defines which local IP the node uses as the VXLAN tunnel
source. This IP must be reachable from the remote cluster.

- On-prem: Use `192.168.188.0/24` (br-ex IPs routed over VPN), NOT
  `10.0.101.0/24` (the labs secondary interfaces VLAN 101 — not routed through VPN to AWS at the moment)
- ROSA: Use the AWS VPC node IPs (`10.0.x.0/24`) which are natively
  reachable from on-prem via the VPN
