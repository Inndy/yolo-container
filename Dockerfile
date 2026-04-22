FROM ubuntu:24.04

ARG DEV_USER=dev
ARG DEV_HOME=/home/dev

# Assume you are using arm64
ARG UBUNTU_DEFAULT_MIRROR="ports.ubuntu.com"
# I live in Taiwan. Choose your own mirror
ARG UBUNTU_MIRROR="mirror.twds.com.tw"
RUN sed -e "s/${UBUNTU_DEFAULT_MIRROR}/${UBUNTU_MIRROR}/g" -i /etc/apt/sources.list.d/ubuntu.sources && \
	apt update && apt install -y \
			curl build-essential git mingw-w64 python3 python3-dev python3-pip \
			jq silversearcher-ag tmux htop sudo pkgconf xxd zstd \
			libssl-dev libgmp-dev libffi-dev libyaml-dev libreadline-dev libgdbm-dev autoconf bison && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/* && \
	touch /.ready && chmod 666 /.ready

# arm64 or x86_64
ARG NEOVIM_ARCH="arm64"
RUN curl -sL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NEOVIM_ARCH}.tar.gz | tar -C /opt -zx && \
	update-alternatives --install /usr/bin/editor editor /opt/nvim-linux-${NEOVIM_ARCH}/bin/nvim 100 && \
	update-alternatives --install /usr/bin/vi vi /opt/nvim-linux-${NEOVIM_ARCH}/bin/nvim 100 && \
	update-alternatives --install /usr/bin/vim vim /opt/nvim-linux-${NEOVIM_ARCH}/bin/nvim 100
ENV PATH="$PATH:/opt/nvim-linux-${NEOVIM_ARCH}/bin"

# Define Node.js version. Override using --build-arg NODE_VERSION=<version>
ARG NODE_VERSION="24.14.0"
# arm64 or x64
ARG NODE_ARCH="arm64"
RUN curl -sL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz | tar -C /opt -Jx
ENV PATH="$PATH:/opt/node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin"

# Define Go version. Override using --build-arg GO_VERSION=<version>
ARG GO_VERSION="1.26.1"
# arm64 or amd64
ARG GO_ARCH="arm64"
RUN curl -sL https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz | tar -C /opt -zx
ENV PATH="$PATH:/opt/go/bin:${DEV_HOME}/go/bin"

# Create dev user with passwordless sudo
RUN userdel -r ubuntu 2>/dev/null; \
	useradd -m -s /bin/bash ${DEV_USER} && \
	echo "${DEV_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEV_USER} && \
	chmod g+w /etc/passwd /etc/group

USER ${DEV_USER}
WORKDIR ${DEV_HOME}

RUN go install honnef.co/go/tools/cmd/staticcheck@latest && \
	go install github.com/mgechev/revive@latest

RUN curl -fsSL https://opencode.ai/install | bash && \
	mkdir -p ~/.config/opencode
ENV PATH="$PATH:${DEV_HOME}/.opencode/bin"

ENV PATH="$PATH:${DEV_HOME}/.local/bin"
ENV IS_SANDBOX=1
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install rust for ruby yjit
ENV PATH="$PATH:{$DEV_HOME}/.cargo/bin"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Install rbenv
ENV PATH="$PATH:${DEV_HOME}/.rbenv/bin"
RUN git clone https://github.com/rbenv/rbenv.git ~/.rbenv --depth 1 && \
	git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build && \
	~/.rbenv/bin/rbenv init bash

# I'm not using codex personally, but here you go
# RUN npm i -g @openai/codex

RUN curl -LsSf https://astral.sh/uv/install.sh | bash

RUN echo '[ -f ~/.env ] && { set -a; source ~/.env; set +a; }' >> ~/.bashrc

COPY --chown=${DEV_USER}:${DEV_USER} opencode.json ${DEV_HOME}/.config/opencode/
COPY --chown=${DEV_USER}:${DEV_USER} model.json ${DEV_HOME}/.local/state/opencode/
COPY --chown=${DEV_USER}:${DEV_USER} gitconfig ${DEV_HOME}/.gitconfig

USER root
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
