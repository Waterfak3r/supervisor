# 跨项目的环境和工具经验

只记 CLAUDE.md 和 skill 里没有的。跨机派活、服务器 PATH、hc 的 BOM 问题见 skill `remote-ops`，worker 卡住见 `worker-troubleshooting`。

## Windows / PowerShell 5.1
- 脚本里有中文，`.ps1` 必须存成 UTF-8 **带 BOM**，否则 5.1 按 ANSI 读会乱码。`tools\` 下现有 5 个脚本（dispatch、common、resume、sync-templates、watch）都是带 BOM 的，新脚本照做（T008；核实 2026-11-10，前 3 字节 239,187,191）
- 多行提交说明：PowerShell 工具里用单引号 here-string `git commit -m @'…'@`（结尾 `'@` 顶格）可以正常提交（2026-11-10 实测两次）。T009 曾报过一次被拆成多个参数、出现 pathspec 错误，原因不明，可能和写法有关；如果又遇到，就把说明写进文件，再用 `git commit -F <文件>`（T009；核实 2026-11-10）
- 本机 PATH 里 Git 自带的 `tar`、`scp`（`D:\Programming\Git\usr\bin`）排在系统自带之前，会把 `C:\...` 当成远程主机名。打包或 scp 时先 cd 到暂存目录，用相对文件名（T013；核实 2026-11-10，`where.exe` 顺序仍是 Git 在前）
- 本机 git 没有全局 `user.name` / `user.email`。新仓库首次提交会失败，用一次性的 `git -c user.name=… -c user.email=… commit`，不要写进配置（T009；核实 2026-11-10）
- Edge 无头的 `--window-size` 最小约 500 px，390 宽截图会被裁、看起来内容偏右，这不是页面 bug。测手机宽度用 Playwright viewport 或 CDP `Emulation.setDeviceMetricsOverride`（T011、T012；核实 2026-11-09）
- 本机 DNS 被代理接管，域名解析成 198.18.x.x，本机 `curl` 域名的结果不可信。上线验收用 `hc exec --on tc-62 -- curl …` 或用户真机（birthday PROGRESS；核实 2026-11-10，`Resolve-DnsName yyxcxc.wonderfaker.online` → 198.18.0.216）

## omp / ssh
- `omp update` 偶发 `ECONNRESET`，原样重试一次就成功了（T002 失败，T003 成功 → 18.18.1）。用完整路径 `C:\Users\Waterfaker\AppData\Local\omp\omp.exe update`；已在跑的 omp 进程要重启才换新版；更新后目录里会留一个约 200 MB 的 `.bak`（T003；核实 2026-11-10，本机 omp/18.18.1）
- 连服务器一律用别名 `ssh tc-62`。直接写 `ubuntu@<IP>` 读不到 config 里的 IdentityFile，会 `Permission denied (publickey,password)`（T004、T005；核实 2026-11-10，`~/.ssh/config` 有 `Host tc-62`）

## 服务器 tc-62
- 网站用 **Caddy** 托管（`/etc/caddy/Caddyfile`，一个域名一个站点块，自动 HTTPS），nginx 是 inactive。改配置前先备份成 `Caddyfile.bak.<时间戳>`，`caddy validate` 通过再 reload（birthday PROGRESS 2026-11-09；核实 2026-11-10，`systemctl is-active` → caddy active、nginx inactive）
- 本机 supervisor 用 `hc exec --on tc-62 -- …` 做只读预检即可，不需要另外 ssh（birthday PROGRESS；核实 2026-11-10）

## 权限分类器与 worker 行为
- 分类器拦截过：写服务器 `~/.profile`（Unauthorized Persistence）、改 CLAUDE.md（Self-Modification）、关别人的 herdr pane（Interfere With Workloads）、auto 模式下 supervisor 执行 `deploy.ps1 -Execute`。做对的处理：不绕，把命令写进报告，等用户（T007、T009、birthday M8；核实 2026-11-10）

## supervisor 自己的习惯
- 向用户报告「素材有错」之前，先逐字核对一遍。藏头诗被 supervisor 误判成对不上，其实前 10 行取首字母、第 11、12 行取整词，白让用户操了一次心（birthday PROGRESS 2026-11-09 更正；核实 2026-11-10）
