all: run

# Build-time toggle for blocking LAN (RFC 1918) access from clients.
# 1 = block all RFC 1918 destinations (default);
# 0 = allow LAN access (single-host / home use, no internal network exposure risk).
# Switching value forces a rebuild via docker layer cache invalidation
# on the ARG layer.
BLOCK_LAN ?= 1

ifndef DOCKER_CONTEXT
ifdef YOLO_DOCKER_CONTEXT
export DOCKER_CONTEXT := $(YOLO_DOCKER_CONTEXT)
else ifeq ($(shell uname -s),Darwin)
$(error macOS: set YOLO_DOCKER_CONTEXT in your shell profile (e.g. export YOLO_DOCKER_CONTEXT=orbstack). OrbStack is required for BLOCK_LAN=1; Docker Desktop works with the default BLOCK_LAN=0)
endif
endif

clean:
	docker rm -f llm-gateway
	docker network rm yolo-internal

debug: FORCE
	docker build --target debug --build-arg BLOCK_LAN=$(BLOCK_LAN) -t llm-gateway .
	touch docker-img-ready

docker-img-ready: default.conf Dockerfile 99-iptables.sh FORCE
	docker build --target base --build-arg BLOCK_LAN=$(BLOCK_LAN) -t llm-gateway .
	touch docker-img-ready

FORCE:

default.conf:
	test -f default.conf || { echo Run \"cp defualt.conf.example defualt.conf\" and put your KEY; exit 1; }

yolo-internal:
	docker network inspect -f OK yolo-internal || \
		docker network create \
			--internal \
			--subnet=192.168.10.0/24 \
			--ip-range=192.168.10.128/25 \
			yolo-internal

run: docker-img-ready yolo-internal
	-docker kill llm-gateway
	-docker rm llm-gateway
	# eth0: bridge (WAN, NAT-ed by Docker host)
	# eth1: yolo-internal (LAN, --internal); IP auto-assigned, clients
	#       reach this container by service name `llm-gateway` via embedded DNS
	# Inside yolo-internal containers: export ANTHROPIC_BASE_URL=http://llm-gateway/claude/
	# On docker host: export ANTHROPIC_BASE_URL=http://127.0.0.1:33380/claude/
	#
	# create → network connect → start, so both interfaces exist before
	# 99-iptables.sh runs at container startup
	docker create --name llm-gateway \
		--network bridge \
		--cap-add=NET_ADMIN \
		--sysctl net.ipv4.ip_forward=1 \
		-p 127.0.0.1:33380:80 \
		--restart unless-stopped \
		llm-gateway
	docker network connect --ip 192.168.10.2 yolo-internal llm-gateway
	docker start llm-gateway

.PHONY: all run yolo-internal clean debug FORCE
