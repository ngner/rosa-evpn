# Route reflector example (Phase 1, historical)

Containerlab FRR iBGP route reflector from the first cross-site attempt.
Both clusters dial out to `192.168.188.152` (ASN 65512) because FRR-k8s
does not accept inbound BGP on TCP 179. VXLAN still goes VTEP-to-VTEP when
the underlay routes.

The **current** lab path is fabric peering under
[`rosa-cluster/`](../rosa-cluster/README.md). Keep this topology for the
Phase 1 story.

**Warning:** this RR does not join fabric VLANs. A guest on the stretched
overlay can reach the other cluster. It is not a member of the lab switch
VLAN or SVI.

## Layout

| Path | Role |
|------|------|
| `evpn-rr.clab.yml` | Topology: node `rr`, image `quay.io/frrouting/frr:10.5.1`, `eth1` toward host port `clab-evpn-rr-br0` |
| `rr/frr.conf` | BGP 65512, router-id `192.168.188.152`, listen ranges `192.168.188.0/24` (on-prem) and `10.0.0.0/8` (ROSA), both route-reflector clients for IPv4 unicast and L2VPN EVPN |
| `rr/daemons`, `rr/vtysh.conf`, `rr/boot.sh` | FRR process flags, integrated vtysh, and interface setup |
| `attach-to-br0.sh` | Puts host veth `clab-evpn-rr-br0` into bridge `br0` |
| `clab-evpn-rr/` | Output from a previous deploy (inventory, TLS). Reproduce from the topology file and `rr/`. |

`rr/boot.sh` addresses `eth1` as `192.168.188.152/24` and adds
`10.0.0.0/8 via 192.168.188.1`. The host needs bridge `br0` on
`192.168.188.0/24` before the attach script will run.

The on-prem object that dials this RR is
[`on-prem/frrconfiguration-peering-rosa.yaml`](../on-prem/frrconfiguration-peering-rosa.yaml)
(ASN 65512, neighbor `192.168.188.152`).

## Deploy

From this directory, with Containerlab installed and `br0` present:

```bash
sudo containerlab deploy -t evpn-rr.clab.yml
./attach-to-br0.sh
```

`attach-to-br0.sh` brings `clab-evpn-rr-br0` up and sets its master to `br0`.
Deploy first — the script exits if that veth does not exist yet.

## Verify

Container name follows Containerlab’s `clab-<lab>-<node>` pattern (`evpn-rr` / `rr`). This lab’s Containerlab runtime was podman:

```bash
sudo podman exec clab-evpn-rr-rr vtysh -c "show bgp l2vpn evpn summary"
sudo podman exec clab-evpn-rr-rr vtysh -c "show bgp l2vpn evpn"
```

Expect the on-prem and ROSA sessions as route-reflector clients once each
cluster’s FRRConfiguration is dialing `192.168.188.152`. `show bgp l2vpn evpn`
lists the type-2/type-3 routes those sessions have reflected.

Tear down when finished:

```bash
sudo containerlab destroy -t evpn-rr.clab.yml
```

## Read next

- Where this sits in the lab timeline: [evolution](../docs/evolution.md)
- What the RR gives us, and what fabric VLANs still require: [peering models](../docs/peering-models.md)
