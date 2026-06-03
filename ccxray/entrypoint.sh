#!/bin/bash
set -e

# yolo-internal is --internal: Docker's default route points at the bridge gw
# (.1), which leads nowhere. Rewrite it to llm-gateway so outbound traffic
# egresses through its iptables MASQUERADE — same pattern as ../entrypoint.sh.
ROUTER_IP=$(getent hosts llm-gateway | awk '{print $1}')
if [ -n "$ROUTER_IP" ]; then
	ip route del default 2>/dev/null || true
	ip route add default via "$ROUTER_IP" 2>/dev/null || \
		echo "ccxray entrypoint: failed to add default route via $ROUTER_IP" >&2
else
	echo "ccxray entrypoint: llm-gateway not resolvable; egress will fail" >&2
fi

exec "$@"
