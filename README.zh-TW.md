# yolo-container

在 Docker 容器中執行 [opencode](https://opencode.ai) 與 [Claude Code](https://claude.ai/code)。
AI 程式編寫代理在能夠自由讀取、寫入與執行時效果最佳，但將這種程度的存取權交給主機上的代理程序是有風險的。本專案將整個流程包裝在容器中，讓代理可以不受限制地運作，同時保護你的主機。

每個專案都有自己的持久容器（以 git 根目錄路徑為索引鍵）。原始碼以 bind mount 方式掛載到容器內。所有專案容器共享一個 `--internal` 的 Docker 網路（`yolo-internal`）：彼此能互通，但無法直接連到主機或任何 RFC 1918 內網。對外流量會經過 `llm-gateway` 容器（nginx + iptables），由它做 NAT 轉送公網流量、並反向代理 AI API（注入真正的 API key），所以專案容器看不到真 key。另有一個選用的 `ccxray` sidecar 位於同一網路，會透明代理 Claude Code 與 Anthropic 之間的流量，並提供即時儀表板以檢視 session（系統提示、每次呼叫成本、token/context 用量）。

## 前置需求

- Docker
- **macOS 限定：** 必須使用 [OrbStack](https://orbstack.dev/)。Docker Desktop 的 iptables 規則會干擾 gateway 容器的 NAT routing，無論 `BLOCK_LAN` 設定為何都會導致對外連線失敗。同時必須在 shell profile 中明確設定 `YOLO_DOCKER_CONTEXT`，Makefile 會強制要求此設定：
  ```bash
  # 加入 ~/.bashrc、~/.zshrc 或 ~/.profile
  export YOLO_DOCKER_CONTEXT=orbstack
  ```

## 設定

### 1. 檢視 Dockerfile

開啟 `Dockerfile`，確認以下設定符合你的環境：

- **`UBUNTU_MIRROR`** — APT 鏡像站（預設為台灣鏡像站）。請改成離你最近的站點，或改回 `ports.ubuntu.com`。
- **`NODE_VERSION`**、**`GO_VERSION`** — 工具鏈版本。
- 架構參數（`NEOVIM_ARCH`、`NODE_ARCH`、`GO_ARCH`）由 `make` 根據主機架構自動設定。

### 2. 建立必要的設定檔

這些檔案因包含個人設定而列於 `.gitignore`。`make` 會對任何缺少的檔案 `touch` 空白佔位檔，但建議在首次使用前先填入內容：

| 檔案 | 用途 |
|------|------|
| `gitconfig` | 建置時複製到 `/home/dev/.gitconfig`。你平常的 git 設定（姓名、Email 等）。 |
| `opencode.json` | 建置時複製到 `/home/dev/.config/opencode/`。OpenCode 設定。 |
| `model.json` | 建置時複製到 `/home/dev/.local/state/opencode/`。OpenCode 模型設定。 |
| `claude.json` | 執行時 bind mount 到 `/home/dev/.claude.json`。Claude Code 設定。 |
| `env` | 執行時 bind mount 到 `/home/dev/.env`。`KEY=VALUE` 格式的環境變數，由 `.bashrc` 自動載入到每個 shell（適合放 API 金鑰）。 |

`claude/` 目錄在執行時 bind mount 到 `/home/dev/.claude`，用於持久保存 Claude Code 狀態。

由於 `gitconfig`、`opencode.json` 和 `model.json` 是*建置時複製進去的*，修改後必須重新建置映像檔（`make`）。`claude.json` 和 `env` 是 bind mount，修改後在新開的 shell 中立即生效。

## 建置

```bash
# 自動偵測主機架構（arm64 或 x86_64）
make

# 或明確指定
make arm64
make amd64
```

macOS 使用者在建置前，必須先把 `YOLO_DOCKER_CONTEXT` 加到 shell profile（詳見前置需求說明）：

```bash
# 加入 ~/.bashrc、~/.zshrc 或 ~/.profile
export YOLO_DOCKER_CONTEXT=orbstack
```

`bin/yo` 與 Makefile 都會讀取此變數，並把所有 `docker` 呼叫導向指定的 context。重新載入 profile（或開新 shell）後，照常執行 `make` 即可。

第一次建置時，若 `yolo-internal` Docker 網路（`--internal`、`192.168.10.0/24`）不存在，也會一併建立。在啟動任何專案容器之前，還必須先建好 gateway：

```bash
cd api-gateway
cp default.conf.example default.conf  # 然後填入你真正的 ANTHROPIC_API_KEY
make run
```

這會啟動 `llm-gateway`（單一 nginx 容器），同時接 `bridge`（WAN）與 `yolo-internal`（LAN，固定 IP `192.168.10.2`）。它負責對外流量的 iptables MASQUERADE、把 `yolo-internal` 出來的所有 RFC 1918 目的位址 DROP 掉，並把 `https://api.anthropic.com` 反向代理到 `http://llm-gateway/claude/`。

### 觀測儀表板（ccxray）

`ccxray` sidecar 會透明代理 Claude Code 與 Anthropic 之間的流量，並提供即時儀表板（系統提示、每次呼叫成本、token/context 用量）。它加入同一個 `yolo-internal` 網路、透過 gateway NAT 對外，並以唯讀方式讀取共用的 `claude/` 對話記錄來統計 token 用量：

```bash
cd ccxray
make run
```

gateway 的 nginx 會反向代理此儀表板，發佈到 host 的 <http://127.0.0.1:33390>。ccxray 自己的記錄存放於 `ccxray-data/`。

### 將 Claude Code 指向 gateway 或 ccxray

在 host 端的 `env` 檔（會 bind mount 進每個專案容器的 `~/.env`）裡：

**Team Plan／OAuth 登入**（建議）— 走 ccxray，讓 session 出現在儀表板。Claude Code 會送出自己的 OAuth token，ccxray 原封不動地轉發。請**不要**設定 `ANTHROPIC_API_KEY`（設了可能會蓋掉 OAuth）：

```
ANTHROPIC_BASE_URL=http://ccxray:5577
```

**API key** — 指向 gateway，由它注入真正的 key。保留一個 dummy key，避免某些 SDK 因缺 key 而拒絕啟動（此路徑不會經過 ccxray 儀表板）：

```
ANTHROPIC_API_KEY=sk-ant-dummy
ANTHROPIC_BASE_URL=http://llm-gateway/claude/
```

## 使用方式

啟動器是 `bin/yo`。它會在此專案的沙箱容器內執行 AI agent；工具與權限模式是
**參數**，而非腳本名稱。

```bash
# 啟動 Claude Code，自動模式（預設工具＋模式）
bin/yo

# YOLO 模式 — 跳過所有權限提示
bin/yo -y

# 其他工具（一樣可用 --safe / --auto / -y 選模式）
bin/yo codex
bin/yo opencode

# 在容器中開啟 shell
bin/yo sh

# 管理此專案的容器
bin/yo status      # 狀態、映像檔、是否過期
bin/yo ls          # 列出所有 yo 容器（專案路徑 -> 容器）
bin/yo reset       # 重建（例如剛 `make` 完之後）
bin/yo stop        # 停止並移除
```

工具名稱**後面**的所有參數都會原封不動轉發給 agent，例如
`bin/yo claude --resume` 會在容器內執行 `claude --resume`。

### 工具與模式

| 項目 | 可選值 | 預設 |
|------|--------|------|
| 工具 | `claude`／`codex`／`opencode` | `claude` |
| 模式 | `--safe`（每件事都詢問）／`--auto`／`-y`、`--yolo`（跳過提示） | `auto` |
| 模型 | `-m, --model NAME` | 未設定 |

每種組合都會對應到該工具正確的旗標，例如 `claude` auto → `claude --permission-mode auto`、
`claude` yolo → `claude --dangerously-skip-permissions`、`codex` yolo → `codex --yolo`。
預設值取自 `YOLO_TOOL`／`YOLO_MODE`／`YOLO_MODEL` 環境變數（與 `YOLO_DOCKER_CONTEXT`
放在同一處的 shell profile 即可）；解析順序為 **CLI 旗標 > 環境變數 > 內建預設**。

啟動器會自動偵測並替換執行中的舊版映像檔容器。若有正在進行的 session，替換前會先詢問確認。

### 舊版符號連結介面（`bin/opencode-docker`）

`bin/opencode-docker` 保留為轉發給 `yo` 的精簡相容 shim，讓舊有的符號連結命名方式
繼續可用。把它以下列其中一個名稱符號連結進 `$PATH`：

| 符號連結名稱            | 轉發為              | 等同於                                          |
|-------------------------|---------------------|-------------------------------------------------|
| `opencode-docker`       | `yo opencode`       | `opencode`                                       |
| `claude`                | `yo -m opus claude` | `claude --permission-mode auto --model opus`     |
| `claude-docker`         | `yo -m opus claude` | `claude --permission-mode auto --model opus`     |
| `claude-yolo`           | `yo -y claude`      | `claude --dangerously-skip-permissions`          |
| `codex`／`codex-docker` | `yo codex`          | `codex`                                          |
| `codex-yolo`            | `yo -y codex`       | `codex --yolo`                                   |

```bash
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude        # 自動模式
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude-yolo   # YOLO 模式
```

新的設定建議直接符號連結 `bin/yo`，並把模式當成參數傳入。
