# Nico 原生设计系统

来源：[Nico design system](https://www.figma.com/design/jEAPJHkP5H4FWMoqH8ovYo/Nico-design-system?node-id=13-177)。提取日期：2026-09-20。源文件保持只读。

## 覆盖范围

- 64 个页面完成盘点。含组件的 38 个页面导出为本地原生图层规范。
- 45 个组件集、2,506 个变体、12 个独立组件；包括 UI 页的 Navigation menu、分段 Progress 和 5 个 Agent 标识。
- 360 个变量：8 个集合，保留 ID、原名、别名和模式。颜色有 Light / Dark，Typography 有 CN / EN。
- 54 个文字样式、6 个图片填充样式、9 个效果样式。
- Carousel、Empty status、Image view、Table、Timeline、Menu、Steps、Date picker、Form、Time picker、Verification code input、Upload、Tipseen 共 13 个页面在源文件中为空，目录明确标为空白；没有为它们编造设计。

## 原生映射

| Figma / Web 概念 | 原生实现 |
| --- | --- |
| CSS color variable | `NicoColorToken` → 动态 `NSColor` / SwiftUI `Color` |
| 数值变量（尺寸、圆角、描边、模糊、行高、字重） | `NicoMetricToken` → `CGFloat` |
| 字体族变量 | `NicoStringToken`；CN 为 PingFang SC，EN 为打包的 Poppins |
| 变量别名与主题 | `Nico.resolve` 按目标集合选择模式，检测缺失与循环引用 |
| 组件、变体和嵌套实例 | `NicoPage` / `NicoComponentSet` / `NicoVariant` / `NicoComponent` |
| 原始矢量路径 | Core Graphics 路径；不替换成外形不同的符号 |
| 图片样式 | 源文件原始图片，按 Figma SHA-1 命名 |
| 文本与效果 | AppKit 字体、段落样式、原生描边与阴影 |

实现不运行 JavaScript、CSS 或 WebView。JSON 是设计资源数据，SwiftUI / AppKit / Core Graphics 负责渲染。

## 使用

```swift
Text("额度用量")
    .foregroundStyle(Nico.color(.colorText))
    .nicoTypography("14/Regular/Default")

Button("刷新") { refresh() }
    .buttonStyle(NicoButtonStyle(kind: "ghost"))

NicoTextField(title: "CLI 路径", text: $path)
Toggle("启用", isOn: $enabled).toggleStyle(NicoSwitchStyle())
NicoTag(color: "orange", size: .lg) { Text("数据已过期") }
NicoProgress(value: remainingFraction)

// 访问任意原始组件变体；同名组件可通过页面及组件集 ID 精确区分。
if let (page, variant) = NicoLibrary.component("Button", properties: ["size": "md", "kind": "filled"]) {
    NicoComponent(page: page, variant: variant)
}
```

所有源变体都能以原生视图查看。`NicoComponent` 是设计图层视图，保留源尺寸与层级；它本身不推断业务行为。可交互封装目前包括 Button、TextField / SecureField、Switch、Tag、Progress、Select 和 Segmented。Select 与 Segmented 用于业务页面的指标、时间范围和设置选项；保留原生按钮键盘操作，外观使用导出的组件变体。复杂组件（例如 Modal、Drawer、Dropdown）的完整设计在目录中可查看，业务中应组合对应原生呈现与数据行为，不把示例点击当成真实操作。

设计目录仅供开发使用，不对用户暴露：应用内没有入口，只能通过 `--nico-gallery` 离线预览启动，提供组件参数检查、全部变体分页、变量检索、明暗主题、中英文字体、文字/图片/效果预览和原生交互示例。总览、详情、设置与菜单栏共用配色、文字、卡片、按钮、输入框和状态标签。设置页以 Nico 卡片替代系统 Form，时间范围与外观使用 Segmented，指标、刷新周期与保留天数使用 Select。

## 验证与离线预览

```sh
./scripts/test.sh
./scripts/build.sh
# 特例：仅设计系统可由 Swift 可执行文件离线预览，不需要 CLI/账户/辅助程序。
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run VibeStatistics --nico-gallery
# 导出各组件集首尾变体与独立组件的明暗原生渲染 PNG：
.build/debug/VibeStatistics --nico-render "$PWD/.local/nico-render"
```

离线入口在构造 UsageStore 之前执行，不发额度请求，也不写历史快照。目录中的深色开关仅作用于当前预览。

测试核对变量解析、主题透明度、全部组件/变体数量、树索引、路径语法、基础控件状态、字体和资源完整性。批量渲染用于人工视觉核对；它不是 2,506 个变体全部通过逐像素比较的证明。字体的抗锯齿会受到 macOS 渲染器影响。

## 更新来源

`Sources/VibeStatistics/Resources/Nico/foundations.json` 保留全部原始变量及样式；`inventory.json` 是组件目录；`components-<page-id>.json` 保存去重后的原生图层树。变量名生成脚本：

```sh
python3 scripts/nico/generate-tokens.py
```

`export-page.js` 是只读 Figma Plugin API 提取脚本，用于 Figma MCP 的 `use_figma`。设置 `PAGE_ID`、`OFFSET`，按 14,000 字符顺序拼接返回块到 `.local/nico-export/<page-id>.b64`；所有块的 `length` 必须一致，否则重新读取该页面。之后：

```sh
python3 scripts/nico/decode-export.py .local/nico-export Sources/VibeStatistics/Resources/Nico
```

图层文件是应用必需的设计资源，需要提交；传输分块、参考截图、构建产物仅放在已忽略的 `.local/`、`.build/`、`dist/`。Poppins 来自 [Google Fonts](https://github.com/google/fonts/tree/main/ofl/poppins)，SIL Open Font License 随字体打包。
