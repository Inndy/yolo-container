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

The Makefile sets architecture-specific build args: `NEOVIM_ARCH`, `NODE_ARCH`, `GO_ARCH`, and `UBUNTU_DEFAULT_MIRROR`. It also creates the shared Docker network `yolo-internal` (via the `yolo-internal` target — `--internal`, subnet `192.168.10.0/24`, gateway `.1`) and touches empty placeholder config files (`gitconfig`, `model.json`, `opencode.json`, `env`) if they don't exist. The companion `api-gateway/` subproject builds the `llm-gateway` container that sits on this network.

The gateway has a build-time toggle `BLOCK_LAN` (default `0`). `make BLOCK_LAN=1 -C api-gateway run` bakes RFC 1918 DROP rules into the image (corporate setups where the agent must not reach the internal LAN). The default `0` allows LAN access — appropriate for single-host / home use. The flag is passed via `--build-arg BLOCK_LAN=...`; the Makefile uses a `FORCE` dep so switching the value always re-invokes `docker build`, with Docker's layer cache skipping unchanged work.

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
- Containers are attached to the `yolo-internal` Docker network (`--internal`), so they can reach each other and `llm-gateway` by name but cannot reach the host or external networks directly. Outbound traffic egresses through `llm-gateway` (iptables MASQUERADE + RFC 1918 DROP + nginx reverse-proxy for AI APIs). The container is launched with `--cap-add=NET_ADMIN` and `--dns 8.8.8.8 --dns 1.1.1.1`. `entrypoint.sh` resolves `llm-gateway` via Docker's embedded DNS (always present at `127.0.0.11` on custom networks, regardless of `--dns`) and rewrites the default route to that IP; the explicit upstream DNS servers handle external lookups (forwarded through the router by NAT) since the host's resolver is unreachable on `--internal`

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
The Dockerfile appends `[ -f ~/.env ] && { set -a; source ~/.env; set +a; }` to `~/.bashrc`. Any `KEY=VALUE` pair in the host-side `env` file is exported into every shell (and therefore into `opencode` / `claude` when launched from a login-style shell). Real API keys live in `api-gateway/default.conf` (not in `env`); the `env` file should hold a dummy key + `ANTHROPIC_BASE_URL=http://llm-gateway/claude/` so SDKs that demand a key don't error and outbound API traffic flows through the gateway.

### User Remapping (`entrypoint.sh`)
The container starts as root. The entrypoint receives `HOST_UID`/`HOST_GID` via environment variables and remaps the `dev` user's UID/GID to match, deleting any conflicting system users/groups (e.g. macOS GID 20 vs Ubuntu's `dialout`). It then `chown`s `/home/dev` and `exec`s the command. All `docker exec` calls use `--user` to run as the remapped UID/GID. The `dev` user has passwordless sudo. A `/.ready` lock file synchronizes: the entrypoint holds an exclusive `flock` during remapping, and `opencode-docker` waits on that lock before issuing the first `exec`. After remapping, the entrypoint resolves `llm-gateway` via Docker's embedded DNS (with `python3 -c 'socket.gethostbyname(...)'`) and rewrites the default route to that IP. Docker's bridge gateway `192.168.10.1` is unreachable on `--internal` networks, so without this rewrite no outbound traffic works.

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
