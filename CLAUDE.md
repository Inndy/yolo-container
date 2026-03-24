# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**yolo-container** runs OpenCode and Claude Code (`--dangerously-skip-permissions`) inside a Docker container with a full multi-language dev environment (Go, Node.js, Python, Neovim, tmux). The container provides isolation so AI agents can operate freely without risk to the host. Each project gets its own persistent container keyed by its git root path.

## Build Commands

```bash
make          # Auto-detects host architecture (arm64 or amd64) and builds Docker image
make arm64    # Explicitly build for ARM64
make amd64    # Explicitly build for x86_64
```

The Makefile sets architecture-specific build args: `NEOVIM_ARCH`, `NODE_ARCH`, `GO_ARCH`, and `UBUNTU_DEFAULT_MIRROR`.

## Running

```bash
bin/opencode-docker          # Launch OpenCode in a project container
bin/opencode-docker claude   # Launch Claude Code with --dangerously-skip-permissions
bin/opencode-docker sh       # Open a shell in the container
```

The script can also be symlinked as `claude` or `claude-docker` to change its default behavior.

## Architecture

### Container Lifecycle (`bin/opencode-docker`)
- Computes a SHA1 hash of the project's git root path to uniquely name each container
- Tracks hash→path mappings in `~/.opencode_map`
- Detects stale containers (image ID mismatch) and prompts to replace them
- Checks for active exec sessions before replacing

### Bind Mounts
| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| Git root of current project | `/code-$HASH` | Source code |
| `~/dev/.claude` | `/home/dev/.claude` | Claude Code state persistence |
| `~/dev/.claude.json` / `claude.json` | `/home/dev/.claude.json` | Claude config |
| `~/.local/share/opencode` | `/home/dev/.local/share/opencode` | OpenCode state |
| `gitconfig` | `/home/dev/.gitconfig` | Git config |
| `opencode.json` | `/home/dev/.config/opencode/config.json` | OpenCode config |
| `model.json` | `/home/dev/.config/opencode/model.json` | OpenCode model settings |

### User Remapping (`entrypoint.sh`)
The entrypoint dynamically maps the host user's UID/GID into the container's `/etc/passwd` and `/etc/group`, so files written inside the container are owned by the host user. The container's `dev` user has passwordless sudo.

### Config Files (Not Committed)
- `gitconfig` — Personal git configuration (example shows user "Inndy")
- `opencode.json` — OpenCode configuration
- `model.json` — OpenCode model settings
- `claude.json` — Claude Code settings (large JSON, bind-mounted at runtime)

These files must exist before the container can be used properly. `gitconfig` and `*json` files are `.gitignore`d except for the empty `model.json` and `opencode.json` placeholders.

### Tool Versions (Dockerfile defaults)
- Ubuntu 24.04 base
- Node.js 24.14.0
- Go 1.26.1
- Neovim: latest GitHub release
- uv: latest from astral.sh
- Go tools: `staticcheck`, `revive`
