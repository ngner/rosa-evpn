#!/usr/bin/env bash
set -euo pipefail

BRIDGE="br0"
HOST_IF="clab-evpn-rr-br0"

if ! ip link show "${BRIDGE}" &>/dev/null; then
  echo "Bridge ${BRIDGE} not found." >&2
  exit 1
fi

if ! ip link show "${HOST_IF}" &>/dev/null; then
  echo "Host veth ${HOST_IF} not found. Deploy evpn-rr.clab.yml first." >&2
  exit 1
fi

sudo ip link set "${HOST_IF}" up
sudo ip link set "${HOST_IF}" master "${BRIDGE}"
echo "Attached ${HOST_IF} to ${BRIDGE}"
