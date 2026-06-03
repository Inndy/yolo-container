all: run

ifndef DOCKER_CONTEXT
ifdef YOLO_DOCKER_CONTEXT
export DOCKER_CONTEXT := $(YOLO_DOCKER_CONTEXT)
else ifeq ($(shell uname -s),Darwin)
$(error macOS: set YOLO_DOCKER_CONTEXT in your shell profile (e.g. export YOLO_DOCKER_CONTEXT=orbstack))
endif
endif

# Tracks the latest published ccxray by default. Pin if needed:
#   make CCXRAY_VERSION=1.9.2 run
CCXRAY_VERSION ?= latest
# When tracking 'latest', bust the npm layer each build so it re-pulls; a pinned
# version uses the version string as the key so its layer stays cache-stable.
ifeq ($(CCXRAY_VERSION),latest)
CCXRAY_CACHEBUST := $(shell date +%s)
else
CCXRAY_CACHEBUST := $(CCXRAY_VERSION)
endif
# Repo root is one level up (parallel to api-gateway/).
REPO_ROOT := $(abspath $(CURDIR)/..)

clean:
	-docker rm -f ccxray

docker-img-ready: Dockerfile entrypoint.sh FORCE
	docker build \
		--build-arg CCXRAY_VERSION=$(CCXRAY_VERSION) \
		--build-arg CCXRAY_CACHEBUST=$(CCXRAY_CACHEBUST) \
		-t ccxray .
	touch docker-img-ready

FORCE:

# ccxray joins the EXISTING shared yolo-internal network (same as dev containers
# and llm-gateway); it creates no network. Single-homed: no --network bridge, no
# -p, no --env-file. Egress rides the llm-gateway NAT via the route rewrite in
# entrypoint.sh, identical to a dev container.
run: docker-img-ready
	-docker kill ccxray
	-docker rm ccxray
	mkdir -p "$(REPO_ROOT)/ccxray-data"
	docker create --name ccxray \
		--network yolo-internal \
		--cap-add=NET_ADMIN \
		--dns 8.8.8.8 --dns 1.1.1.1 \
		--restart unless-stopped \
		-v "$(REPO_ROOT)/claude:/root/.claude:ro" \
		-v "$(REPO_ROOT)/ccxray-data:/root/.ccxray" \
		ccxray
	docker start ccxray

.PHONY: all run clean FORCE
