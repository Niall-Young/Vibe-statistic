# 只读桥接子项目

本目录是 Python 服务桥接与 Node.js ESM 的 Qoder CN SDK 包装层，随 macOS 应用一起打包；本机提供 Python、Node 和各 CLI 运行时。

- 保持 JSON stdin/stdout 协议；不要向 stdout 混入调试文本，也不要在错误信息中暴露凭据或原始账户响应。
- 桥接仅查询额度、Credits、余额与本机用量；Qoder SDK 初始化使用无模型提示的会话，不将查询改成模型调用。
- 子进程使用应用专属查询目录，保留 Git 环境隔离、超时与进程组清理；沙盒启动失败不能降级为无沙盒查询。
- Node 依赖由 `package.json` 与 `package-lock.json` 管理，Python 依赖由 `requirements.txt` 固定；依赖安装和应用打包统一使用根项目构建脚本。
- 桥接测试纳入根项目 `./scripts/test.sh`；本包没有独立的 npm test 脚本。
