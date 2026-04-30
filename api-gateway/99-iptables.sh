#!/bin/sh
set -e

WAN_IF=$(ip route show default | awk '/default/{print $5; exit}' | sed -e 's/@.*//')
LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep '^eth' | sed -e 's/@.*//' | grep -v "^${WAN_IF}\$" | head -1)
HOST_IP=$(getent hosts host.docker.internal | awk '{print $1}')

if [ -z "$WAN_IF" ] || [ -z "$LAN_IF" ]; then
	echo "iptables setup: failed to detect interfaces (WAN=$WAN_IF LAN=$LAN_IF)" >&2
	exit 1
fi

echo "iptables setup: WAN=$WAN_IF LAN=$LAN_IF"

# net.ipv4.ip_forward is already enabled by `docker run --sysctl net.ipv4.ip_forward=1`,
# so we don't need a sysctl binary inside the image.

iptables -P FORWARD DROP

# BLOCK_LAN is baked in at build time (see Dockerfile ARG/ENV).
# 1 = block all RFC 1918 destinations from LAN clients (corporate setup);
# 0 = allow LAN access (home / single-host setup).
if [ "${BLOCK_LAN:-0}" = "1" ]; then
	echo "iptables setup: BLOCK_LAN=1, blocking RFC 1918 destinations from LAN"
	iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -d "$HOST_IP"     -j ACCEPT
	iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -d 10.0.0.0/8     -j DROP
	iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -d 172.16.0.0/12  -j DROP
	iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -d 192.168.0.0/16 -j DROP
else
	echo "iptables setup: BLOCK_LAN=0, LAN access allowed"
fi

iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT
iptables -A FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
