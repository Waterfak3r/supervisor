# 验收通过后，把 worker 的 worktree 分支合并回项目，并清理 worktree。
# 用法：
#   & D:\Programming\Project\supervisor\tools\worktree-finish.ps1 -Name <worker 名>            # 合并并清理
#   & D:\Programming\Project\supervisor\tools\worktree-finish.ps1 -Name <worker 名> -NoMerge   # 只检查能否合并，不动任何东西
#
# 安全约束（全部依赖 git 自己的检查，脚本不用任何 --force）：
#  - worktree 里有未提交的改动 → 拒绝（先让 worker 提交）；
#  - 项目主目录当前分支不是开 worktree 时的那个分支 → 拒绝；
#  - 合并冲突 → 自动 git merge --abort，列出冲突文件，什么都不清理；
#  - 清理用 git worktree remove（目录有改动时 git 会拒绝）和 git branch -d（没合并的分支 git 会拒绝）。
# 不 push。worker 终端请先 hc kill + hc rm（worktree 目录被占用时 Windows 上删不掉）。
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$NoMerge
)

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$metaFile = Join-Path $root "state\workers\$Name.json"
if (-not (Test-Path $metaFile)) { Write-Error "找不到 worker 元数据：$metaFile"; exit 2 }
$meta = Get-Content $metaFile -Raw -Encoding utf8 | ConvertFrom-Json
$wt = $meta.worktree
if (-not $wt) { Write-Error "$Name 不是用 -Worktree 派出的 worker"; exit 2 }
$repo = $wt.repo; $path = $wt.path; $branch = $wt.branch; $base = $wt.base

function Invoke-Git([string[]]$a) { & git.exe @a 2>&1 | ForEach-Object { "$_" } }

# worker 终端还活着？
$t = $null
try { $t = hc get $Name --json 2>$null | Out-String | ConvertFrom-Json } catch {}
if ($t -and $t.state -eq 'live' -and -not $NoMerge) { Write-Error "worker 终端 $Name 还在运行。先 hc kill $Name; hc rm $Name，再来合并（返工的话就别合并）。"; exit 3 }

if (-not (Test-Path $path)) { Write-Error "worktree 目录不存在：$path"; exit 2 }
$dirty = (Invoke-Git @('-C', $path, 'status', '--porcelain')) -join "`n"
if ($dirty.Trim()) { Write-Error "worktree 里还有未提交的改动，先让 worker 提交（或确认不要后再处理）：`n$dirty"; exit 4 }

$cur = ((Invoke-Git @('-C', $repo, 'branch', '--show-current')) -join '').Trim()
if ($cur -ne $base) { Write-Error "项目主目录当前在分支 $cur，不是开 worktree 时的 $base。请先确认主目录的状态。"; exit 4 }

$ahead = ((Invoke-Git @('-C', $repo, 'rev-list', '--count', "$base..$branch")) -join '').Trim()
$behind = ((Invoke-Git @('-C', $repo, 'rev-list', '--count', "$branch..$base")) -join '').Trim()
"分支 $branch：比 $base 多 $ahead 个提交；$base 在它开出之后又多了 $behind 个提交。"
if ($ahead -eq '0') { "worker 没有提交任何东西。" }

if ($NoMerge) {
    $probe = Invoke-Git @('-C', $repo, 'merge-tree', '--write-tree', '--name-only', $base, $branch)
    if ($LASTEXITCODE -eq 0) { "试合并：没有冲突。" } else { "试合并：有冲突：`n$($probe | Select-Object -Skip 1 | Where-Object { $_ } | Out-String)" }
    exit 0
}

if ($ahead -ne '0') {
    $out = Invoke-Git @('-C', $repo, 'merge', '--no-ff', '--no-edit', '-m', "合并 $branch（$Name）", $branch)
    if ($LASTEXITCODE -ne 0) {
        $conflicts = Invoke-Git @('-C', $repo, 'diff', '--name-only', '--diff-filter=U')
        Invoke-Git @('-C', $repo, 'merge', '--abort') | Out-Null
        Write-Error ("合并失败，已 git merge --abort，主目录恢复原样。`n" + ($out -join "`n") + "`n冲突文件：" + ($conflicts -join ', ') +
            "`n处理办法：resume 这个 worker，让它在自己的 worktree 里先 git merge $base 解决冲突并提交，再来合并。")
        exit 5
    }
    $out
}

$rm = Invoke-Git @('-C', $repo, 'worktree', 'remove', $path)
if ($LASTEXITCODE -ne 0) { Write-Error "合并已完成，但清理 worktree 失败：$($rm -join ' ')"; exit 6 }
$bd = Invoke-Git @('-C', $repo, 'branch', '-d', $branch)
if ($LASTEXITCODE -ne 0) { Write-Error "合并已完成、worktree 已删，但删除分支失败：$($bd -join ' ')"; exit 6 }
$wtRoot = Join-Path $repo '.worktrees'
if ((Test-Path $wtRoot) -and -not (Get-ChildItem $wtRoot -Force)) { Remove-Item $wtRoot }
"已合并到 $base，worktree 和分支 $branch 已清理。最新提交：$((Invoke-Git @('-C', $repo, 'log', '-1', '--oneline')) -join '')"
