# ROSA Partner CUDNs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ROSA partner CUDNs for blue-320 and green-319 with complementary reservedSubnets, supersede `evpn-layer2-cudn.yaml`, and update README / `comined.yaml` refs.

**Architecture:** Mirror lab CUDN manifests under `rosa-cluster/`, keep both old (`network: "evpn-on-prem"`) and new (`evpn` / `advertise`) labels, match lab VNIs/RTs, and reserve the on-prem auto-assign pool (`.128/27`) so ROSA auto-assigns from `.160/27`.

**Tech Stack:** Kubernetes YAML (`ClusterUserDefinedNetwork` / `k8s.ovn.org/v1`), git.

**Spec:** `docs/superpowers/specs/2026-09-23-rosa-partner-cudns-design.md`

## Global Constraints

- File names: `rosa-cluster/cudn-evpn-blue-320.yaml`, `rosa-cluster/cudn-evpn-green-319.yaml`
- `metadata.name`: `blue-320` / `green-319`
- Labels on both: `network: "evpn-on-prem"`, `evpn: "true"`, `advertise: "evpn"`
- Blue IPAM: subnet `172.25.220.0/24`; reserve `172.25.220.128/27`; leave `172.25.220.160/27` free
- Green IPAM: subnet `172.25.219.0/24`; reserve `172.25.219.128/27`; leave `172.25.219.160/27` free
- Blue EVPN: macVRF `10320` / `65004:10320`; ipVRF `50320` / `65004:10000`
- Green EVPN: macVRF `10319` / `65004:10319`; ipVRF `50319` / `65004:10000`
- Delete `rosa-cluster/evpn-layer2-cudn.yaml`
- Do not apply to a live cluster; do not edit lab-infra-ocp or `on-prem-cluster/`

## File map

| Path | Action | Responsibility |
|------|--------|----------------|
| `rosa-cluster/cudn-evpn-blue-320.yaml` | Create | ROSA partner blue CUDN |
| `rosa-cluster/cudn-evpn-green-319.yaml` | Create | ROSA partner green CUDN |
| `rosa-cluster/evpn-layer2-cudn.yaml` | Delete | Superseded by blue |
| `README.md` | Modify | Apply paths for new CUDNs |
| `rosa-cluster/comined.yaml` | Modify | Embed blue + green partner CUDNs |

---

### Task 1: Add ROSA partner blue-320 CUDN and remove superseded file

**Files:**
- Create: `rosa-cluster/cudn-evpn-blue-320.yaml`
- Delete: `rosa-cluster/evpn-layer2-cudn.yaml`

**Interfaces:**
- Consumes: lab blue-320 shape from design (subnet `172.25.220.0/24`, VNIs as Global Constraints)
- Produces: `ClusterUserDefinedNetwork/blue-320` manifest for ROSA apply

- [ ] **Step 1: Create `rosa-cluster/cudn-evpn-blue-320.yaml`**

Write this exact content:

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: blue-320
  labels:
    network: "evpn-on-prem"
    evpn: "true"
    advertise: "evpn"
spec:
  namespaceSelector:
    matchExpressions:
      - key: primary-cudn
        operator: In
        values:
          - blue-320
  network:
    topology: Layer2
    layer2:
      role: Primary
      mtu: 1400
      ipam:
        lifecycle: Persistent
      subnets:
        - 172.25.220.0/24
      infrastructureSubnets:
        - 172.25.220.0/28          # .0–.15: gateway .1, mgmt .2, headroom
      reservedSubnets:
        - 172.25.220.16/28         # .16–.31: static IPs (shared)
        - 172.25.220.32/27         # .32–.63: static IPs (shared)
        - 172.25.220.64/28         # .64–.79: static IPs (shared)
        - 172.25.220.80/28         # .80–.95: unallocated
        - 172.25.220.96/28         # .96–.111: unallocated
        - 172.25.220.112/28        # .112–.127: unallocated
        - 172.25.220.128/27        # .128–.159: on-prem auto-assign pool
        - 172.25.220.192/26        # .192–.255: headroom
        # ROSA auto-assign pool: 172.25.220.160/27 (.160–.191)
    transport: EVPN
    evpn:
      vtep: evpn-vtep
      macVRF:
        vni: 10320
        routeTarget: 65004:10320
      ipVRF:
        vni: 50320
        routeTarget: 65004:10000
```

- [ ] **Step 2: Delete superseded file**

```bash
rm rosa-cluster/evpn-layer2-cudn.yaml
```

- [ ] **Step 3: Verify blue partner invariants**

```bash
test ! -f rosa-cluster/evpn-layer2-cudn.yaml
grep -q 'name: blue-320' rosa-cluster/cudn-evpn-blue-320.yaml
grep -q 'network: "evpn-on-prem"' rosa-cluster/cudn-evpn-blue-320.yaml
grep -q '172.25.220.128/27' rosa-cluster/cudn-evpn-blue-320.yaml
grep -q 'vni: 50320' rosa-cluster/cudn-evpn-blue-320.yaml
! grep -q '172.25.220.160/27' rosa-cluster/cudn-evpn-blue-320.yaml || grep -q 'ROSA auto-assign pool: 172.25.220.160/27' rosa-cluster/cudn-evpn-blue-320.yaml
```

Expected: all `test`/`grep` succeed (exit 0). The last line allows `.160/27` only in the comment marking the free ROSA pool, not as a reserved entry.

Confirm reserved list does **not** include a `- 172.25.220.160/27` entry:

```bash
! grep -E '^\s+- 172\.25\.220\.160/27' rosa-cluster/cudn-evpn-blue-320.yaml
```

Expected: exit 0 (no match).

- [ ] **Step 4: Commit**

```bash
git add rosa-cluster/cudn-evpn-blue-320.yaml
git add -u rosa-cluster/evpn-layer2-cudn.yaml
git commit -m "$(cat <<'EOF'
Add ROSA partner blue-320 CUDN and drop superseded manifest.

EOF
)"
```

---

### Task 2: Add ROSA partner green-319 CUDN

**Files:**
- Create: `rosa-cluster/cudn-evpn-green-319.yaml`

**Interfaces:**
- Consumes: same label / IPAM-pairing pattern as Task 1 blue file
- Produces: `ClusterUserDefinedNetwork/green-319` manifest for ROSA apply

- [ ] **Step 1: Create `rosa-cluster/cudn-evpn-green-319.yaml`**

Write this exact content:

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: green-319
  labels:
    network: "evpn-on-prem"
    evpn: "true"
    advertise: "evpn"
spec:
  namespaceSelector:
    matchExpressions:
      - key: primary-cudn
        operator: In
        values:
          - green-319
  network:
    topology: Layer2
    layer2:
      role: Primary
      mtu: 1400
      ipam:
        lifecycle: Persistent
      subnets:
        - 172.25.219.0/24
      infrastructureSubnets:
        - 172.25.219.0/28          # .0–.15: gateway .1, mgmt .2, headroom
      reservedSubnets:
        - 172.25.219.16/28         # .16–.31: static IPs (shared)
        - 172.25.219.32/27         # .32–.63: static IPs (shared)
        - 172.25.219.64/28         # .64–.79: static IPs (shared)
        - 172.25.219.80/28         # .80–.95: unallocated
        - 172.25.219.96/28         # .96–.111: unallocated
        - 172.25.219.112/28        # .112–.127: unallocated
        - 172.25.219.128/27        # .128–.159: on-prem auto-assign pool
        - 172.25.219.192/26        # .192–.255: headroom
        # ROSA auto-assign pool: 172.25.219.160/27 (.160–.191)
    transport: EVPN
    evpn:
      vtep: evpn-vtep
      macVRF:
        vni: 10319
        routeTarget: 65004:10319
      ipVRF:
        vni: 50319
        routeTarget: 65004:10000
```

- [ ] **Step 2: Verify green partner invariants**

```bash
grep -q 'name: green-319' rosa-cluster/cudn-evpn-green-319.yaml
grep -q 'network: "evpn-on-prem"' rosa-cluster/cudn-evpn-green-319.yaml
grep -q '172.25.219.128/27' rosa-cluster/cudn-evpn-green-319.yaml
grep -q 'vni: 50319' rosa-cluster/cudn-evpn-green-319.yaml
! grep -E '^\s+- 172\.25\.219\.160/27' rosa-cluster/cudn-evpn-green-319.yaml
```

Expected: all commands exit 0.

- [ ] **Step 3: Commit**

```bash
git add rosa-cluster/cudn-evpn-green-319.yaml
git commit -m "$(cat <<'EOF'
Add ROSA partner green-319 CUDN with complementary IPAM reserves.

EOF
)"
```

---

### Task 3: Update README and comined.yaml references

**Files:**
- Modify: `README.md` (Deploy EVPN networking apply list, ~lines 108–113)
- Modify: `rosa-cluster/comined.yaml` (CUDN document starting at `name: evpn-on-prem-cudn`, through the ipVRF block before the next `---` / Namespace)

**Interfaces:**
- Consumes: exact YAML from Task 1 and Task 2
- Produces: docs/combined bundle that match the standalone partner files

- [ ] **Step 1: Update README apply paths**

In `README.md`, replace:

```bash
oc apply -f rosa-cluster/evpn-layer2-cudn.yaml
```

with:

```bash
oc apply -f rosa-cluster/cudn-evpn-blue-320.yaml
oc apply -f rosa-cluster/cudn-evpn-green-319.yaml
```

- [ ] **Step 2: Replace blue CUDN in `comined.yaml`**

Replace the entire `ClusterUserDefinedNetwork` document whose `metadata.name` is `evpn-on-prem-cudn` (from its `---` separator through the `ipVRF` block) with the full contents of `rosa-cluster/cudn-evpn-blue-320.yaml`, preserving a leading `---` so it remains a multi-doc YAML stream. After replacement the document must have `metadata.name: blue-320` and `ipVRF.vni: 50320`.

- [ ] **Step 3: Append green CUDN to `comined.yaml`**

Immediately after the blue-320 CUDN document (before the Namespace comment/document for `blue`), insert a `---` and the full contents of `rosa-cluster/cudn-evpn-green-319.yaml`.

- [ ] **Step 4: Verify refs and parity**

```bash
! grep -q 'evpn-layer2-cudn.yaml' README.md
grep -q 'cudn-evpn-blue-320.yaml' README.md
grep -q 'cudn-evpn-green-319.yaml' README.md
! grep -q 'name: evpn-on-prem-cudn' rosa-cluster/comined.yaml
grep -q 'name: blue-320' rosa-cluster/comined.yaml
grep -q 'name: green-319' rosa-cluster/comined.yaml
grep -q 'vni: 50320' rosa-cluster/comined.yaml
grep -q 'vni: 50319' rosa-cluster/comined.yaml
```

Expected: all exit 0.

Optional parity check (documents must match standalone files aside from stream separators):

```bash
python3 - <<'PY'
from pathlib import Path
import re

def docs(text):
    return [d.strip() for d in re.split(r'(?m)^---\s*$', text) if d.strip()]

combined = docs(Path('rosa-cluster/comined.yaml').read_text())
blue = Path('rosa-cluster/cudn-evpn-blue-320.yaml').read_text().strip()
green = Path('rosa-cluster/cudn-evpn-green-319.yaml').read_text().strip()
assert any(d == blue for d in combined), 'blue CUDN missing or drifted in comined.yaml'
assert any(d == green for d in combined), 'green CUDN missing or drifted in comined.yaml'
print('comined.yaml parity OK')
PY
```

Expected: `comined.yaml parity OK`

- [ ] **Step 5: Commit**

```bash
git add README.md rosa-cluster/comined.yaml
git commit -m "$(cat <<'EOF'
Point README and comined.yaml at ROSA partner blue/green CUDNs.

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Add blue-320 ROSA partner | Task 1 |
| Add green-319 ROSA partner | Task 2 |
| Delete `evpn-layer2-cudn.yaml` | Task 1 |
| Both label sets | Tasks 1–2 |
| Complementary reservedSubnets | Tasks 1–2 |
| VNIs/RTs match lab | Tasks 1–2 |
| Update README | Task 3 |
| Update `comined.yaml` | Task 3 |
| Out of scope items untouched | No tasks touch them |
