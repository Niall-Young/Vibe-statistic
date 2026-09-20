# Vibe Statistics

原生 macOS Agent 额度与余额面板 · A native macOS dashboard for agent quotas and balances.

[中文](#中文) | [English](#english)

<a id="中文"></a>
## 中文

### 项目简介

供本机使用的 SwiftUI + AppKit 菜单栏应用，统一查看 Codex、Kimi Code、Qoder CN（`qodercn`）、Claude Code / DeepSeek、Antigravity CLI。目标环境为 macOS 26、Apple Silicon。无需后台云服务，不包含公开发布或公证流程。

### 核心能力

- 菜单栏摘要、独立总览窗口、各 Agent 详情、7 / 30 天每日趋势、接入设置。
- 五个只读适配器，保留官方单位、额度窗口、账户隔离与更新时间；缺失值不视为零。
- 默认每 5 分钟刷新，支持 1 / 15 分钟；请求合并、失败退避、休眠暂停及唤醒刷新。
- SwiftData 本地快照，默认保留 90 天，可改为 30 天；新增 Key / PAT 存入 macOS 钥匙串。
- 原生深浅色（工具栏或设置中切换跟随系统 / 浅色 / 深色，自动记住选择）、键盘操作、可访问性标签。开机启动默认关闭。

### 快速开始

需要 Xcode（默认 `/Applications/Xcode.app`）、Swift 6 工具链、`/usr/bin/python3`、Node.js 18+、npm，以及已经安装并登录的 CLI。

```sh
./scripts/build.sh '/Applications/Vibe Statistics.app'
# 在访达的「应用程序」中双击 Vibe Statistics
```

构建脚本可接受应用输出路径；不传参数时输出到 `dist/Vibe Statistics.app`。安装前退出旧应用，避免从开发工具终端直接启动，以免再次关联菜单栏归属。桌面云同步属性可能导致签名失败，建议使用上述本机 Applications 路径。

构建脚本通过锁文件安装 Qoder CN SDK 1.0.45，并安装固定版本的 pyte / wcwidth；复制辅助程序及依赖进入 `.app`。Python、Node 和各 CLI 使用本机安装，不打包其运行时。脚本生成图标并做本地 ad-hoc 签名，没有 Developer ID 签名或公证。

### 使用方法

点击菜单栏图表图标查看摘要，点击 Agent 查看详情。主窗口支持 `⌘O` 打开、`⌘U` 显示摘要、`⌘R` 刷新、`⌘,` 设置、`⌘W` 关闭窗口和 `⌘Q` 退出。关闭主窗口后菜单栏继续运行。

趋势点是每天最后一次成功采集的观测值，按当前账户和指标隔离。首次使用没有之前的历史；空缺日期不补零，跨重置、充值与采集空档不推算消费。DeepSeek 展示整个账户余额及变化，不等同于 Claude Code 支出。Claude Code 详情还展示近 30 天本机 DeepSeek Token：按消息 ID 去重流式片段，分别统计输入、输出与缓存；该统计覆盖本机日志，不按当前 API Key 归因。缺乏历史价格和完整计费证据时不估算费用，不提供项目明细或多设备归因。

### 配置

| Agent | 入口 | 授权与数据 |
| --- | --- | --- |
| Codex | `~/.local/bin/codex` | 官方 app-server `account/read`、`account/rateLimits/read`；复用 CLI 登录，显示实际返回的额度窗口与附加 Credits |
| Kimi Code | `~/.kimi-code/bin/kimi` | 复用本地 Server 或临时启动仅监听回环地址的 Server；GET OAuth usage / userinfo，兼容本机旧字段和新 quota 字段 |
| Qoder CN | `~/.qoder-cn/entry/qodercn` | SDK `getUsageInfo()`；自动解析到 `qoderclicn` 实际运行时，复用登录或使用用户填入的 PAT |
| Claude Code / DeepSeek | `~/.claude/settings.json` | 仅接受 DeepSeek 官方 host，复用配置 Key 或用户填入的 Key，GET `/user/balance`；按 Key 指纹隔离历史 |
| Antigravity | `~/.local/bin/agy` | 后台伪终端读取 `/usage` 与 `/credits`；不发模型任务、不修改 Credits 开关，倒计时换算的重置时间标为估算 |

可以在设置修改 CLI / Node 路径、添加或移除钥匙串凭据，并打开官方账户页面。登录流程仍由官方 CLI 完成，应用显示对应命令。Kimi 和 Antigravity 必须先在 CLI 完成登录。

数据位于 `~/Library/Application Support/VibeStatistics/`。`usage.store` 是历史数据库；`QueryWorkspace` 是只用于元数据查询的空目录。Antigravity 首次查询可能为这个目录确认 CLI workspace trust，绝不会为用户项目自动确认。查询子进程受超时和退出清理控制；CLI 自身可能产生常规登录或运行日志。应用不保存对话正文、账户明文或原始响应日志。DeepSeek 历史按 Key 区分，因此换 Key 会开启新的历史分区。

### 项目结构

- `Sources/VibeStatistics/`：AppKit 生命周期、SwiftUI 界面、SwiftData 历史和 Provider 协议。
- `Helpers/`：Python 只读桥接、Qoder CN 官方 SDK 包装、锁定的依赖声明。
- `Tests/`：解析、错误处理、进程清理、历史口径及刷新状态测试。
- `scripts/`：构建、图标生成、测试与本机验证。

### 开发与验证

```sh
./scripts/test.sh
# 先退出正在运行的应用，再进行完整 .app 的真实只读验证
./scripts/verify.sh
```

`verify.sh` 检查本地签名并启动完整 `.app`，查询五家真实数据、保存快照，输出 `.local/verification/verification.json` 和界面几何报告。任一 Provider 未接通即返回失败；该命令会调用官方额度接口但不调用模型。几何报告不能代替视觉验收，视觉与键盘交互应在实际原生窗口中检查。

2026-09-20 的本机接入已验证：Codex CLI 0.154.0、Kimi 0.42.0、Qoder CN CLI 1.1.43、Antigravity 1.2.7，以及 DeepSeek 官方余额接口。Antigravity 的 AI Credits 当前未启用，应用明确标记，不将其当成零。具体读数会变化，不写入源码。

### 常见问题

- **应用运行但菜单栏无图标**：检查系统设置 → 菜单栏 → 允许在菜单栏显示 → Vibe Statistics。应用使用独立标识 `com.niallyoung.vibestatistics`，从访达或登录项启动；不需要开启 ChatGPT 菜单栏开关。旧开发标识曾被 macOS 26 错误关联到启动它的开发工具，因此改用独立标识并一次性迁移偏好设置，继续使用原历史数据库与钥匙串服务。原有开机启动需在新应用设置中重新开启。菜单栏位置会保存；`isVisible` 为真不代表图标实际在屏幕上。可设置该应用偏好 `statusDiagnosticsPath` 为绝对 JSON 路径，在从访达启动后读取图标窗口坐标与屏幕范围。
- **登录失效或接口不可用**：保留旧读数并标明过期；检查 CLI 登录，再点击刷新。自动重试最多退避到 1 小时。
- **CLI 更新后查询失败**：Qoder SDK 和 Antigravity TUI 都有版本边界；不猜测无法识别的新格式。检查连接提示与 CLI 版本。
- **钥匙串需要授权**：应用自身读取 Key / PAT 时默认禁止授权弹窗，包括自动刷新、手动刷新和打开设置。已读取的凭据仅在本次运行的内存中复用；保存或移除后立即更新。无法静默读取时保留旧数据并显示提示，不会改用其他账户凭据；在设置中主动点击「授权读取凭据」即可允许系统授权。本地 ad-hoc 重新构建后可能需要再次主动授权。官方 CLI 自身的登录或钥匙串提示由对应 CLI 管理。
- **开机启动失败**：注册可能需要在系统设置的登录项中批准。没有静默降低系统保护。
- **没有费用估算**：当前仅提供可靠的官方额度、Credits 与余额，不把余额差额、订阅百分比或 Token 按不明价格换算成费用。
- **本机依赖缺失**：确认 Xcode、Python、Node、CLI 路径，重新运行构建脚本；不能只复制裸可执行文件。

<a id="english"></a>
## English

### Overview

A personal SwiftUI + AppKit menu bar application for Codex, Kimi Code, Qoder CN (`qodercn`), Claude Code / DeepSeek, and Antigravity CLI. Targets macOS 26 on Apple Silicon. No cloud backend, public distribution, or notarization workflow is included.

### Features

- Menu bar summary, overview window, provider details, 7 / 30-day daily observations, and connection settings.
- Five read-only adapters preserving official units, quota windows, account boundaries, and timestamps. Missing values are never treated as zero.
- Five-minute refresh by default, with 1 / 15-minute options; request coalescing, retry backoff, sleep suspension, and wake refresh.
- SwiftData snapshots retained for 90 days by default, optionally 30 days; additional keys / PATs stored in macOS Keychain.
- Native light / dark appearance (choose System / Light / Dark in the toolbar or Settings; the choice is remembered), keyboard access, and accessibility labels. Launch at login is off by default.

### Quick Start

Requires Xcode (default `/Applications/Xcode.app`), a Swift 6 toolchain, `/usr/bin/python3`, Node.js 18+, npm, and installed, authenticated CLIs.

```sh
./scripts/build.sh '/Applications/Vibe Statistics.app'
# Double-click Vibe Statistics in Finder → Applications
```

The build script accepts an app output path; without an argument it writes `dist/Vibe Statistics.app`. Quit the old app before installing, and avoid launching directly from a development tool terminal to prevent menu bar attribution from recurring. Desktop cloud-sync attributes can cause signing failures; prefer the local Applications path above.

The build script installs Qoder CN SDK 1.0.45 through its lockfile and pinned pyte / wcwidth packages, then copies helpers and dependencies into the `.app`. Python, Node, and CLI runtimes remain local dependencies. The script generates an icon and an ad-hoc local signature; it does not perform Developer ID signing or notarization.

### Usage

Click the menu bar chart icon for the summary, then an agent for details. In the main application, use `⌘O` to open the window, `⌘U` for the summary, `⌘R` to refresh, `⌘,` for settings, `⌘W` to close the window, and `⌘Q` to quit. Closing the main window leaves the menu bar app running.

Each chart point is the final successful observation for that day, isolated by current account and metric. No earlier history exists on first use; missing days stay absent. Resets, top-ups, and collection gaps are not converted into spending. DeepSeek shows the entire account balance and its changes, not Claude Code's bill. Claude Code details also show 30-day local DeepSeek tokens, deduplicating streaming fragments by message ID and separating input, output, and cache usage. These statistics cover local logs and are not attributed to the current API key. Historical pricing and complete billing evidence are unavailable, so there are no cost estimates, project breakdowns, or cross-device attribution.

### Configuration

| Agent | Entry point | Authentication and data |
| --- | --- | --- |
| Codex | `~/.local/bin/codex` | Official app-server `account/read` and `account/rateLimits/read`; reuses CLI login and displays returned quota windows and extra Credits |
| Kimi Code | `~/.kimi-code/bin/kimi` | Reuses a local Server or temporarily starts a loopback-only Server; GET OAuth usage / userinfo, supporting the installed legacy fields and new quota fields |
| Qoder CN | `~/.qoder-cn/entry/qodercn` | SDK `getUsageInfo()`; resolves the dispatcher to the actual `qoderclicn` runtime, using CLI login or an explicitly entered PAT |
| Claude Code / DeepSeek | `~/.claude/settings.json` | Accepts only the official DeepSeek host; uses the configured or entered key for GET `/user/balance`, isolating history by key fingerprint |
| Antigravity | `~/.local/bin/agy` | Background PTY for `/usage` and `/credits`; no model prompts or credit-setting changes; countdown-derived reset times are marked estimated |

Settings support CLI / Node paths, adding or removing Keychain credentials, and official account links. Official CLIs own the login flow; the application displays the appropriate commands. Kimi and Antigravity require an existing CLI login.

Data lives under `~/Library/Application Support/VibeStatistics/`. `usage.store` contains history; `QueryWorkspace` is an empty metadata-query workspace. On first use, Antigravity may confirm CLI workspace trust for this directory only, never for user projects. Subprocesses have timeouts and exit cleanup; the CLIs themselves may produce their usual login or runtime logs. The application does not persist conversation text, plaintext account identities, or raw response logs. Changing a DeepSeek key starts a separate history partition.

### Project Structure

- `Sources/VibeStatistics/`: AppKit lifecycle, SwiftUI views, SwiftData history, and the Provider protocol.
- `Helpers/`: read-only Python bridge, official Qoder CN SDK wrapper, and pinned dependency declarations.
- `Tests/`: parsers, error handling, process cleanup, history semantics, and refresh-state tests.
- `scripts/`: build, icon generation, tests, and local verification.

### Development and Verification

```sh
./scripts/test.sh
# Quit the running application before real read-only verification of the complete .app
./scripts/verify.sh
```

`verify.sh` checks the local signature, launches the complete `.app`, queries all five services, persists snapshots, and writes `.local/verification/verification.json` plus UI geometry reports. It fails if any provider is disconnected. It calls official quota endpoints without model inference. Geometry reports do not replace visual acceptance; check visual and keyboard behavior in the actual native windows.

Local integrations were verified on 2026-09-20 using Codex CLI 0.154.0, Kimi 0.42.0, Qoder CN CLI 1.1.43, Antigravity 1.2.7, and the official DeepSeek balance endpoint. AI Credits are currently disabled in Antigravity; the application reports that explicitly instead of showing zero. Live values change and are not committed to source.

### Troubleshooting

- **Running app with no menu bar icon**: check System Settings → Menu Bar → Allow in the Menu Bar → Vibe Statistics. The app uses the independent identifier `com.niallyoung.vibestatistics`; launch through Finder or its login item. The ChatGPT menu bar switch can stay off. macOS 26 had incorrectly associated the old development identity with its launching development tool, so the new identity migrates preferences once and keeps the existing history database and Keychain service. Re-enable any previous launch-at-login preference in the new app. Menu bar placement is preserved; `isVisible` alone does not prove the icon is on screen. Set the app preference `statusDiagnosticsPath` to an absolute JSON path to record icon window coordinates and screen bounds after a Finder launch.
- **Expired login or unavailable service**: previous values remain marked stale. Check CLI authentication and refresh. Automatic retries back off to at most one hour.
- **Failure after a CLI update**: Qoder SDK and Antigravity TUI have version boundaries; unknown formats are not guessed. Inspect the connection message and CLI version.
- **Keychain authorization required**: the app suppresses authentication dialogs when reading keys / PATs during automatic refresh, manual refresh, and opening settings. Successfully read credentials are reused only in memory for the current run and updated immediately after saving or removing them. When silent access fails, previous data is retained with a status message instead of falling back to another account. Click “授权读取凭据” in settings to explicitly allow system authorization. A local ad-hoc rebuild may require another explicit authorization. Login or Keychain prompts initiated by official CLIs remain managed by those CLIs.
- **Launch-at-login failure**: registration may require approval in System Settings. System protections are not silently weakened.
- **No cost estimate**: only reliable official quotas, Credits, and balances are shown. Balance differences, subscription percentages, and tokens without known pricing are not converted into spending.
- **Missing local dependencies**: check Xcode, Python, Node, and CLI paths, then rebuild. Copying the bare executable is insufficient.
