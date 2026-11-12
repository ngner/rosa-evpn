# Troubleshooting appendix

Narrative docs (read these first):

- [Evolution](docs/evolution.md)
- [Peering models](docs/peering-models.md)
- [Migration / Submariner / cold CUDN](docs/migration.md)
- [rosa-virt components](docs/rosa-virt-components.md)

The sections below are raw lab notes and failure traces.

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



## The API endpoints on managed clsuters must be able to reach other via BR-EX

In our case this conflicted with the above.  So we did a policy or routingrule to set the source of api to use the br-ex interface when routing to the ROSA Node IP and API range.

## Learnt required connections

### Submariner is a workaround

Submariner extends L3 reachability across clusters so MTV live migration can dial destination pod listeners (for example `:9185`) that VPN/VPC underlay alone cannot reach. It is a **temporary lab workaround**, not the long-term design for MTV or CUDN/EVPN networking. Expect to drop or shrink the mesh once MTV supports routable migration paths and Network CUDN guidance covers transfer plumbing—including Primary CUDN vs default network for cold plans. See [Migration / Submariner / cold CUDN](docs/migration.md) for the narrative, MTU caveats, and cold-migration CUDN notes.

| Cluster     | Namespace     | Pod Name Pattern     | Role                                                                         |
| ----------- | ------------- | -------------------- | ---------------------------------------------------------------------------- |
| Destination | VM Namespace  | importer--           | The Worker: Pulls disk data from the source and writes it to the target PVC. |
| Destination | openshift-cnv | cdi-deployment-      | The Orchestrator: Manages the lifecycle of the importer pods.                |
| Source      | VM Namespace  | virt-v2v--           | The Exporter (Warm Only): Processes disks for warm migration transfers.      |
| Hub         | openshift-mtv | forklift-controller- | The Manager: Monitors the overall plan progress and status.                  |


The importer pod on the Destination Cluster must be able to reach the Source Cluster on the following ports:

Port 6443 (API): To read VM manifests and secret tokens.
Port 443 (HTTPS): To download disk data through the VirtualMachineExport route created on the source .
MTU Considerations: If you are using a VPN or tunnel (like Submariner), an MTU mismatch can cause the Synchronization to hang at 0% or fail silently during large packet transfers.

Cannot reach the node port on ROSA from the pod
    - lastProbeTime: null
      lastTransitionTime: '2026-10-19T04:48:21Z'
      message: 'rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp 10.129.4.82:9185: i/o timeout"'
      reason: DecentralizedNotLiveMigratable
      status: 'True'

```
+------------------------------------------------------------------------------------------------------------------------------------------------------------------+
|                                                                    HUB CLUSTER: `apac-tech-lab`                                                                  |
|                                                                                                                                                                  |
|  Namespace: `openshift-mtv` / `mtv-integrations`[cite: 2]                                                                                                       |
|  +------------------------------------------------------------------------------------------------------------------------------------------------------------+  |
|  | Deployment: `forklift-controller`[cite: 2]                                                                                                                |  |
|  | Pod hint: `forklift-controller-7959b58bfd-27d8v`                                                                                                           |  |
|  | Function: Reconciles `Plan` and active `Migration` resources[cite: 2]                                                                                     |  |
|  +------------------------------------------------------------------------------------------------------------------------------------------------------------+  |
+-------------------------------------------------------+-----------------------------------------------------------------------+----------------------------------+
                                                        |                                                                       |
                 TCP 6443 (HTTPS / Kube-API)            |                                                                       | TCP 6443 (HTTPS / Kube-API)
                 - Creates source VMIM (`forklift-b2xjb`)|                                                                      | - Creates target VM (`fleet-db`)[cite: 3]
                 - Polls VMI migration phase            |                                                                       | - Applies `runStrategy: WaitAsReceiver`[cite: 3]
                                                        v                                                                       v
+---------------------------------------------------------------------------------+   +----------------------------------------------------------------------------+
|                        SOURCE CLUSTER: `dl380` (`dl380-mtv`)[cite: 2]          |   |                 DESTINATION CLUSTER: `ROSA` (`rosa-virt-mtv`)[cite: 2]    |
|                                                                                 |   |                                                                            |
|  Namespace: `openshift-cnv`                                                     |   |  Namespace: `openshift-cnv`                                                |
|  +---------------------------------------------------------------------------+  |   |  +----------------------------------------------------------------------+  |
|  | DaemonSet: `virt-handler`                                                 |  |   |  | Deployment: `virt-controller`[cite: 3]                                 |  |
|  | Pod hint: `virt-handler-<source-node>`                                    |  |   |  | Pod hint: `virt-controller-<hash>`                                    |  |
|  | Function: Reads target `connectURL`; dials destination to push VM state   |  |   |  | Function: Reconciles target VM/VMI receiver state[cite: 3]            |  |
|  +--------------------------------------+------------------------------------+  |   |  +----------------------------------------------------------------------+  |
|                                         |                                       |   |                                                                            |
|                                         | Unix Domain Socket                    |   |  Namespace: `openshift-cnv` or `blue` (Receiver Proxy/Service)             |
|                                         v                                       |   |  +----------------------------------------------------------------------+  |
|  Namespace: `blue`[cite: 2]                                                    |   |  | Service / Pod: Migration Receiver Listener                           |  |
|  +---------------------------------------------------------------------------+  |   |  | Target Endpoint: `connectURL` (`10.130.0.36:9185`)                   |  |
|  | Pod: `virt-launcher-fleet-db-zww9c`[cite: 1]                              |  |   |  | Status: Target in `WaitingForReceiver` holding pattern[cite: 3]        |  |
|  | Container: `compute` (libvirt / QEMU process PID 67)[cite: 1]              |  |   |  +----------------------------------+-----------------------------------+  |
|  | Storage: Backed by source PV `/dev/vol-0`[cite: 1]                       |  |   |                                     |                                      |
|  +---------------------------------------------------------------------------+  |   |                                     | Unblocks upon handshake              |
|                                                                                 |   |                                     v                                      |
|                                                                                 |   |  Namespace: `blue`[cite: 2, 3]                                            |
|                                                                                 |   |  +----------------------------------------------------------------------+  |
|                                                                                 |   |  | Pod: `virt-launcher-fleet-db-<hash>` (Not yet scheduled)[cite: 3]   |  |
|                                                                                 |   |  | Condition: `PodNotExists` until inbound synchronization starts[cite: 3]|
|                                                                                 |   |  | Storage: Bound to target PVC `fleet-db-vmware-...-9sdvb`[cite: 3]    |  |
|                                                                                 |   |  +----------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------+   +----------------------------------------------------------------------------+
                                          |                                                                     ^
                                          |                    TCP 9185 (gRPC / mTLS Migration Stream)          |
                                          +---------------------------------------------------------------------+
                                            Target: dial tcp 10.130.0.36:9185
                                            Result: Connection refused (Pod network overlay not routable WAN/VPC)

```



---



### Component & Connection Details

```mermaid
flowchart TD
    subgraph HUB["HUB CLUSTER (apac-tech-lab)"]
        subgraph NS_HUB["Namespace: mtv-integrations / openshift-mtv"]
            FC["Deployment: forklift-controller<br/>Pod: forklift-controller-7959b58bfd-27d8v<br/>(Reconciles Plan & Migration CRDs)"]
        end
    end

    subgraph SRC["SOURCE CLUSTER (dl380 / dl380-mtv)"]
        subgraph NS_SRC_CNV["Namespace: openshift-cnv"]
            VH_SRC["DaemonSet: virt-handler<br/>Pod: virt-handler-<node><br/>(Initiates outbound migration stream)"]
        end
        subgraph NS_SRC_BLUE["Namespace: blue"]
            VL_SRC["Pod: virt-launcher-fleet-db-zww9c<br/>(Source QEMU / KVM process)"]
            VMIM_SRC["CR: virtualmachineinstancemigration/forklift-b2xjb<br/>(Phase: Synchronizing)"]
        end
    end

    subgraph DEST["DESTINATION CLUSTER (ROSA / rosa-virt-mtv)"]
        subgraph NS_DEST_CNV["Namespace: openshift-cnv"]
            VC_DEST["Deployment: virt-controller<br/>(Manages target VMI receiver lifecycle)"]
        end
        subgraph NS_DEST_BLUE["Namespace: blue"]
            VM_DEST["CR: virtualmachine/fleet-db<br/>(runStrategy: WaitAsReceiver)"]
            RECV["Target Migration Listener<br/>Endpoint: 10.130.0.36:9185<br/>(Status: WaitingForReceiver)"]
            VL_DEST["Pod: virt-launcher-fleet-db-<hash><br/>(Status: PodNotExists / Pending sync)"]
        end
    end

    FC -->|TCP 6443 HTTPS<br/>Creates VMIM & tracks migration| SRC
    FC -->|TCP 6443 HTTPS<br/>Creates VM, PVC, & Receiver VMIM| DEST

    VH_SRC -->|IPC / Unix Domain Socket| VL_SRC
    VMIM_SRC -. controls .-> VH_SRC
    VC_DEST -. manages .-> VM_DEST
    VM_DEST -. waits for .-> RECV
    RECV -. schedules upon connect .-> VL_DEST

    VH_SRC ===|TCP 9185 gRPC / mTLS<br/>[FAILED: connect: connection refused]| RECV

```





### Protocol & Traffic Breakdown

- **Hub to Source / Destination Control Planes (TCP 6443 - HTTPS):**
- **Source:** `forklift-controller` on the Hub communicates with the source Kubernetes API server to inspect VM `fleet-db`, read secrets, and generate the source `virtualmachineinstancemigration` resource (`forklift-b2xjb`).
- **Destination:** `forklift-controller` connects to the ROSA API server to prepare target namespace `blue`, create PVC `fleet-db-vmware-dl380-vm-49-9sdvb`, and deploy the target VirtualMachine manifest with `spec.runStrategy: WaitAsReceiver`.
- **Source Internal IPC (Local Unix Domain Socket):**
- `virt-handler` communicates with the local `virt-launcher-fleet-db-zww9c` container over `/var/run/kubevirt` domain sockets to control libvirt and attach memory/disk tracking hooks.
- **Cross-Cluster VM State & Disk Synchronization (TCP 9185 - gRPC over TLS):**
- **Intended flow:** Source worker node's `virt-handler` dials the `spec.sendTo.connectURL` advertised by the destination cluster (`10.130.0.36:9185`) to stream storage changes and memory dirty pages directly.
- **Failure point:** The destination advertised an internal OVN-Kubernetes Pod overlay address (`10.130.0.36`), which cannot be routed from on-premise hardware over the WAN/VPC boundaries to AWS ROSA, dropping the TCP connection before synchronization can begin.

