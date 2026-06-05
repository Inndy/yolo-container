# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**yolo-container** runs OpenCode and Claude Code inside a Docker container with a full multi-language dev environment (Go, Node.js, Python, Ruby via rbenv, Neovim, tmux). The container provides isolation so AI agents can operate freely without risk to the host. Each project gets its own persistent container keyed by its git root path.

## macOS Prerequisite: OrbStack

macOS users must use [OrbStack](https://orbstack.dev/). Docker Desktop's iptables rules interfere with the gateway container's NAT routing and break outbound connectivity regardless of `BLOCK_LAN` setting.

Set `YOLO_DOCKER_CONTEXT` in your shell profile — the Makefile enforces explicit context on macOS:

```bash
# in ~/.bashrc, ~/.zshrc, or ~/.profile
export YOLO_DOCKER_CONTEXT=orbstack
```

After adding the export, reload your profile (or open a new shell) and run `make` as normal.

## Build Commands

```bash
make          # Auto-detects host architecture (arm64 or amd64) and builds Docker image
make arm64    # Explicitly build for ARM64
make amd64    # Explicitly build for x86_64
```

The Makefile sets architecture-specific build args: `NEOVIM_ARCH`, `NODE_ARCH`, `GO_ARCH`, and `UBUNTU_DEFAULT_MIRROR`. It also creates the shared Docker network `yolo-internal` (via the `yolo-internal` target — `--internal`, subnet `192.168.10.0/24`, gateway `.1`) and touches empty placeholder config files (`gitconfig`, `model.json`, `opencode.json`, `env`) if they don't exist. The companion `api-gateway/` subproject builds the `llm-gateway` container that sits on this network. The `ccxray/` subproject builds an optional `ccxray` observability sidecar on the same network (see Architecture → ccxray Observability Sidecar).

The gateway has a build-time toggle `BLOCK_LAN` (default `1`). `make BLOCK_LAN=0 -C api-gateway run` disables the RFC 1918 DROP rules (single-host / home use where LAN access is acceptable). The default `1` blocks all RFC 1918 destinations. The flag is passed via `--build-arg BLOCK_LAN=...`; the Makefile uses a `FORCE` dep so switching the value always re-invokes `docker build`, with Docker's layer cache skipping unchanged work.

## Running

```bash
bin/yo            # Launch Claude Code, auto mode (default tool + mode)
bin/yo -y         # YOLO mode (skip permission prompts)
bin/yo codex      # Launch Codex instead;  bin/yo opencode for OpenCode
bin/yo sh         # Open a shell in the container
bin/yo status     # Container state / image / staleness; also: ls, reset, stop
```

### Tool and mode selection

`bin/yo` takes the tool and permission mode as arguments rather than dispatching
on its invoked name:

- **Tool** (positional): `claude` (default) · `codex` · `opencode`.
- **Mode**: `--safe` (prompt for everything) · `--auto` (default) · `-y`/`--yolo` (skip prompts). Each maps to the right per-tool flags, e.g. claude auto → `--permission-mode auto`, claude yolo → `--dangerously-skip-permissions`, codex yolo → `--yolo`.
- **Model**: `-m, --model NAME` (default unset).

Defaults come from `YOLO_TOOL` / `YOLO_MODE` / `YOLO_MODEL`; resolution is **CLI flag > env var > built-in**. Anything after the tool name is forwarded to the agent verbatim.

### Legacy symlink shim (`bin/opencode-docker`)

`bin/opencode-docker` is a thin compatibility shim that forwards to `bin/yo`,
preserving the old name-based interface. The invoked name selects the equivalent `yo` call: `claude`/`claude-docker` → `yo -m opus claude`, `claude-yolo` → `yo -y claude`, `codex`/`codex-docker` → `yo codex`, `codex-yolo` → `yo -y codex`, `opencode-docker` → `yo opencode`. A leading `sh`/`bash`/`claude` argument still takes precedence over the name (→ `yo exec sh`/`yo exec bash`/`yo --safe claude`). New setups should symlink `bin/yo` directly.

## Architecture

### Container Lifecycle (`bin/yo`)
(`bin/opencode-docker` is a compatibility shim that forwards to `bin/yo` — see Running → Legacy symlink shim.)
- Computes a SHA1 hash of the project's git root path to uniquely name each container (`yolo-dev-<hash>`; prefix overridable via `YOLO_CONTAINER_PREFIX`)
- Tracks hash→path mappings in `~/.yolocontainer_map`
- Detects stale containers (image ID mismatch) and prompts to replace them
- Checks for active exec sessions before replacing
- If `YOLO_DOCKER_CONTEXT` is set, all `docker` invocations use `docker --context "$YOLO_DOCKER_CONTEXT"`. This lets you pin the script to a specific Docker context (e.g. `orbstack`) without changing the system-wide active context.
- Containers are attached to the `yolo-internal` Docker network (`--internal`), so they can reach each other and `llm-gateway` by name but cannot reach the host or external networks directly. Outbound traffic egresses through `llm-gateway` (iptables MASQUERADE + RFC 1918 DROP + nginx reverse-proxy for AI APIs). The container is launched with `--cap-add=NET_ADMIN` and `--dns 8.8.8.8 --dns 1.1.1.1`. `entrypoint.sh` resolves `llm-gateway` via Docker's embedded DNS (always present at `127.0.0.11` on custom networks, regardless of `--dns`) and rewrites the default route to that IP; the explicit upstream DNS servers handle external lookups (forwarded through the router by NAT) since the host's resolver is unreachable on `--internal`

### ccxray Observability Sidecar (`ccxray/`)
`ccxray/` builds a `ccxray` container that transparently proxies Claude Code ↔ Anthropic traffic and serves a live dashboard (system prompts, per-call cost, token/context usage). Bring it up with `make -C ccxray run` after `llm-gateway`.

- **Network:** joins the existing `yolo-internal` (single-homed — no `bridge`, no published port of its own). Its `entrypoint.sh` rewrites the default route to `llm-gateway` exactly like a dev container, so it egresses through the gateway NAT. Runs with `--cap-add=NET_ADMIN` and `--dns 8.8.8.8 --dns 1.1.1.1`.
- **Upstream:** no env file, so `ANTHROPIC_BASE_URL` is unset → ccxray forwards directly to `api.anthropic.com`, passing the client `Authorization` header (Team Plan OAuth Bearer) through untouched. It must NOT receive `AUTH_TOKEN` (would `401` the OAuth requests) or `ANTHROPIC_BASE_URL` (would re-chain into itself).
- **Dashboard exposure:** the gateway's nginx (`api-gateway/ccxray.conf`) reverse-proxies root `/` on port `33390` → `ccxray:5577`, published to the host at `http://127.0.0.1:33390`. Deferred DNS (`resolver 127.0.0.11`) lets the gateway start before/independently of ccxray and recover on ccxray restart.
- **Mounts:** `<repo>/claude:/root/.claude:ro` (the shared transcripts — `server/cost-worker.js` reads `~/.claude/projects/**/*.jsonl` for token-usage counting) and `<repo>/ccxray-data:/root/.ccxray` (its own logs/state, persisted; `.gitignore`d). Runs as root so it reads the host-uid-owned transcripts regardless of UID mapping.
- **Routing dev → ccxray:** set `ANTHROPIC_BASE_URL=http://ccxray:5577` in `env`. dev→ccxray is an intra-`yolo-internal` hop (does not traverse the gateway default-route NAT); only ccxray→Anthropic is NAT'd. With this set ccxray is in Claude Code's request path — `--restart unless-stopped` mitigates outages.

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
The Dockerfile appends `[ -f ~/.env ] && { set -a; source ~/.env; set +a; }` to `~/.bashrc`. Any `KEY=VALUE` pair in the host-side `env` file is exported into every shell (and therefore into `opencode` / `claude` when launched from a login-style shell). Real API keys live in `api-gateway/default.conf` (not in `env`). For Team Plan / OAuth login (the default), point Claude Code at the ccxray sidecar with `ANTHROPIC_BASE_URL=http://ccxray:5577` and set no `ANTHROPIC_API_KEY` (a key can shadow OAuth); ccxray forwards the OAuth token straight to Anthropic and captures the session. For API-key auth, instead set a dummy `ANTHROPIC_API_KEY` + `ANTHROPIC_BASE_URL=http://llm-gateway/claude/` so the gateway injects the real key (this path bypasses the ccxray dashboard).

### User Remapping (`entrypoint.sh`)
The container starts as root. The entrypoint receives `HOST_UID`/`HOST_GID` via environment variables and remaps the `dev` user's UID/GID to match, deleting any conflicting system users/groups (e.g. macOS GID 20 vs Ubuntu's `dialout`). It then `chown`s `/home/dev` and `exec`s the command. All `docker exec` calls use `--user` to run as the remapped UID/GID. The `dev` user has passwordless sudo. A `/.ready` lock file synchronizes: the entrypoint holds an exclusive `flock` during remapping, and `yo` waits on that lock before issuing the first `exec`. After remapping, the entrypoint resolves `llm-gateway` via Docker's embedded DNS (with `getenv hosts ...`) and rewrites the default route to that IP. Docker's bridge gateway `192.168.10.1` is unreachable on `--internal` networks, so without this rewrite no outbound traffic works.

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
