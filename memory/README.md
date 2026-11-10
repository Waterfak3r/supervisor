# 团队记忆

supervisor 和所有 worker 共用的长期记忆。对话会被 `/clear`、worker 做完就关，**只有写在这里的经验能留到下一次**。

## 怎么流动

1. **白天记录**：worker 在报告末尾写"经验"一节；supervisor 遇到用户表达偏好、纠正做法时，往 `inbox.md` 追加一行。
2. **定期整理（dreaming）**：一个 `dreamer` worker 读取上次整理以来的报告和 `inbox.md`，把经验合并进下面的主题文件，核对旧条目是否还成立，删掉过时的，并把"应该改成规则"的模式写进 `proposals.md`。由 supervisor 的 Stop hook 按天触发，做法见 skill `dreaming`。
3. **开工前读取**：dispatch 会在任务说明末尾附上相关的记忆文件路径，worker 开工前先读。

## 文件

| 文件 | 内容 | 谁读 |
|---|---|---|
| `user.md` | 用户的偏好、习惯、明确做过的决定（跨项目适用的） | supervisor 每次会话开始读 |
| `general.md` | 跨项目的环境和工具经验：Windows、PowerShell、hc、omp、git 的坑和可用写法 | 所有本机 worker |
| `projects/<项目目录名>.md` | 某个项目的经验：约定、坑、验收时要注意什么、常用命令 | 在这个项目里干活的 worker；supervisor 继续这个项目时 |
| `inbox.md` | 还没整理的原始记录，dreamer 整理后清空 | dreamer |
| `proposals.md` | dreamer 提议改成 skill、template 或 CLAUDE.md 规则的内容，等用户决定 | supervisor 转告用户 |
| `.last-dream` | 上次整理的时间和处理到的任务编号（dreamer 写） | Stop hook、dreamer |
| `dreams/<编号>.md` | 每次整理的报告：加了什么、改了什么、删了什么、为什么 | supervisor |

## 条目格式

一条一行，写**以后的人用得上、从代码和文件里看不出来**的东西：

```
- <经验，一句话，必要时带命令或路径>（来源 T025；核实 2026-11-10）
```

- "来源"写任务编号或"用户"；"核实"写最后一次确认它仍然成立的日期。
- 每个文件控制在 80 行以内。超了就合并相近的条目，删掉最不常用的。

## 不写什么

- 密钥、令牌、密码、账号，以及私人信息：私信或信件内容、证件号、联系方式、住址。
- 本次任务的流水账、代码里一眼就能看出来的东西、已经写进 CLAUDE.md 或 skill 的规则。
- 没有证据的猜测。
