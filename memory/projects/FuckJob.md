# FuckJob（开源求职自动化，Tauri2）

目前只有 planner 的 SPEC/PLAN（T024），源码零改动，M1 还没开始。以下是调研结论，依据是 planner 当时读的代码和文档，除注明外没有实测。

- FuckJob 已原生支持 Anthropic（按 provider 原生调用，有降级链，API Key 按服务分开存），所有 AI 任务共用一个模型，不能按任务分模型（T024，读源码 `src-tauri/src/llm/service.rs`、`config.rs`；未实测）
- Claude 订阅登录或 OAuth 令牌不能给第三方应用当通用 API，官方合规页写明不允许。程序调用要用 Console API Key 或云厂商。用户本人在 Claude Code 里交互使用订阅是允许的（T024，引自 Anthropic 官方文档，未逐条核对原文）
- Resume Matcher（srbhr/Resume-Matcher v1.4.0）的 ATS 匹配分是纯代码、零 token，但按词项重叠计算，**中文 JD 可能失真**。M1 的主要目的就是验证这一点（T024，未验证）
- 本机有 Python 3.14、uv、Node 24.14.1，**没有 Docker、Rust、Ollama**。RM 推荐 Node 24.22.1，发布说明说 22+ 即可（T024，未核实；D:\Programming\Project\Resume-Matcher 目录已存在，核实 2026-11-10）
- 招聘平台风控：51job 自动过滑块风险最高，规划里建议不用；各平台协议原文没有逐条核实（T024）
