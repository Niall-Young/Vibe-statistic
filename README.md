<div align="center">

  <img src="Resources/Branding/Creature.svg" width="96" height="96" alt="Vibe Statistics Icon" style="border-radius: 20px;" />

  # Vibe Statistics

  **原生 macOS 菜单栏 AI Agent 额度与用量看板**  
  *A sleek, privacy-first native macOS menu bar dashboard for coding agent quotas, balances & usage trends.*

  <p align="center">
    <a href="https://github.com/Niall-Young/Vibe-statistic/releases"><img src="https://img.shields.io/github/v/release/Niall-Young/Vibe-statistic?color=007AFF&label=Release&logo=apple" alt="Release" /></a>
    <img src="https://img.shields.io/badge/Platform-macOS%2026%2B-000000?logo=apple&logoColor=white" alt="Platform" />
    <img src="https://img.shields.io/badge/Arch-Apple%20Silicon%20(arm64)-555555?logo=apple&logoColor=white" alt="Architecture" />
    <img src="https://img.shields.io/badge/Swift-6.0%20Toolchain%20(Swift%205%20Mode)-F05138?logo=swift&logoColor=white" alt="Swift Version" />
    <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20Nico%20Design-6C5CE7" alt="Design System" />
    <img src="https://img.shields.io/badge/Privacy-100%25%20Local%20%7C%20Read--Only-10B981" alt="Privacy" />
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License" /></a>
  </p>

  <p align="center">
    <a href="#-中文文档">简体中文</a> •
    <a href="#-english">English</a> •
    <a href="https://github.com/Niall-Young/Vibe-statistic/releases">GitHub Releases</a> •
    <a href="docs/NicoDesignSystem.md">原生设计系统说明</a>
  </p>

</div>

---

<a id="-中文文档"></a>
## 🇨🇳 中文文档

### 💡 项目简介

**Vibe Statistics** 是一款专为 **macOS 26 / Apple Silicon** 打造的原生菜单栏用量统计面板。它采用 **SwiftUI + AppKit + SwiftData** 构建，帮助开发者在单个菜单栏窗口和原生面板中，一站式洞察本机各类 AI Coding Agent 的额度窗口、到期时间、账户余额与历史消耗趋势。

- 🛡️ **严格只读与纯本地**：无任何后台云端服务，不发起模型推理任务，不修改任何 Agent 的配置文件；
- 📐 **忠于原生与专业设计**：完整内置 Nico 设计系统（2,500+ 原生变体与动态 Token），融合 MingCute 图标，完美适配 macOS 深浅色模式；
- 📊 **严谨的数据哲学**：缺失数据绝不补零，估算时间明确标注，不同时区严格按本机转换，不把未知单价的 Token 或余额变动妄加折算为虚假费用。

---

### ✨ 核心特性

- 🐾 **常驻菜单栏与全局总览**
  - 点击菜单栏抽象小生物图标即可弹出快览卡片，实时掌握所有已连接 Agent 的额度状态；
  - 拥有完整的独立总览大窗口，支持按 Agent 名称实时过滤与快捷搜索。
- 🧩 **全套 Nico 原生设计系统**
  - 45 个组件集、2,506 个变体、360 个变量及 69 种文本/特效样式；
  - 包含平直侧边栏、52pt 紧凑顶部栏、20 段精确额度进度条与平滑色彩过渡；
  - 可通过独立预览指令 `--nico-gallery` 离线体验全套设计组件库（详见 [原生设计系统说明](docs/NicoDesignSystem.md)）。
- 📈 **科学严谨的趋势与消耗视图**
  - **7 / 30 天每日趋势**：每根柱代表当日最后一次成功观测值，按账户与指标严格隔离，空缺日期不补零；
  - **每日真实消耗视图**：仅统计同一额度窗口内（重置时间一致）相邻两次观测的下降绝对值；跨周期重置、充值与采集空白断档一律剔除；
  - **本地 Token 统计**：专门解析 Claude Code / DeepSeek 的本地日志，按消息 ID 去重流式片段，分列输入、输出与缓存用量。
- 🔐 **系统级安全隔离与沙盒保护**
  - 凭据依托 **macOS 钥匙串（Keychain）**，后台轮询默认采用静默读取机制，绝不无故弹出授权弹窗骚扰；
  - Python 桥接程序在 macOS **`sandbox-exec`** 沙盒内严格执行，物理级阻断访问桌面、文稿、下载及主目录 `.git` 等隐私路径。
- ⚡ **智能调度与持久化**
  - 默认 5 分钟定时刷新（支持 1 / 15 分钟切换）；
  - 具备请求合并（Request Coalescing）、失败退避重试、系统休眠自动暂停与唤醒即时刷新；
  - 本地快照依托 SwiftData 保存，默认留存 90 天（可调为 30 天），支持随时一键清除历史数据。

---

### 🤖 支持的 Agent 与数据来源

应用启动或刷新时会自动探测本机环境，**仅展示已安装并在本机可用的 Agent**。未安装项不读取凭据、不发起查询。

| Agent | 本机入口 / 机制 | 授权与数据来源 | 特性与隔离规则 |
| :--- | :--- | :--- | :--- |
| **Codex** | `~/.local/bin/codex` | 官方 app-server `account/read`、`account/rateLimits/read` | 复用 CLI 登录态；展示多段额度窗口与附加 Credits；严格限定读取 `~/.codex` |
| **Kimi Code** | `~/.kimi-code/bin/kimi` | 本地回环临时/驻留 Server；GET OAuth usage / userinfo | 兼容旧版字段与新版 quota 结构；需先在 CLI 完成登录 |
| **Qoder CN** | `~/.qoder-cn/entry/qodercn` | 官方 SDK `getUsageInfo()` 解析至 `qoderclicn` | 复用 CLI 登录态或用户填入的 PAT；SDK 锁定版本运行 |
| **Claude Code** | `~/.claude/settings.json` | 官方 DeepSeek 余额接口 或 智谱 GLM Coding Plan 接口 | 纯读取配置；按 API Key 指纹隔离历史快照；换 Key 自动分区 |
| **Antigravity** | `~/.local/bin/agy` | 后台伪终端（PTY）交互读取 `/usage` 与 `/credits` | 不触发推理任务；倒计时换算的重置时间明确标注为「估算」 |

#### 🌐 扩展 API 查询来源

| API 查询来源 | 调取接口与指标 | 适用范围说明 |
| :--- | :--- | :--- |
| **DeepSeek** | 官方 `/user/balance` 账户余额与赠金 | 可与 Codex、Kimi Code、Qoder CN、Claude Code 关联 |
| **智谱 GLM Coding Plan** | 官方 `/api/monitor/usage/quota/limit` 剩余比例、调用次数及重置周期 | 适用于国内个人版 GLM Coding Plan（不含团队版/海外版） |

> [!NOTE]
> 同一个 API Key 被多个 Agent 关联时，系统会自动合并为单次查询，并标明共享额度；不同 Key 绝不跨账户汇总。

---

### 🚀 快速开始

#### 方式一：直接安装（推荐）

1. 前往 [GitHub Releases](https://github.com/Niall-Young/Vibe-statistic/releases) 下载最新版本的 ZIP 压缩包（例如 `Vibe-Statistics-v0.1.2-arm64.zip`）；
2. 解压后将 `Vibe Statistics.app` 拖移至 macOS 的 **「访达」→「应用程序（/Applications）」** 目录；
3. 从访达中双击打开。

> [!TIP]
> **关于系统安全提示**：由于首发版本采用 ad-hoc 签名且未做 Developer ID 公证，若系统拦截提示，请在确认下载完整性（可核对同名 `.sha256` 校验和）后，前往 macOS **「系统设置」→「隐私与安全性」**，点击 **「仍要打开」** 即可。无需关闭系统的 Gatekeeper。

#### 方式二：从源码构建

构建完整应用需满足：
- 运行环境：macOS 26、Apple Silicon 芯片；
- 开发工具：Xcode（默认安装于 `/Applications/Xcode.app`）、Swift 6 工具链（Swift Package 使用 Swift 5 语言模式）及系统内置 Python3。

```sh
# 1. 克隆代码仓库
git clone https://github.com/Niall-Young/Vibe-statistic.git
cd Vibe-statistic

# 2. 运行完整构建脚本（自动下载锁定的 Python/Node 依赖运行时并打包）
./scripts/build.sh '/Applications/Vibe Statistics.app'

# 3. 在访达的「应用程序」中启动 Vibe Statistics
```

> [!IMPORTANT]
> - 构建脚本默认会将可执行文件、Python/Node 离线辅助运行时和依赖完整封装到 `.app` 内部；
> - 请避免直接在 IDE 终端内运行裸二进制文件，以免菜单栏归属被错误关联到终端工具。

---

### ⌨️ 快捷键与操作指南

| 快捷键 | 功能操作 | 说明 |
| :--- | :--- | :--- |
| <kbd>⌘</kbd> + <kbd>O</kbd> | **打开主窗口** | 从任意状态呼出主应用总览面板 |
| <kbd>⌘</kbd> + <kbd>U</kbd> | **切换摘要视图** | 聚焦查看顶部四大指标总览卡片 |
| <kbd>⌘</kbd> + <kbd>R</kbd> | **立即刷新** | 触发所有可用 Agent 的数据拉取 |
| <kbd>⌘</kbd> + <kbd>,</kbd> | **应用偏好设置** | 打开设置面板配置路径、刷新频率与凭据 |
| <kbd>⌘</kbd> + <kbd>W</kbd> | **关闭当前窗口** | 关闭主窗口后，菜单栏图标依然在后台静默运行 |
| <kbd>⌘</kbd> + <kbd>Q</kbd> | **完全退出** | 彻底退出应用及所有后台监控辅助任务 |

---

### 📊 数据口径与统计边界

为了向开发者提供真实、严谨且不误导的数据，Vibe Statistics 严格遵守以下统计原则：

> [!IMPORTANT]
> 1. **非零原则**：当接口没有返回数据、网络中断或登录失效时，界面标记为“未知”或保留旧数据并加注“已过期”，**绝对不显示为假 0**；
> 2. **周期隔离**：不同时区严格转换至当前 macOS 本机时区；通过倒计时逆推的到期时间明确标注为 **「估算时间」**；
> 3. **真实消耗计算**：只有在 **同一个额度重置周期内** 的相邻两次有效采集，才会计算额度消耗降幅；跨周期的重置、充值回弹以及采集空档，一概不参与消耗计算；
> 4. **余额不等于消耗**：账户余额变动可能受充值、赠券到期等多种因素影响，因此余额类指标不计入消耗走势图；缺少官方精准计费凭证前，绝不将未知单价的 Token 强行估算为金钱费用。

---

### 🔒 安全、沙盒与凭据管理

- 🔐 **静默凭据读取**：保存于 macOS Keychain 中的 API Key / PAT，仅在运行时常驻加密内存，设置或删除后即时同步，轮询刷新时阻断系统弹窗提示；
- 📦 **严格进程沙盒**：底层负责调用的 Python 桥接程序使用 `sandbox-exec` 启动，系统沙盒策略阻断其触碰用户的 `~/Desktop`、`~/Documents`、`~/Downloads` 等个人目录；
- 🛑 **无项目数据泄露**：查询工作空间限制在应用专属的安全目录，禁止 Git 向上回溯查找仓库，绝不读取用户项目的源码或对话上下文。

---

### 🛠 项目架构

```text
Vibe-statistic/
├── Sources/VibeStatistics/       # 核心 macOS 原生代码
│   ├── DesignSystem/            # Nico 设计系统（原生组件、主题、语义 Token）
│   ├── Providers/               # 5 个 Agent 及 API 渠道的只读查询协议
│   ├── Storage/                 # SwiftData 本地快照与模型
│   └── Views/                   # 菜单栏、总览、卡片与设置视图
├── Resources/
│   ├── Branding/                # 抽象小生物图标源文件 (Creature.svg)
│   ├── AgentLogos/              # 各 Agent 官方品牌彩色与灰度 PNG 图标
│   ├── MingCute/                # 内置 MingCute 图标库
│   └── Nico/                    # Nico 设计规范原始设计资源
├── Helpers/                     # Python 沙盒只读桥接器与锁定的依赖定义
├── Tests/                       # 涵盖解析、安全沙盒、数据口径与 UI 测试
├── docs/                        # 设计系统与业务进阶文档
└── scripts/                     # 一键构建、打包发布与本地验证脚本
```

#### 本地验证与设计走廊

```sh
# 运行单元测试（覆盖 Python 桥接与 Swift 模块）
./scripts/test.sh

# 独立启动离线设计走廊预览（无需任何凭据）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run VibeStatistics --nico-gallery

# 运行只读真实验证
./scripts/verify.sh
```

---

### ❓ 常见问题 (FAQ)

<details>
<summary><b>Q: 启动后在菜单栏找不到应用图标？</b></summary>

请前往 macOS **「系统设置」→「控制中心」/「菜单栏」**，确认 **「Vibe Statistics」** 是否已被开启并允许在菜单栏显示。应用使用独立标识 `com.niallyoung.vibestatistics`，建议直接从「访达」中的「应用程序」启动。
</details>

<details>
<summary><b>Q: 为什么某些 Agent 始终显示未连接或过期？</b></summary>

Vibe Statistics 采用只读方式探测。请先确保该 Agent 自身的官方 CLI 已在本机正确安装并处于已登录状态（例如先在终端运行 `codex login` 或 `kimi login`）。
</details>

<details>
<summary><b>Q: 提示需要钥匙串授权？</b></summary>

应用默认静默读取凭据，若 macOS 因系统更新或 ad-hoc 重签名导致权限变更，可在 Vibe Statistics「设置」页面中主动点击 **「授权读取凭据」** 完成一次系统批准即可。
</details>

---

<a id="-english"></a>
## 🌐 English

### 💡 Overview

**Vibe Statistics** is a lightweight, privacy-first native macOS menu bar application designed for **macOS 26 & Apple Silicon**. Built on **SwiftUI, AppKit, and SwiftData**, it gives developers a central dashboard to monitor quotas, reset windows, and balances across Codex, Kimi Code, Qoder CN, Claude Code / DeepSeek, and Antigravity CLI.

---

### ✨ Features

- 🖥️ **Native macOS Experience**: Runs quietly in your menu bar with an abstract creature icon; opens an overview window with keyboard shortcuts (<kbd>⌘O</kbd>, <kbd>⌘R</kbd>, <kbd>⌘,</kbd>);
- 🎨 **Nico Native Design System**: 45 component sets, 2,506 variants, and 360 dynamic design tokens; supports native light/dark appearance and MingCute icon set;
- 📊 **Strict Metric Semantics**: Missing data is never coerced to zero. Estimated reset times are explicitly labeled. Drops are summed strictly within the same quota window;
- 🔒 **Zero Telemetry & Local Sandbox**: Runs 100% locally with zero cloud backend. Helper processes run inside an explicit macOS `sandbox-exec` sandbox, strictly denied access to personal directories (`~/Desktop`, `~/Documents`, `~/Downloads`, etc.);
- 🔑 **Keychain Integration**: Credentials are stored securely in the native macOS Keychain with silent background reads that prevent disruptive system popups.

---

### 🤖 Supported Agents & Providers

| Agent | CLI / Host Entry | Auth & Data Channel | Details |
| :--- | :--- | :--- | :--- |
| **Codex** | `~/.local/bin/codex` | App-server `account/read` & `rateLimits/read` | Reuses CLI session; shows rate limit windows & credits |
| **Kimi Code** | `~/.kimi-code/bin/kimi` | Loopback local server; OAuth usage/userinfo | Compatible with both legacy and new quota fields |
| **Qoder CN** | `~/.qoder-cn/entry/qodercn` | Official SDK `getUsageInfo()` | Reuses CLI login or personal access token (PAT) |
| **Claude Code** | `~/.claude/settings.json` | DeepSeek balance API or GLM Coding Plan | Read-only; isolated snapshots per API key fingerprint |
| **Antigravity** | `~/.local/bin/agy` | Background PTY session (`/usage`, `/credits`) | Non-intrusive; marks reset countdowns as estimated |

---

### 🚀 Getting Started

1. Download the latest release `.zip` from [GitHub Releases](https://github.com/Niall-Young/Vibe-statistic/releases);
2. Unzip and drag `Vibe Statistics.app` into your **Applications** folder;
3. Double-click to launch from Finder.

> [!NOTE]
> Since early builds are ad-hoc signed, if macOS displays a security prompt on first launch, go to **System Settings → Privacy & Security** and click **Open Anyway**.

#### Source Build
```sh
# Build full application bundle with bundled dependencies
./scripts/build.sh '/Applications/Vibe Statistics.app'
```

---

### 📜 开源协议 / License

本项目源码基于 [MIT License](LICENSE) 授权开源。  
项目中所包含的第三方组件（Python、Node.js、MingCute 图标、Poppins 字体等）遵循各自原始开源许可，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
