IMAGE ?= opencode-dev
BUILD_OPT ?=
DEFAULT_FILES = gitconfig model.json opencode.json env

# Detect host architecture and build matching image
ARCH := $(shell uname -m)

all: build-$(ARCH) yolo-internal

$(DEFAULT_FILES):
	touch $@

yolo-internal:
	docker network inspect -f OK yolo-internal || \
		docker network create \
			--internal \
			--subnet=192.168.10.0/24 \
			--gateway=192.168.10.1 \
			--ip-range=192.168.10.128/25 \
			yolo-internal

build-%: Dockerfile entrypoint.sh $(DEFAULT_FILES)
	@arch=$*; \
	case $$arch in \
		arm64) NEOVIM_ARCH=arm64 NODE_ARCH=arm64 GO_ARCH=arm64 UBUNTU_DEFAULT_MIRROR=ports.ubuntu.com ;; \
		amd64|x64|x86_64) NEOVIM_ARCH=x86_64 NODE_ARCH=x64 GO_ARCH=amd64 UBUNTU_DEFAULT_MIRROR=archive.ubuntu.com ;; \
		*) echo "Unsupported architecture: $$arch"; exit 1 ;; \
	esac; \
	docker build $(BUILD_OPT) -t $(IMAGE) \
		--build-arg UBUNTU_DEFAULT_MIRROR=$$UBUNTU_DEFAULT_MIRROR \
		--build-arg NEOVIM_ARCH=$$NEOVIM_ARCH \
		--build-arg NODE_ARCH=$$NODE_ARCH \
		--build-arg GO_ARCH=$$GO_ARCH \
		.

arm64: build-arm64
aarch64: build-arm64

amd64: build-amd64
x64: build-amd64
x86_64: build-amd64
