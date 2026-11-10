---
name: writing
description: supervisor 专用。派发文字类任务的完整流程：writer（Claude 起草）→ editor（Gemini 只润色）→ helper 意思一致性核对；含分级、选模型、文件约定和任务说明写法。凡是以文字为最终产出的任务（文档、README、报告、简历、求职信、邮件、申报材料、演示文稿文案、翻译、摘要）或用户要求"润色"时，派活前先加载。
---

# 文字类任务：Claude 写内容，Gemini 只润色

用户的判断：**Gemini 的文字表达最好，但逻辑不行**。所以按擅长的分工：
- 内容、逻辑、结构、事实取舍由 Claude 负责：`writer` 起草。
- 句子层面的表达交给 Gemini：`editor` 只润色，不动内容。

核心是：Claude 定内容，Gemini 管语言，最后检查语言有没有把内容改坏。

## 分级

| 级别 | 什么文字 | 流程 |
|---|---|---|
| A 内部、短小 | 笔记、commit message、worker 的工作报告、你给用户的汇报 | 谁做的事谁写，不转手 |
| B 一般文字 | README、文档、报告、普通邮件 | `writer` 起草 → `editor` 润色 |
| C 对外的重要材料 | 简历、求职信、申报书、给老师或面试官的正式邮件 | `writer` 起草 → `editor` 润色 → `helper` 做意思一致性核对 |

## 模型

| 角色 | B 级 | C 级 |
|---|---|---|
| `writer`（Claude） | `sonnet` / `medium` | `sonnet` / `high`；逻辑特别复杂的申报书用 `opus` / `high` |
| `editor`（Gemini） | `google-antigravity/gemini-3.8-flash` / `medium` | 同一个模型，`high` |
| 核对（`helper`） | — | `sonnet` / `medium` |

- **事实不清楚时**，先让 `coder`、`helper` 或 `planner` 整理出事实要点（比如项目 README 要先弄清代码实际做了什么），再交给 writer。writer 和 editor 都不自己去读代码、推断事实。
- writer 报告里的【待补充】项，汇报时列给用户；需要用户决定的，按 CLAUDE.md 第 7 节挂 `sv.ask` 标签问。
- 文字流程**一律在本机做**。服务器上没有登录 Claude，跑不了 writer。
- 用户点名要用别的模型或流程时，照办。

## 文件约定

所有文件都放在同一个工作目录里：
- 杂项任务用 `state\work\<编号>\`；
- 项目文档放在项目里该放的位置，过程文件放 `<项目>\.supervisor\writing\<编号>\`。

| 文件 | 谁写 | 内容 |
|---|---|---|
| `material.md` | supervisor | 素材：用户给的原文、事实要点、读者和用途、格式要求。用户的原话尽量原样贴进去 |
| `<名称>.draft.md` | writer | 初稿 |
| `<名称>.md` | editor | 润色稿，也就是最终稿 |
| `report-writer.md`、`report-editor.md`、`report-check.md` | 各自的 worker | 报告 |

## B 级：起草 → 润色

每一步派出后照常结束回合，等后台监听叫醒你再做下一步。

1. 把素材写进 `material.md`。
2. 派 writer：
   ```powershell
   & D:\Programming\Project\supervisor\tools\dispatch.ps1 -Name <编号>-writer -Cwd <工作目录> -Command writer -Model sonnet -Effort medium -Task '读 material.md，为<读者>写<什么>，<格式要求>。初稿写到 <名称>.draft.md，报告写到 report-writer.md。'
   ```
3. 读 writer 的报告，确认结构合理、【待补充】项清楚。有问题就 `hc send` 让它改，改完再往下走。
4. 派 editor：
   ```powershell
   & D:\Programming\Project\supervisor\tools\dispatch.ps1 -Name <编号>-editor -Cwd <工作目录> -Command editor -Model google-antigravity/gemini-3.8-flash -Effort medium -Task '润色 <名称>.draft.md，读者和必须保留的措辞见 report-writer.md。润色稿写到 <名称>.md，不要覆盖初稿；报告写到 report-editor.md。'
   ```
5. 读 editor 报告里的"疑点"。确实有问题的，交回 writer 修改，然后重新润色；没问题的，忽略即可。
6. 汇报给用户：最终稿路径、【待补充】项、疑点的处理结果。然后关掉 worker。

## C 级：再加一步意思一致性核对

在 B 级的第 6 步之前，加一步核对：

```powershell
& D:\Programming\Project\supervisor\tools\dispatch.ps1 -Name <编号>-check -Cwd <工作目录> -Command helper -Model sonnet -Effort medium -Task '意思一致性核对：逐句对比 <名称>.draft.md（初稿）和 <名称>.md（润色稿），对照 material.md 的素材。只找这几类问题：1) 意思变了；2) 说法被加强或减弱（例如「参加过」变成「具备经验」），或者限定词丢了；3) 加了初稿没有的内容，或删了初稿的内容；4) 事实、数字、名称和素材不符。不评价文风，不改任何文件。报告写到 report-check.md：第一行写「通过」或「有 N 处问题」，然后每处列出 初稿原句 / 润色后 / 问题 / 建议。'
```

核对有问题时：
- 只是个别措辞被改强了，或者丢了限定词：直接把这几处的初稿说法告诉 editor，`hc send` 让它改回去。改完不用再核对一遍，你自己对照一下那几处就行。
- 问题很多，或者意思改得面目全非：说明这次润色失控了。直接用初稿，或者用 `resume.ps1` 恢复 editor 的会话，让它在"只做最小改动"的前提下重新润色一遍。

## 只润色现成文字

用户直接给了一段文字，只要求润色：
1. 把原文存为 `<名称>.draft.md`，读者和用途写进 `material.md`。
2. 从 B 级的第 4 步开始。任务说明里没有 writer 报告，就在 `material.md` 里写清楚哪些措辞必须保留。
3. 如果是 C 级材料，照样做核对。

## 校准

如果发现某类文字用这套流程效果不好（润色反复失控、核对总是有问题，或者用户觉得 Claude 的初稿已经够好、润色是多余的），记到 `state/routing-notes.md`，攒够 3 条再提议调整流程。
