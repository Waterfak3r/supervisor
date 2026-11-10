# 后台监听 worker：任意一个 worker 有了需要处理的变化，就结束并打印所有 worker 的状态。
# supervisor 用 Claude Code 的后台任务运行它（run_in_background），所以不会占着回合；
# 它一结束，Claude Code 就会唤醒 supervisor。整个过程不往 supervisor 的输入框里打字。
#
# 用法（supervisor 在 PowerShell 工具里，run_in_background 设为 true）：
#   & D:\Programming\Project\supervisor\tools\watch.ps1
#
# 会触发返回的变化：从 working 变成别的状态（完成、空闲）、变成 blocked 或 error、终端结束了。
# 和"上一次 watch 结束时告诉你的状态"比：那之后才停下的 worker，新 watch 一启动就立即报告；
# 你上次已经看到是 done/idle、还没关的 worker 不会反复叫醒你，除非它又开始工作、然后再停下。
# 监听对象：state\workers 里有记录、而且终端还活着的 worker（本机和远程都算）。
param(
    [int]$TimeoutSec = 3600,
    [int]$IntervalSec = 15
)

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workersDir = Join-Path $root 'state\workers'

function Get-Watched {
    $list = @()
    if (-not (Test-Path $workersDir)) { return $list }
    foreach ($f in Get-ChildItem $workersDir -Filter '*.json') {
        try { $m = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json } catch { continue }
        # 远程 worker 用地址查（名字只在它那台机器上唯一），本机用名字
        $target = if ($m.machine -and $m.address) { $m.address } else { $m.name }
        $t = $null
        try { $t = hc get $target --json 2>$null | Out-String | ConvertFrom-Json } catch {}
        if (-not $t) { continue }
        $status = if ($t.state -ne 'live') { 'finished' } elseif ($t.status.state) { $t.status.state } else { 'unknown' }
        $list += [pscustomobject]@{ name = $m.name; address = $t.address; machine = $m.machine; status = $status; cwd = $m.cwd }
    }
    return $list
}

function Show($list) {
    $list | ForEach-Object {
        $where = if ($_.machine) { "[$($_.machine)] " } else { '' }
        "  {0,-28} {1,-12} {2,-9} {3}{4}" -f $_.name, $_.address, $_.status, $where, $_.cwd
    }
}

# 基线 = supervisor 上一次从 watch.ps1 看到的状态（存在 state\watch-seen.json），而不是"本次启动时的状态"。
# 否则会漏掉这种情况：上一个 watch 结束后，supervisor 处理别的事花了几十秒，某个 worker 恰好在这期间完成；
# 新 watch 启动时它已经是 done，按"启动时已是 done 不算"就永远不会报（2026-11-10 T025 就是这样漏掉的）。
$seenFile = Join-Path $root 'state\watch-seen.json'
$seen = @{}
if (Test-Path $seenFile) {
    try {
        $obj = Get-Content $seenFile -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $seen[$p.Name] = [string]$p.Value }
    } catch {}
}
function Save-Seen($list) {
    $map = [ordered]@{}
    foreach ($w in $list) { $map[$w.address] = $w.status }
    try { [pscustomobject]$map | ConvertTo-Json | Set-Content $seenFile -Encoding utf8 } catch {}
}

# 需要 supervisor 处理的变化
function Test-Notable($before, $after) {
    if ($before -eq $after) { return $false }
    return ($after -in @('blocked', 'error', 'finished')) -or ($before -eq 'working' -and $after -in @('done', 'idle', 'unknown'))
}

function Report($changed, $now) {
    "== 有 worker 需要处理 =="
    Show $changed
    ""
    "== 全部 worker 当前状态 =="
    Show $now
    ""
    "处理完之后，如果还有 worker 在 working，就再在后台启动一次 watch.ps1。"
    Save-Seen $now
}

$base = @{}
$start = Get-Watched
$changed = @()
foreach ($w in $start) {
    if ($seen.ContainsKey($w.address)) {
        $before = $seen[$w.address]
    } elseif ($w.status -in @('done', 'idle')) {
        # supervisor 还没通过 watch 见过的新 worker，如果已经停下，就当作刚从 working 停下（派出后很快就做完的情况）。
        # 例外：turn 为 0 说明还没开始干活（比如卡在信任对话框之前），不算。
        $t = $null
        try { $t = hc get $w.address --json 2>$null | Out-String | ConvertFrom-Json } catch {}
        $before = if ($t -and $t.turn -ge 1) { 'working' } else { $w.status }
    } else {
        $before = $w.status
    }
    if (Test-Notable $before $w.status) { $changed += $w }
    $base[$w.address] = $w.status
}
if ($changed) {
    Report $changed $start
    exit 0
}
if (-not ($start | Where-Object { $_.status -ne 'finished' })) {
    "没有正在运行的 worker，不需要监听。"
    Save-Seen $start
    exit 0
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $IntervalSec
    $now = Get-Watched
    $changed = @()
    foreach ($w in $now) {
        $before = $base[$w.address]
        if ($before -eq $w.status) { continue }
        $base[$w.address] = $w.status
        if (Test-Notable $before $w.status) { $changed += $w }
    }
    if ($changed) {
        Report $changed $now
        exit 0
    }
}
$now = Get-Watched
"== 监听超时（${TimeoutSec} 秒），期间没有变化 =="
Show $now
"如果还有 worker 在 working，就再在后台启动一次 watch.ps1。"
Save-Seen $now
