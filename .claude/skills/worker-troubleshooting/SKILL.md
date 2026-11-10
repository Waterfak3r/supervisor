---
name: worker-troubleshooting
description: supervisor 专用。worker 出状况时的处理办法：dispatch 返回 first_message.sent/started 为 false（信任对话框、omp 更新说明吞掉首条消息）、worker 卡在 blocked（权限确认、git push 之类的 ask 规则）、限流（rate limit / Too many requests / Retrying）、需要恢复已关闭的 worker 会话。遇到这些情况时加载。
---

# worker 出状况时怎么办

## 首条消息没送达（`first_message.sent` 为 false）

先 `hc read <t> --lines 0` 看清情况，不要盲目重发。

**最常见的原因是首次进入某个目录时弹出的"信任此文件夹"对话框：**
- 只有当目录在 `D:\Programming\Project\` 下，或者是你按用户要求新建的目录时，才可以代为确认：Claude Code 用 `hc keys <t> down enter`，Codex 用 `hc keys <t> enter`。其他目录一律先问用户。
- 已信任项目里的子目录（包括 `-Worktree` 开出的 `<项目>\.worktrees\*`）不会再弹，实测过。
- 确认后 template 正文**没有**发出去，需要手动补发：
  `hc send <t> "先完整读取 D:\Programming\Project\supervisor\templates\<template>.md，frontmatter 之后的正文就是你的角色指令。然后执行任务：<原任务说明>"`

**omp worker** 启动时可能弹出更新说明之类的画面，把首条消息吞掉。如果 `first_message.started` 是 false：先 `hc wait <t>`，等到 idle 后 `turn` 仍是 0，就 `hc read` 确认输入框里没有任务、也没有回复，然后用 `hc send` 补发任务说明。

## worker 卡在 blocked

`blocked` 意味着需要人。`hc read <t> --lines 60` 读屏幕，把问题转述给用户（按 CLAUDE.md 第 7 节挂 `sv.ask` 标签），**绝不用 `--force` 绕过**，也不要替用户在权限框里选"是"。

- 屏幕上写着 `Ask rule ... overrides auto mode`：是 worker 想执行 `git push`、`git reset --hard`、`git clean` 之类被护栏拦下的命令（规则在 `tools\worker-settings.json`）。worker 本不该做这些。问清用户要不要做；不做就 `hc keys <t> escape`，再 `hc send` 告诉它不要做、接着干别的。
- 其他权限确认：看清它要做什么，判断在不在任务范围内，再转述给用户。

## 限流

worker 屏幕上出现 rate limit、Too many requests 或 Retrying 字样，说明被限流了。不要干等，直接 `hc kill` 加 `hc rm`，按 CLAUDE.md 4.5 换备选模型重新派活，并在 `state/routing-notes.md` 记一笔。

## 恢复已关闭的 worker

```powershell
& D:\Programming\Project\supervisor\tools\resume.ps1 -Name <名字>
```

然后 `hc wait <名字>`（很快就绪），再 `hc send <名字> '...'`。它会记得之前做过的所有事。
- 只用于同一模型继续干。升档时不要恢复旧会话，而是新开一个高一档的 worker，把旧报告路径交给它。
- 不支持远程 worker（见 skill remote-ops）。
