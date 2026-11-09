# 启动（或重新连接）supervisor，并让它显示在 Herdr App 的 Supervisor 空间里。
# 用法：在任意终端运行 .\start-supervisor.ps1；也可以直接在 Herdr App 里点开 Supervisor 空间的 supervisor 标签页。
# 用 hc attach 连接时，Ctrl+\ 断开，supervisor 会继续在后台运行。
param([switch]$NoAttach)
$root = $PSScriptRoot

function Get-SupervisorSpace {
    try {
        $ls = herdr-app ls 2>$null | Out-String | ConvertFrom-Json
        # 只找本机的：远程机器上也有同名的 Supervisor 空间（放远程 worker 用）
        return ($ls.spaces | Where-Object { $_.name -eq 'Supervisor' -and -not $_.machine } | Select-Object -First 1)
    } catch { return $null }
}

# Herdr 窗口开着但还没有 Supervisor 空间时，先建一个
$space = Get-SupervisorSpace
if (-not $space) {
    herdr-app do space.new --name Supervisor --folder $root --tab shell *> $null
    $space = Get-SupervisorSpace
}

$claudeCmd = 'claude --model sonnet --permission-mode auto'

# 注意：hc get 对已结束的同名终端也会成功返回，所以必须检查 state
$cur = $null
try { $cur = hc get supervisor --json 2>$null | Out-String | ConvertFrom-Json } catch {}
if (-not $cur -or $cur.state -ne 'live') {
    # 情况 1：没有 supervisor，新建一个。
    # --no-parent：不要绑定在启动它的这个终端上，否则关掉这个终端，supervisor 和所有 worker 都会结束
    hc run --bg --no-parent --name supervisor --cwd $root --label role=supervisor claude --model sonnet --permission-mode auto | Out-Null
} elseif (-not $cur.status -and $cur.foreground.name -match '^(powershell|pwsh|cmd|bash|sh)(\.exe)?$') {
    # 情况 2：电脑重启后，Herdr 会把终端恢复成同一地址的 shell，claude 不会自己回来。在这个 shell 里重新启动它。
    hc send supervisor "cd '$root'; $claudeCmd" | Out-Null
}
# 情况 3：claude 正在运行，什么都不做。

if ($space) {
    hc label supervisor "herdr.space=$($space.id)" | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
        $s = Get-SupervisorSpace
        $tab = $s.tabs | Where-Object { $_.terminals.terminal -contains (hc get supervisor --json | ConvertFrom-Json).address } | Select-Object -First 1
        if ($tab) { herdr-app do tab.rename --id $tab.id --name supervisor *> $null; break }
        Start-Sleep -Milliseconds 300
    }
}

if (-not $NoAttach) { hc attach supervisor }
