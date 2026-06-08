# yolo-container

Run [opencode](https://opencode.ai) and [Claude Code](https://claude.ai/code) inside a Docker container. AI coding agents work best when they can freely read, write, and execute — but handing that level of access to an agentic process on your host machine is risky. This project wraps the whole thing in a container so the agent can run uninhibited while your host stays protected.

Each project gets its own persistent container (keyed by git root path). Source code is bind-mounted into the container. All project containers share a `--internal` Docker network (`yolo-internal`); they can talk to each other but cannot reach the host or any RFC 1918 network directly. Outbound traffic is routed through a `yolo-infra-gateway` container (nginx + iptables) which NATs public traffic and reverse-proxies AI APIs with API keys injected, so the project containers never see real keys. An optional `yolo-infra-ccxray` sidecar on the same network transparently proxies Claude Code ↔ Anthropic traffic and serves a live dashboard for inspecting sessions (system prompts, per-call cost, token/context usage).

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

Both `bin/yo` and the Makefile read this variable and forward all `docker` calls through the specified context. After reloading your profile (or opening a new shell), run `make` as normal.

The first build also creates the shared `yolo-internal` (`--internal`, `192.168.10.0/24`) Docker network if it doesn't already exist. Before launching any project container you also need to build and start the gateway:

```bash
cd api-gateway
cp default.conf.example default.conf  # then put your real ANTHROPIC_API_KEY in
make run
```

That brings up `yolo-infra-gateway` (a single nginx container) attached to both the default `bridge` (WAN) and `yolo-internal` (LAN, fixed IP `192.168.10.2`). It does iptables MASQUERADE for outbound traffic, drops all RFC 1918 destinations from `yolo-internal`, and reverse-proxies `https://api.anthropic.com` at `http://yolo-infra-gateway/claude/`.

### Observability dashboard (ccxray)

The `yolo-infra-ccxray` sidecar transparently proxies Claude Code ↔ Anthropic traffic and serves a live dashboard (system prompts, per-call cost, token/context usage). It joins the same `yolo-internal` network, egresses through the gateway NAT, and reads the shared `claude/` transcripts (read-only) for token-usage counting:

```bash
cd ccxray
make run
```

The gateway's nginx reverse-proxies the dashboard, published to the host at <http://127.0.0.1:33390>. ccxray's own logs live in `ccxray-data/`.

### Point Claude Code at the gateway / ccxray

In your `env` file (host-side, bind-mounted into every project container as `~/.env`):

**Team Plan / OAuth login** (recommended) — route through ccxray so sessions appear in the dashboard. Claude Code sends its own OAuth token, which ccxray forwards untouched. Do **not** set `ANTHROPIC_API_KEY` (a set key can shadow OAuth):

```
ANTHROPIC_BASE_URL=http://yolo-infra-ccxray:5577
```

**API key** — point at the gateway, which injects the real key. Keep a dummy key so SDKs that demand one don't error (this path bypasses the ccxray dashboard):

```
ANTHROPIC_API_KEY=sk-ant-dummy
ANTHROPIC_BASE_URL=http://yolo-infra-gateway/claude/
```

## Usage

`bin/yo` is the launcher. It runs an AI agent inside this project's sandbox
container; the tool and permission mode are arguments, not the script's name.

```bash
# Launch Claude Code, auto mode (the default tool + mode)
bin/yo

# YOLO mode — skip permission prompts
bin/yo -y

# Other tools (still pick a mode with --safe / --auto / -y)
bin/yo codex
bin/yo opencode

# Open a shell in the container
bin/yo sh

# Manage this project's container
bin/yo status      # state, image, staleness
bin/yo ls          # all yo containers (project path -> container)
bin/yo reset       # recreate (e.g. after a fresh `make`)
bin/yo stop        # stop and remove
```

Everything **after** the tool name is forwarded verbatim to the agent, e.g.
`bin/yo claude --resume` runs `claude --resume` inside the container.

### Tools and modes

| Concept | Values | Default |
|---------|--------|---------|
| Tool    | `claude` · `codex` · `opencode` | `claude` |
| Mode    | `--safe` (prompt for everything) · `--auto` · `-y`/`--yolo` (skip prompts) | `auto` |
| Model   | `-m, --model NAME` | unset |

Each maps to the right flags per tool — e.g. `claude` auto → `claude --permission-mode auto`,
`claude` yolo → `claude --dangerously-skip-permissions`, `codex` yolo → `codex --yolo`.
Defaults come from `YOLO_TOOL` / `YOLO_MODE` / `YOLO_MODEL` env vars (set them in
your shell profile next to `YOLO_DOCKER_CONTEXT`); resolution is **CLI flag > env var > built-in**.

The launcher automatically detects and replaces containers running on an outdated image. If active sessions are running, it will prompt before replacing.

### Legacy symlink interface (`bin/opencode-docker`)

`bin/opencode-docker` is kept as a thin compatibility shim that forwards to `yo`,
so older symlink-name setups keep working. Symlink it into your `$PATH` under one
of these names:

| Symlink name      | Forwards to            | Equivalent of                                   |
|-------------------|------------------------|-------------------------------------------------|
| `opencode-docker` | `yo opencode`          | `opencode`                                       |
| `claude`          | `yo -m opus claude`    | `claude --permission-mode auto --model opus`     |
| `claude-docker`   | `yo -m opus claude`    | `claude --permission-mode auto --model opus`     |
| `claude-yolo`     | `yo -y claude`         | `claude --dangerously-skip-permissions`          |
| `codex` / `codex-docker` | `yo codex`      | `codex`                                          |
| `codex-yolo`      | `yo -y codex`          | `codex --yolo`                                   |

```bash
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude        # auto mode
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude-yolo   # YOLO mode
```

New setups should symlink `bin/yo` directly and pass the mode as an argument.
