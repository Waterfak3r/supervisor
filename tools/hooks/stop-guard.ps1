# supervisor 的 Stop hook：supervisor 每次要结束回合时运行。
# 如果还有 worker 在 working，后台却没有 watch.ps1 在跑，就拦下这次结束，让 supervisor 先把监听挂上。
# 否则 worker 做完了也不会有人叫醒它（2026-11-10 T025 就是这样漏掉的）。
#
# 只对 supervisor 本人生效：cwd 必须正好是 supervisor 仓库根目录（worker 一律不在根目录运行，dispatch 会拒绝）。
# stop_hook_active 为 true 时直接放行，避免反复拦截陷入循环。
# 任何意外都放行（exit 0），绝不因为 hook 自己出错把 supervisor 卡住。
$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')

    $raw = [Console]::In.ReadToEnd()
    $in = $raw | ConvertFrom-Json
    if ($in.stop_hook_active) { exit 0 }
    if (-not $in.cwd) { exit 0 }
    if ([IO.Path]::GetFullPath($in.cwd).TrimEnd('\') -ne $root) { exit 0 }

    # 后台监听还活着？
    $pidFile = Join-Path $root 'state\watch.pid'
    if (Test-Path $pidFile) {
        $p = 0
        if ([int]::TryParse((Get-Content $pidFile -Raw).Trim(), [ref]$p)) {
            $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -match '^(powershell|pwsh)$') { exit 0 }
        }
    }

    # 有没有 worker 还在 working？
    $workersDir = Join-Path $root 'state\workers'
    if (-not (Test-Path $workersDir)) { exit 0 }
    $working = @()
    foreach ($f in Get-ChildItem $workersDir -Filter '*.json') {
        $m = $null
        try { $m = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json } catch { continue }
        if ($m.detached) { continue }
        $target = if ($m.machine -and $m.address) { $m.address } else { $m.name }
        $t = $null
        try { $t = & hc get $target --json 2>$null | Out-String | ConvertFrom-Json } catch { continue }
        if ($t -and $t.state -eq 'live' -and $t.status.state -eq 'working') { $working += $m.name }
    }
    if ($working.Count -eq 0) { exit 0 }

    $reason = "还有 worker 在工作（$($working -join '、')），但后台没有监听在跑，它们做完时不会有人叫醒你。" +
        "请用 PowerShell 工具、run_in_background 设为 true，运行 & D:\Programming\Project\supervisor\tools\watch.ps1，然后再结束这一轮。" +
        "如果这些 worker 你已经不打算管了，就先 hc kill 并 hc rm 掉它们。"
    [pscustomobject]@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    exit 0
} catch {
    exit 0
}
