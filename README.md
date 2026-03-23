# opencode-docker

Run [opencode](https://opencode.ai) and [Claude Code](https://claude.ai) inside a Docker container with a full dev environment (Go, Node.js, Python, Neovim, etc.).

Each project gets its own persistent container (keyed by git root path). Source code is bind-mounted into the container.

## Prerequisites

- Docker

## Setup

### 1. Review the Dockerfile

Open `Dockerfile` and check these settings match your environment:

- **`UBUNTU_MIRROR`** — APT mirror (default: Taiwan mirror). Change to one near you or revert to `ports.ubuntu.com`.
- **`NODE_VERSION`**, **`GO_VERSION`** — toolchain versions.
- Architecture args (`NEOVIM_ARCH`, `NODE_ARCH`, `GO_ARCH`) are set automatically by `make` based on your host architecture.

### 2. Create required config files

These files are `.gitignore`'d because they contain personal config. Create them before building:

| File | Purpose |
|------|---------|
| `gitconfig` | Copied to `/root/.gitconfig` inside the container. Use your usual git config (name, email, etc.). |
| `opencode.json` | Copied to `/root/.config/opencode/`. OpenCode configuration. |
| `model.json` | Copied to `/root/.local/state/opencode/`. OpenCode model settings. |
| `claude.json` | Bind-mounted at runtime to `/root/.claude.json`. Claude Code configuration. |

The `claude/` directory is bind-mounted to `/root/.claude` at runtime for Claude Code state persistence.

## Build

```bash
# Auto-detects host architecture (arm64 or x86_64)
make

# Or specify explicitly
make arm64
make amd64
```

## Usage

```bash
# Launch opencode (default)
bin/opencode-docker

# Launch Claude Code (with --dangerously-skip-permissions)
bin/opencode-docker claude

# Open a shell in the container
bin/opencode-docker sh
bin/opencode-docker bash
```

If the script is symlinked as `claude` or `claude-docker`, it launches Claude Code by default.

The wrapper automatically detects and replaces containers running on an outdated image. If active sessions are running, it will prompt before replacing.
