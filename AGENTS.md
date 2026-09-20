# Vibe Statistics

这是面向 macOS 26 / Apple Silicon 的个人菜单栏额度统计应用，使用 SwiftUI、AppKit 和 SwiftData；各服务通过本机 CLI 或官方接口只读接入，无后台云服务。

## 开发入口

- 先阅读 [README.md](README.md)，以其中的数据口径、接入边界和开发说明为准；独立子项目遵循其本地 `AGENTS.md`。
- 使用 Swift 6 工具链；当前 Swift Package 明确采用 Swift 5 语言模式，不要将工具链版本误当成语言模式。
- 统一测试入口为 `./scripts/test.sh`，覆盖 Python 桥接与 Swift 测试。
- 完整应用通过 `./scripts/build.sh` 构建，默认输出 `dist/Vibe Statistics.app`；裸 Swift 可执行文件不包含完整的辅助程序和依赖。
- 真实接入验证、安装和原生界面验收按 README 的「开发与验证」「快速开始」执行；真实验证会查询已登录账户并写入本地快照，不能当成离线单元测试。

## 产品边界

- 保持只读额度查询，不发送模型任务；保留官方单位、额度窗口、账户隔离和更新时间。
- 缺失或不可用的数据不显示为零；估算时间明确标注，不将余额变化或不明价格的 Token 换算为费用。
- 凭据由 macOS 钥匙串和官方 CLI 登录机制管理；遵循 README 中的沙盒、静默凭据读取与本地数据存储边界。
