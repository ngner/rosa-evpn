#!/bin/sh
set -eu
sysctl -w net.ipv4.ip_forward=1
ip link set eth1 up
ip addr add 192.168.188.152/24 dev eth1
ip route add 10.0.0.0/8 via 192.168.188.1 dev eth1
