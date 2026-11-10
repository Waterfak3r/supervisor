# Supervisor

基于 herdr-core（`hc`）和 Herdr App 的个人多智能体调度：所有任务交给 supervisor，由它分派给 worker、验收、收尾，并把反复出现的经验沉淀成 template 或 skill。

## 使用

**打开 Herdr 就能用。** 底部的 Supervisor 状态栏（一个 mod）会在 Herdr 启动时检查 supervisor；没有在运行就自动启动它。之后：

- 左侧选 **Supervisor 空间 → supervisor 标签页**，直接和它说话，比如"新项目：……需求……"或"继续 X"。
- 它派出的每个 worker 都会在 Supervisor 空间里开一个标签页（名字就是终端名）。在标签页里能看到 worker 的实时画面，也可以直接接管。
- 底部状态栏显示 supervisor 和各个 worker 的状态，"等你处理"的排在最前面，点一下就跳过去。左侧 Agents 列表也能看到这些状态；有 worker 卡住时 Herdr 会发出声音并弹出提醒。
- 如果你手动退出了 supervisor，状态栏会显示"未运行"和一个"启动"按钮。
- **看板视图**：按 `Ctrl+Shift+L` 在布局之间切换，切到 `board` 就是看板。看板按"等你处理 / 工作中 / 完成 / 空闲"四列展示所有 agent 的卡片；点一张卡片，下方的 Live workspace 会实时显示它的终端，可以直接在里面输入。卡片上的"在标签页中打开"会切回工作区布局，并聚焦到这个终端。

上下文太长时在 supervisor 里执行 `/clear`。**不要关掉 supervisor 的标签页或退出它**，它派出去的 worker 是它的子终端，会跟着一起结束。关闭 Herdr 窗口没关系，终端会在后台继续运行。

不用 Herdr 时也可以运行 `start-supervisor.ps1`，在终端里通过 `hc attach` 连接；按 Ctrl+\ 断开。

## 结构

| 路径 | 内容 |
|---|---|
| `CLAUDE.md` | supervisor 的工作规则 |
| `templates/` | worker 角色（planner / coder / reviewer）。已通过目录链接挂到 `%APPDATA%\herdr-core\templates`，这是 Windows 上 hc 读取 template 的位置 |
| `tools/dispatch.ps1` | 派活脚本：启动 worker，并把它放进 Herdr 的 Supervisor 空间 |
| `start-supervisor.ps1` | 启动或连接 supervisor（会自动建好 Supervisor 空间）。mod 和手动启动用的都是它 |
| `herdr-mod/` | Herdr 相关文件的备份：`supervisor/`（状态栏 mod；其中 `attention.js` + `taskbar-flash.cs` 负责有事等你时让任务栏按钮常亮，exe 首次使用时自动编译到 `%LOCALAPPDATA%\herdr-taskbar-flash\`）、`agent-board/`（看板 mod）、`layouts/`（`supervisor.json`、`board.json`）、`app/`（`settings.json`（含 `taskbar_highlight` 开关）、`programs.json`、`my-icons/`）、`herdr-tui/config.toml`（旧版 herdr 终端版配置）。安装位置分别是 `~\.config\herdr-app\mods\<名称>`、`~\.config\herdr-app\layouts\`、`~\.config\herdr-app\`、`%APPDATA%\herdr\`，复制过去即可 |
| `.claude/skills/` | supervisor 按需加载的做事方法：`writing`（文字流程）、`remote-ops`（服务器）、`worker-troubleshooting`（worker 出状况）、`worktree`（同项目并行）。以后沉淀的经验也写成 skill |
| `.claude/settings.json` | supervisor 的程序化护栏：`git push` 等危险命令必须确认；Stop hook（`tools/hooks/stop-guard.ps1`）在还有 worker 在跑却没挂后台监听时，拦下 supervisor 结束回合；到了该整理记忆的时候（距上次超过 20 小时、期间派过 3 个以上任务），提醒它派 dreamer |
| `memory/` | 团队记忆：worker 报告里的"经验"和 supervisor 的记录，由 `dreamer` 定期整理（dreaming）成用户偏好、通用经验、各项目经验；dispatch 会把相关文件附给 worker。规则见 `memory/README.md` |
| `tools/watch.ps1` | 后台监听：worker 完成、卡住或出错时唤醒 supervisor |
| `tools/worker-settings.json` | worker 的护栏（dispatch 用 `--settings` 传给 claude worker） |
| `tools/worktree-finish.ps1` | 把 `-Worktree` 派出的 worker 分支合并回项目并清理 |
| `state/` | 台账和项目登记（不纳入 git） |
| `<项目>/.supervisor/` | 每个项目自己的 SPEC、PLAN、PROGRESS 和 worker 报告 |

## 环境依赖

- hc 的 template 用 `sh` 执行 `command`，所以 `D:\Programming\Git\bin` 必须在用户 PATH 里。
- template 目录链接丢失时重建：`New-Item -ItemType Junction -Path "$env:APPDATA\herdr-core\templates" -Target "D:\Programming\Project\supervisor\templates"`
- 修改 mod 后，把它复制到安装位置，然后运行 `herdr-app check ~\.config\herdr-app\mods\supervisor` 检查。
- 状态栏放在布局 `supervisor` 里。它是复制默认布局 `main` 得到的，因为 Herdr 自带的布局是只读的。副本不会跟着 Herdr 更新；想回到默认布局，按 `Ctrl+Shift+L` 切换即可，但那里没有状态栏，也就不会自动启动 supervisor。
- 电脑重启后，Herdr 会把 supervisor 终端恢复成同一地址下的一个空 shell，claude 不会自己回来。`start-supervisor.ps1`（也就是状态栏自动调用的那个脚本）会识别这种情况，在这个 shell 里重新启动 claude。
- reviewer 暂时用的是 claude。codex 的默认模型 `gpt-6.1-sol` 通过 CC Switch 调用时会被拒绝（ChatGPT 账号不支持这个模型）。修好之后可以把 `templates/reviewer.md` 的 command 改回 `codex --no-daemon -m <可用模型> -s workspace-write -a on-request`。注意 codex 在 hc 里必须带 `--no-daemon`。
