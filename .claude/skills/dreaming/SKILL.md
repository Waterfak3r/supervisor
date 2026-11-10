---
name: dreaming
description: supervisor 专用。团队记忆（memory/ 目录）的日常维护：派 dreamer 整理记忆、读整理报告、提交记忆、把 proposals.md 里的提议转告用户；以及平时什么时候往 memory/inbox.md 记一笔。Stop hook 提示"该整理团队记忆了"、dreamer 完成、或用户问起记忆时加载。
---

# 团队记忆与 dreaming

团队记忆在 `D:\Programming\Project\supervisor\memory\`，规则见那里的 `README.md`。你在里面的职责有三件：

## 1. 平时：往 inbox 记一笔

遇到下面的情况，往 `memory\inbox.md` 末尾追加一行（`- 2026-11-10 [用户] 内容`），不用等整理：
- 用户表达了偏好或习惯（"以后简历都用中文""别用 Grok"）。
- 用户纠正了你或 worker 的做法。
- 用户做了一个以后还会用到的决定。
- 你验收时发现了某个项目或工具的坑，worker 的报告里却没写。

只记一句话，不写私人信息和密钥。用户明确说"帮我记一下某个想法或计划"的，那是待办，记进 `state\projects.md` 或台账，不是记忆。

## 2. 派 dreamer

Stop hook 会在该整理的时候提醒你（距上次超过 20 小时，期间派出过至少 3 个任务）。用户要求整理时也照做。

1. 读 `memory\.last-dream`，拿到上次处理到的任务编号 `upto`（文件不存在就是第一次）。
2. 在台账记一行，编号照常递增，类型写 `记忆整理`。
3. 派活，**工作目录固定是 memory 目录**：
   ```powershell
   & D:\Programming\Project\supervisor\tools\dispatch.ps1 -Name dream-<编号> -Cwd D:\Programming\Project\supervisor\memory -Command dreamer -Model sonnet -Effort high -Task '<编号> 记忆整理。范围：台账里 <upto 之后的编号> 到最新的任务（第一次整理就是全部）。报告写到 dreams\<编号>.md。'
   ```
   选档：sonnet / high。整理要判断真假、合并矛盾，不用 Gemini。
4. 确保后台监听在跑，结束这一轮。

## 3. dreamer 完成后

1. 读 `memory\dreams\<编号>.md`。看一眼删除和修改的条目理由是否站得住；明显删错的，自己改回来。
2. 提交记忆，只提交 memory 目录，**不 push**。这一步不需要问用户：
   ```powershell
   git -C D:\Programming\Project\supervisor add memory
   git -C D:\Programming\Project\supervisor commit -m '<编号> 记忆整理'
   ```
3. `memory\proposals.md` 里有新提议时，按 CLAUDE.md 第 7 节转告用户：每条写清改什么、为什么，挂 `sv.ask` 标签。用户同意的，派 worker 或自己落实（改 skill、template、CLAUDE.md 后在本仓库提交），然后从 proposals.md 删掉；用户拒绝的也删掉，并在 inbox 记一行"用户拒绝了……"，免得下次又被提出来。
4. 报告里的"存疑"项，能自己判断的直接处理，需要用户确认的一并问。
5. 关掉 dreamer：`hc kill dream-<编号>; hc rm dream-<编号>`。
6. 给用户 2~3 行汇报：新增几条、删了几条、有没有提议。

## 读记忆

- 每次会话开始（包括 `/clear` 之后），读 `memory\user.md`。
- 继续一个项目时，除了 PROGRESS.md，也读 `memory\projects\<项目目录名>.md`。
- worker 不用你操心：dispatch 会把 `general.md` 和对应项目的记忆文件路径附在任务说明末尾。
