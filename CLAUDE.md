# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**yolo-container** runs OpenCode and Claude Code inside a Docker container with a full multi-language dev environment (Go, Node.js, Python, Ruby via rbenv, Neovim, tmux). The container provides isolation so AI agents can operate freely without risk to the host. Each project gets its own persistent container keyed by its git root path.

## Build Commands

```bash
make          # Auto-detects host architecture (arm64 or amd64) and builds Docker image
make arm64    # Explicitly build for ARM64
make amd64    # Explicitly build for x86_64
```

The Makefile sets architecture-specific build args: `NEOVIM_ARCH`, `NODE_ARCH`, `GO_ARCH`, and `UBUNTU_DEFAULT_MIRROR`. It also creates the shared Docker network `yolo-container-net` (via the `yolo-container-net` target) and touches empty placeholder config files (`gitconfig`, `model.json`, `opencode.json`, `env`) if they don't exist.

## Running

```bash
bin/opencode-docker          # Launch OpenCode in a project container
bin/opencode-docker claude   # Launch Claude Code inside the container (raw `claude`, no flags)
bin/opencode-docker sh       # Open a shell in the container
```

### Symlink behavior

The launch mode is selected by the script's invoked name:

| Invoked as          | Default command                                 | Meaning      |
|---------------------|-------------------------------------------------|--------------|
| `opencode-docker`   | `opencode`                                      | OpenCode     |
| `claude`            | `claude --permission-mode auto --model opus`    | Auto mode    |
| `claude-docker`     | `claude --dangerously-skip-permissions`         | YOLO mode    |
| `claude-yolo`       | `claude --dangerously-skip-permissions`         | YOLO mode    |

Create symlinks in your `$PATH` (e.g. `ln -s .../bin/opencode-docker ~/bin/claude`) to pick a mode.

## Architecture

### Container Lifecycle (`bin/opencode-docker`)
- Computes a SHA1 hash of the project's git root path to uniquely name each container (`opencode-<hash>`)
- Tracks hash→path mappings in `~/.opencode_map`
- Detects stale containers (image ID mismatch) and prompts to replace them
- Checks for active exec sessions before replacing
- Containers are attached to the `yolo-container-net` Docker network so sibling project containers can reach each other by name; `host.docker.internal` is also mapped to the host gateway

### Bind Mounts
| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| Git root of current project | `/code-$HASH` (also the workdir) | Source code |
| `<repo>/claude/` | `/home/dev/.claude` | Claude Code state persistence |
| `<repo>/claude.json` | `/home/dev/.claude.json` | Claude Code config (auto-`touch`ed if missing) |
| `<repo>/env` | `/home/dev/.env` | Env file, sourced automatically by `.bashrc` (see below) |
| `~/.local/share/opencode` | `/home/dev/.local/share/opencode` | OpenCode state |

`gitconfig`, `opencode.json`, and `model.json` are copied in at build time (not bind-mounted), so rebuild the image after editing them.

### Env File Auto-Loading
The Dockerfile appends `[ -f ~/.env ] && { set -a; source ~/.env; set +a; }` to `~/.bashrc`. Any `KEY=VALUE` pair in the host-side `env` file is exported into every shell (and therefore into `opencode` / `claude` when launched from a login-style shell). Use this for API keys and other runtime secrets you don't want baked into the image.

### User Remapping (`entrypoint.sh`)
The container starts as root. The entrypoint receives `HOST_UID`/`HOST_GID` via environment variables and remaps the `dev` user's UID/GID to match, deleting any conflicting system users/groups (e.g. macOS GID 20 vs Ubuntu's `dialout`). It then `chown`s `/home/dev` and `exec`s the command. All `docker exec` calls use `--user` to run as the remapped UID/GID. The `dev` user has passwordless sudo. A `/.ready` lock file synchronizes: the entrypoint holds an exclusive `flock` during remapping, and `opencode-docker` waits on that lock before issuing the first `exec`.

### Config Files (Not Committed)
- `gitconfig` — Personal git configuration
- `opencode.json` — OpenCode configuration
- `model.json` — OpenCode model settings
- `claude.json` — Claude Code settings (bind-mounted at runtime, auto-`touch`ed if missing)
- `env` — Shell env vars, sourced into every container shell

All five are `.gitignore`d. `make` will `touch` empty placeholders for `gitconfig`, `model.json`, `opencode.json`, and `env` so the build can succeed on a fresh clone.

### Tool Versions (Dockerfile defaults)
- Ubuntu 24.04 base
- Node.js 24.14.0
- Go 1.26.1
- Neovim: latest GitHub release
- uv: latest from astral.sh
- rbenv: latest from GitHub (Ruby not pre-installed; use `rbenv install <version>` inside the container)
- Go tools: `staticcheck`, `revive`
