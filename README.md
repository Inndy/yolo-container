# yolo-container

Run [opencode](https://opencode.ai) and [Claude Code](https://claude.ai/code) inside a Docker container. AI coding agents work best when they can freely read, write, and execute — but handing that level of access to an agentic process on your host machine is risky. This project wraps the whole thing in a container so the agent can run uninhibited while your host stays protected.

Each project gets its own persistent container (keyed by git root path). Source code is bind-mounted into the container. All project containers share a `--internal` Docker network (`yolo-internal`); they can talk to each other but cannot reach the host or any RFC 1918 network directly. Outbound traffic is routed through an `llm-gateway` container (nginx + iptables) which NATs public traffic and reverse-proxies AI APIs with API keys injected, so the project containers never see real keys.

## Prerequisites

- Docker
- **macOS only:** [OrbStack](https://orbstack.dev/) is required. Docker Desktop's iptables rules interfere with the gateway container's NAT routing and break outbound connectivity regardless of `BLOCK_LAN` setting. You must also explicitly set `YOLO_DOCKER_CONTEXT` in your shell profile — the Makefile enforces this:
  ```bash
  # in ~/.bashrc, ~/.zshrc, or ~/.profile
  export YOLO_DOCKER_CONTEXT=orbstack
  ```

## Setup

### 1. Review the Dockerfile

Open `Dockerfile` and check these settings match your environment:

- **`UBUNTU_MIRROR`** — APT mirror (default: Taiwan mirror). Change to one near you or revert to `ports.ubuntu.com`.
- **`NODE_VERSION`**, **`GO_VERSION`** — toolchain versions.
- Architecture args (`NEOVIM_ARCH`, `NODE_ARCH`, `GO_ARCH`) are set automatically by `make` based on your host architecture.

### 2. Create required config files

These files are `.gitignore`'d because they contain personal config. `make` will `touch` empty placeholders for anything that is missing, but you probably want to fill them in before first use:

| File | Purpose |
|------|---------|
| `gitconfig` | Copied to `/home/dev/.gitconfig` at build time. Your usual git config (name, email, etc.). |
| `opencode.json` | Copied to `/home/dev/.config/opencode/` at build time. OpenCode configuration. |
| `model.json` | Copied to `/home/dev/.local/state/opencode/` at build time. OpenCode model settings. |
| `claude.json` | Bind-mounted at runtime to `/home/dev/.claude.json`. Claude Code configuration. |
| `env` | Bind-mounted at runtime to `/home/dev/.env`. `KEY=VALUE` pairs, auto-sourced by `.bashrc` into every shell (good place for API keys). |

The `claude/` directory is bind-mounted to `/home/dev/.claude` at runtime for Claude Code state persistence.

Because `gitconfig`, `opencode.json`, and `model.json` are *copied in at build time*, you must rebuild the image (`make`) after changing them. `claude.json` and `env` are bind-mounted, so edits take effect in new shells immediately.

## Build

```bash
# Auto-detects host architecture (arm64 or x86_64)
make

# Or specify explicitly
make arm64
make amd64
```

On macOS with OrbStack, add `YOLO_DOCKER_CONTEXT` to your shell profile before building:

```bash
# in ~/.bashrc, ~/.zshrc, or ~/.profile
export YOLO_DOCKER_CONTEXT=orbstack
```

Both `bin/opencode-docker` and the Makefile read this variable and forward all `docker` calls through the specified context. After reloading your profile (or opening a new shell), run `make` as normal.

The first build also creates the shared `yolo-internal` (`--internal`, `192.168.10.0/24`) Docker network if it doesn't already exist. Before launching any project container you also need to build and start the gateway:

```bash
cd api-gateway
cp default.conf.example default.conf  # then put your real ANTHROPIC_API_KEY in
make run
```

That brings up `llm-gateway` (a single nginx container) attached to both the default `bridge` (WAN) and `yolo-internal` (LAN, fixed IP `192.168.10.2`). It does iptables MASQUERADE for outbound traffic, drops all RFC 1918 destinations from `yolo-internal`, and reverse-proxies `https://api.anthropic.com` at `http://llm-gateway/claude/`.

In your `env` file (host-side, bind-mounted into every project container as `~/.env`), keep a dummy `ANTHROPIC_API_KEY` (some SDKs refuse to run without it being set) and point the SDK at the gateway:

```
ANTHROPIC_API_KEY=sk-ant-dummy
ANTHROPIC_BASE_URL=http://llm-gateway/claude/
```

## Usage

```bash
# Launch opencode (default)
bin/opencode-docker

# Launch Claude Code inside the container (raw `claude`, no flags)
bin/opencode-docker claude

# Open a shell in the container
bin/opencode-docker sh
bin/opencode-docker bash
```

### Claude launch modes via symlink

The script picks a launch mode based on the name it's invoked as:

| Symlink name     | Runs                                            | Mode       |
|------------------|-------------------------------------------------|------------|
| `opencode-docker`| `opencode`                                      | OpenCode   |
| `claude`         | `claude --permission-mode auto --model opus`    | Auto       |
| `claude-docker`  | `claude --dangerously-skip-permissions`         | Auto       |
| `claude-yolo`    | `claude --dangerously-skip-permissions`         | YOLO       |

So a typical setup is:

```bash
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude        # auto mode
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude-yolo   # YOLO mode
```

Any extra arguments you pass on the command line are forwarded to the underlying command.

The wrapper automatically detects and replaces containers running on an outdated image. If active sessions are running, it will prompt before replacing.
