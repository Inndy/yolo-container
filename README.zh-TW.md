# yolo-container

在 Docker 容器中執行 [opencode](https://opencode.ai) 與 [Claude Code](https://claude.ai/code)。
AI 程式編寫代理在能夠自由讀取、寫入與執行時效果最佳，但將這種程度的存取權交給主機上的代理程序是有風險的。本專案將整個流程包裝在容器中，讓代理可以不受限制地運作，同時保護你的主機。

每個專案都有自己的持久容器（以 git 根目錄路徑為索引鍵）。原始碼以 bind mount 方式掛載到容器內，所有專案容器共享同一個 Docker 網路（`yolo-container-net`），讓同層的服務可以互相通訊。

## 前置需求

- Docker

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

第一次建置時，若 `yolo-container-net` Docker 網路不存在，也會一併建立。

## 使用方式

```bash
# 啟動 opencode（預設）
bin/opencode-docker

# 在容器內啟動 Claude Code（原始 `claude`，不帶任何旗標）
bin/opencode-docker claude

# 在容器中開啟 shell
bin/opencode-docker sh
bin/opencode-docker bash
```

### 透過符號連結選擇 Claude 啟動模式

腳本依據被呼叫時的名稱來選擇啟動模式：

| 符號連結名稱       | 執行指令                                        | 模式       |
|--------------------|-------------------------------------------------|------------|
| `opencode-docker`  | `opencode`                                      | OpenCode   |
| `claude`           | `claude --permission-mode auto --model opus`    | 自動模式   |
| `claude-docker`    | `claude --dangerously-skip-permissions`         | YOLO 模式  |
| `claude-yolo`      | `claude --dangerously-skip-permissions`         | YOLO 模式  |

典型設定方式如下：

```bash
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude        # 自動模式
ln -s "$PWD/bin/opencode-docker" ~/.local/bin/claude-yolo   # YOLO 模式
```

命令列傳入的任何額外參數都會轉發給底層指令。

腳本會自動偵測並替換執行中的舊版映像檔容器。若有正在進行的 session，替換前會先詢問確認。
