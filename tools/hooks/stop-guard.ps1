# supervisor 的 Stop hook：supervisor 每次要结束回合时运行。按顺序检查两件事，第一件不满足就拦下：
#  1. 还有 worker 在 working，后台却没有 watch.ps1 在跑 → 拦下，让 supervisor 先把监听挂上。
#     否则 worker 做完了也不会有人叫醒它（2026-11-10 T025 就是这样漏掉的）。
#  2. 该整理团队记忆了（dreaming）：距离上次整理超过 20 小时，期间派出过至少 3 个任务，
#     而且今天还没提醒过 → 拦下，让 supervisor 派一个 dreamer。每 20 小时最多提醒一次，supervisor 不派也不会反复催。
#
# 只对 supervisor 本人生效：cwd 必须正好是 supervisor 仓库根目录（worker 一律不在根目录运行，dispatch 会拒绝）。
# stop_hook_active 为 true 时直接放行，避免反复拦截陷入循环。
# 任何意外都放行（exit 0），绝不因为 hook 自己出错把 supervisor 卡住。
$ErrorActionPreference = 'Stop'

function Block([string]$reason) {
    [pscustomobject]@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    exit 0
}

try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')

    $raw = [Console]::In.ReadToEnd()
    $in = $raw | ConvertFrom-Json
    if ($in.stop_hook_active) { exit 0 }
    if (-not $in.cwd) { exit 0 }
    if ([IO.Path]::GetFullPath($in.cwd).TrimEnd('\') -ne $root) { exit 0 }

    # 归 supervisor 管的 worker（-Detached 派出的测试 worker 除外）
    $workersDir = Join-Path $root 'state\workers'
    $metas = @()
    if (Test-Path $workersDir) {
        foreach ($f in Get-ChildItem $workersDir -Filter '*.json') {
            $m = $null
            try { $m = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json } catch { continue }
            if ($m.detached) { continue }
            $metas += $m
        }
    }
    function Get-Term($m) {
        $target = if ($m.machine -and $m.address) { $m.address } else { $m.name }
        try { return (& hc get $target --json 2>$null | Out-String | ConvertFrom-Json) } catch { return $null }
    }

    # ---- 1. 后台监听 ----
    $watcherAlive = $false
    $pidFile = Join-Path $root 'state\watch.pid'
    if (Test-Path $pidFile) {
        $p = 0
        if ([int]::TryParse((Get-Content $pidFile -Raw).Trim(), [ref]$p)) {
            $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -match '^(powershell|pwsh)$') { $watcherAlive = $true }
        }
    }
    $live = @{}
    foreach ($m in $metas) {
        $t = Get-Term $m
        if ($t -and $t.state -eq 'live') { $live[$m.name] = $t }
    }
    if (-not $watcherAlive) {
        $working = @($live.Keys | Where-Object { $live[$_].status.state -eq 'working' })
        if ($working.Count -gt 0) {
            Block ("还有 worker 在工作（$($working -join '、')），但后台没有监听在跑，它们做完时不会有人叫醒你。" +
                "请用 PowerShell 工具、run_in_background 设为 true，运行 & D:\Programming\Project\supervisor\tools\watch.ps1，然后再结束这一轮。" +
                "如果这些 worker 你已经不打算管了，就先 hc kill 并 hc rm 掉它们。")
        }
    }

    # ---- 2. 整理团队记忆 ----
    $lastAt = $null
    $lastFile = Join-Path $root 'memory\.last-dream'
    if (Test-Path $lastFile) {
        try { $lastAt = [datetime]((Get-Content $lastFile -Raw | ConvertFrom-Json).at) } catch {}
    }
    if ($lastAt -and ((Get-Date) - $lastAt).TotalHours -lt 20) { exit 0 }
    $reqFile = Join-Path $root 'state\dream-requested'
    if ((Test-Path $reqFile) -and ((Get-Date) - (Get-Item $reqFile).LastWriteTime).TotalHours -lt 20) { exit 0 }
    # 已经有 dreamer 在跑
    if (@($metas | Where-Object { $_.role -eq 'dreamer' -and $live.ContainsKey($_.name) }).Count -gt 0) { exit 0 }
    # 本机最多 3 个 worker
    if (@($live.Values | Where-Object { -not ($_.address -like '*/*') }).Count -ge 3) { exit 0 }
    $since = @($metas | Where-Object {
        $_.role -ne 'dreamer' -and (-not $lastAt -or ($_.created -and [datetime]$_.created -gt $lastAt))
    })
    if ($since.Count -lt 3) { exit 0 }

    Set-Content $reqFile (Get-Date).ToString('s') -Encoding ascii
    $when = if ($lastAt) { "上次整理是 $($lastAt.ToString('yyyy-MM-dd HH:mm'))" } else { '还从来没有整理过' }
    Block ("该整理团队记忆了：$when，之后派出过 $($since.Count) 个任务。" +
        "请加载 skill dreaming，按里面的步骤派一个 dreamer（派出后照常确保后台监听在跑），然后结束这一轮，不用等它。" +
        "如果现在不合适（比如正在处理用户的急事），就不派，直接结束；这个提醒 20 小时内不会再出现。")
} catch {
    exit 0
}
