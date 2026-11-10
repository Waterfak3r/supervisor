---
name: worktree
description: supervisor 专用。同一个项目要同时跑多个会写文件的 worker（几个 coder 并行做不同里程碑）时，用 dispatch -Worktree 给每个 worker 开独立的 git worktree 和分支，验收后用 worktree-finish.ps1 合并、处理冲突、清理。打算在同一项目里并行派第二个 coder 之前加载。
---

# 用 git worktree 让同一项目的多个 coder 并行

默认规则是"同一个项目目录同时只能有一个会写文件的 worker"。worktree 让每个 worker 在 `<项目>\.worktrees\<名字>` 里有自己的一份代码和分支 `sv/<名字>`，互不干扰，验收后再合并回项目。

## 什么时候用

- 值得用：两个以上的里程碑**改的文件基本不重叠**，而且都比较大（各自要跑十几分钟以上）。
- 不值得用：里程碑之间有依赖（B 要用 A 的成果）、改同一批文件、或者任务很小。这些照旧排队，一个做完再派下一个。
- 代价：worktree 里**只有 git 跟踪的文件**。依赖（`node_modules`、`venv`）和被 gitignore 的生成物（例如 birthday 的 `site\img\*.webp`）都没有，worker 要自己安装或重新生成，任务说明里要写清楚怎么做。项目主目录里**没提交的改动**在 worktree 里也看不到（dispatch 会提示）。
- 只支持本机项目，不支持 `-Machine`。

## 派活

```powershell
& D:\Programming\Project\supervisor\tools\dispatch.ps1 -Worktree -Name <项目>-coder-<编号> -Cwd <项目根目录> -Command coder -Model sonnet -Effort high -Task '...'
```

- `-Cwd` 填**项目根目录**，脚本自己开 worktree，worker 的工作目录就是 worktree。输出第一行会打印 worktree 路径和分支。
- 新分支从项目**当前分支**的 HEAD 开出。项目主目录有没提交的改动时，先想清楚 worker 需不需要它们；需要的话，先让人把它们提交了再派。
- `.worktrees/` 会被自动写进项目的 `.git/info/exclude`，不进版本库，也不改项目的 `.gitignore`。
- 任务说明里额外写上：「你在独立的 git worktree 里工作，做完后必须把改动 git commit 到当前分支（不要切换分支、不要 push、不要合并）。报告写到当前目录下的 .supervisor/reports/<编号>-coder.md，随代码一起提交。」再写清依赖怎么装、生成物怎么生成。
- 台账里注明 worktree 路径。

## 验收

- 报告在 **worktree** 里：`<项目>\.worktrees\<名字>\.supervisor\reports\<编号>-coder.md`。
- 验收命令在 worktree 里跑（`--cwd` 指向 worktree）。
- reviewer 也派到 worktree 路径（不加 `-Worktree`，直接把 worktree 路径当 `-Cwd`），只读审查。coder 的改动已经提交了，所以任务说明里要写明审查范围 `git diff <base_commit>..HEAD`，`base_commit` 在 `state\workers\<coder 名字>.json` 的 `worktree` 字段里。
- 同一个 worktree 里同时也只能有一个会写文件的 worker。

## 合并和清理

验收通过后：

1. `hc kill <名字>; hc rm <名字>`（Windows 上目录被占用就删不掉）。如果这个 worktree 还有 reviewer 终端，也一起关掉。
2. 先试合并，不动任何东西：
   ```powershell
   & D:\Programming\Project\supervisor\tools\worktree-finish.ps1 -Name <名字> -NoMerge
   ```
3. 正式合并并清理：
   ```powershell
   & D:\Programming\Project\supervisor\tools\worktree-finish.ps1 -Name <名字>
   ```
   脚本会做 `git merge --no-ff`（不 push），然后 `git worktree remove` 和 `git branch -d`。它不用任何 `--force`：worktree 有未提交的改动、项目主目录不在原来的分支上，都会拒绝；分支没合并，git 不让删。所以**这一步的清理不需要再问用户**，它只删除已经合并进项目的东西。
4. 合并后在**项目主目录**再跑一次验收命令，确认合在一起也没问题，再更新 PROGRESS.md 和台账。

**有冲突时**（退出码 5）：脚本已经 `git merge --abort`，项目主目录原样不动。用 `resume.ps1 -Name <名字>` 恢复这个 coder，让它在自己的 worktree 里 `git merge <主分支>`、解决冲突、跑验收、提交，然后再从第 1 步来一遍。冲突解决不了或者牵涉业务取舍，就找用户。

**不要了的 worktree**（任务取消、做砸了）：不要自己删，把 worktree 路径和分支名告诉用户，由用户决定（删除要先问用户）。
