# 派出一个 worker，并让它显示在 Herdr App 的 Supervisor 空间里（标签页名 = 终端名）。
# 用法：
#   & D:\Programming\Project\supervisor\tools\dispatch.ps1 -Name demo-coder-T003 -Cwd D:\Programming\Project\demo `
#       -Command coder -Model sonnet -Effort medium -Task '任务说明'
# -Command：template 名（planner/coder/reviewer/helper…），也可以直接填程序名（不推荐）。
# -Model / -Effort：模型和思考强度。带 provider/ 前缀的模型（如 xai-oauth/grok-4.7）用 omp 启动，
#   其余（haiku/sonnet/opus）用 claude。不填就用 template 自己写的设置。
# -Detached：不把调用方当作父终端，也不往父终端发通知（测试或手动派活时用）。
#
# 每个 worker 的会话都会被固定下来（claude 用 --session-id，omp 用独立的 --session-dir），
# 元数据写在 state\workers\<Name>.json。worker 关掉之后，可以用 tools\resume.ps1 -Name <Name> 恢复原会话。
# 输出 hc run 的 JSON 结果（address、first_message 等）。
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Cwd,
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$Task,
    [string]$Model,
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')][string]$Effort,
    [switch]$Detached,
    [string]$Machine
)

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$templateDir = Join-Path $root 'templates'
$workersDir = Join-Path $root 'state\workers'
$utf8 = New-Object Text.UTF8Encoding $false
. (Join-Path $PSScriptRoot 'common.ps1')

# ================= 跨机派活：-Machine tc-62 =================
# 在远程机器上用 hc run --on 启动 worker。限制和做法（详见 state\drafts\CLAUDE-cross-machine.md）：
#  - -Cwd 是该机器上的 Linux 绝对路径，本机不检查；
#  - 只允许 omp 类模型（带 provider/ 前缀）；服务器没有登录 claude；
#  - 同一台机器上同时只允许 1 个 worker；
#  - template 由服务器的 hc core 解析：这里按本机 templates\<Command>.md 生成一次性的 sv-<Command>--… 变体，
#    写到服务器的 template 目录，hc run 之后删除（只删自己写的这一个文件）；
#  - 在该机器上的 Supervisor 空间里开标签页（没有就自动建）。Herdr 只显示挂在同一台机器的空间里的终端，
#    作为本机 supervisor 的子终端是看不到的；
#  - worker 必须由 supervisor 终端直接派出（parent 是 supervisor），服务器上的 worker 只能回报给它的 parent。
if ($Machine) {
    function Stop-Remote([string]$msg, [int]$code = 2) { Write-Error $msg; exit $code }

    $rp = Get-RemoteProfile $Machine
    if (-not $rp) { Stop-Remote "未登记的机器：$Machine。已登记：$(($script:RemoteProfiles.Keys) -join ', ')（在 tools\common.ps1 的 RemoteProfiles 里加）" }
    if (-not $Model) { Stop-Remote "-Machine 时必须指定 -Model（带 provider/ 前缀的 omp 模型，例如 google-antigravity/gemini-3.8-flash）" }
    if ($Model -notmatch '/' -or (Get-Launcher $Model) -ne 'omp') {
        Stop-Remote "服务器 $Machine 上没有登录 Claude，-Machine 时不能用 Claude 模型（$Model）。请用带 provider/ 前缀的 omp 模型，例如 google-antigravity/gemini-3.8-flash 或 xai-oauth/grok-4.7"
    }
    if ($Name -notmatch '^[a-z0-9_-]{1,32}$') { Stop-Remote "-Name 只能是 1-32 位的 a-z 0-9 - _：$Name" }
    if ($Cwd -notmatch '^/[A-Za-z0-9_./-]*$') { Stop-Remote "-Machine 时 -Cwd 必须是 $Machine 上的 Linux 绝对路径（只含字母数字 _ . / -）：$Cwd" }
    if ($Cwd.TrimEnd('/') -eq '' -or $Cwd.TrimEnd('/') -eq $rp.Home) { Stop-Remote "不要把服务器主目录或根目录当工作目录，请用 $($rp.Home)/work/<名字> 或 /tmp/<名字>" }
    $templateFile = Join-Path $templateDir "$Command.md"
    if ($Command -notmatch '^[A-Za-z0-9_-]+$' -or -not (Test-Path $templateFile)) {
        Stop-Remote "-Machine 时 -Command 必须是本机 templates 下的角色名（planner/coder/reviewer/helper…），不能直接写程序名：$Command"
    }

    # 机器在线？该机器上是否已有 live 的 worker？
    $lsJson = (& hc ls --json | Out-String | ConvertFrom-Json)
    $mach = @($lsJson.machines | Where-Object { $_.name -eq $Machine }) | Select-Object -First 1
    if (-not $mach -or $mach.state -ne 'connected') {
        Stop-Remote "机器 $Machine 当前不是 connected（$(if ($mach) { $mach.state } else { 'hc machine ls 里没有' })）。可以试 hc machine login $Machine" 3
    }
    $shells = @('bash', 'sh', 'zsh', 'fish', 'dash')
    $busy = @($lsJson.terminals | Where-Object { $_.address -like "$Machine/*" -and $_.state -eq 'live' -and ($shells -notcontains $_.agent) })
    if ($busy.Count -ge $rp.MaxWorkers) {
        $desc = ($busy | ForEach-Object { "$($_.address)($(if ($_.name) { $_.name } else { $_.agent }))" }) -join ', '
        Stop-Remote "$Machine 上已有 live 的 worker：$desc。服务器内存紧张，同时只允许 $($rp.MaxWorkers) 个；等它结束并验收、hc kill + hc rm 之后再派。" 4
    }

    # 工作目录：必须已存在；只有 ~/work/ 和 /tmp/ 下的可以代为创建
    & hc exec --on $Machine -- test -d $Cwd *> $null
    if ($LASTEXITCODE -ne 0) {
        if ($Cwd -like "$($rp.Home)/work/*" -or $Cwd -like '/tmp/*') {
            & hc exec --on $Machine -- mkdir -p $Cwd *> $null
            if ($LASTEXITCODE -ne 0) { Stop-Remote "在 $Machine 上创建工作目录失败：$Cwd" 3 }
        } else {
            Stop-Remote "$Machine 上的工作目录不存在：$Cwd（只有 $($rp.Home)/work/ 和 /tmp/ 下的目录会自动创建）"
        }
    }
    $sessionDir = "$($rp.Home)/.local/share/sv-sessions/$Name"
    & hc exec --on $Machine -- mkdir -p $sessionDir *> $null

    # 生成服务器版的一次性 template
    $argv = Get-RemoteOmpArgv $rp $Model $Effort $sessionDir
    $short = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $tag = (@($Model, $(if ($Effort) { $Effort } else { 'default' })) | ForEach-Object { $_.ToLower() -replace '[^a-z0-9-]', '-' }) -join '--'
    $launchName = ("sv-$Command--$tag--$short")
    $remoteTpl = "$($rp.TemplateDir)/$launchName.md"
    $tplText = ConvertTo-RemoteTemplate ([IO.File]::ReadAllText($templateFile)) $launchName $argv

    $hcArgs = @('run', '--bg', '--json', '--on', $Machine, '--name', $Name, '--cwd', $Cwd)
    # 一律 --no-notify：hc 不往 supervisor 的终端里打字（会和用户正在输入的内容混在一起），由 tools\watch.ps1 在后台监听
    $hcArgs += @('--no-notify')
    if ($Detached) { $hcArgs += @('--no-parent') }
    $hcArgs += @('--label', "sv.role=$Command", '--label', "sv.model=$Model", '--label', "sv.machine=$Machine")
    if ($Effort) { $hcArgs += @('--label', "sv.effort=$Effort") }
    $rspace = Get-RemoteSupervisorSpace $Machine $rp.Home
    if ($rspace) { $hcArgs += @('--label', "herdr.space=$(Get-SpaceLabel $rspace)") }
    $hcArgs += @($launchName, $Task)

    $out = $null; $code = 1
    try {
        [void](Write-RemoteFile $Machine $remoteTpl $tplText)
        $out = & hc @hcArgs | Out-String
        $code = $LASTEXITCODE
    } finally {
        # hc run 返回时首条消息已经发出（或已确定没发出），一次性 template 不再需要；只删自己写的这个文件
        & hc exec --on $Machine -- rm -f $remoteTpl *> $null
    }
    Write-Output $out.Trim()
    if ($code -ne 0) { exit $code }

    $res = $out | ConvertFrom-Json
    if ($rspace) { Rename-WorkerTab $rspace "$($res.address)" $Name $Machine }
    New-Item -ItemType Directory -Force $workersDir | Out-Null
    $rmeta = [ordered]@{ name = $Name; machine = $Machine; address = "$($res.address)"; cwd = $Cwd; role = $Command; model = $Model; effort = $Effort; launcher = 'omp'; argv = $argv; session = $sessionDir; created = (Get-Date).ToString('s'); note = 'resume.ps1 不支持远程 worker' }
    [IO.File]::WriteAllText((Join-Path $workersDir "$Name.remote.json"), ($rmeta | ConvertTo-Json -Depth 4), $utf8)

    # 提示：谁是 parent（服务器上的 worker 只能回报给它的 parent）
    $parentInfo = ''
    if ($res.parent) {
        $pname = $null
        try { $pname = ((& hc get $res.parent --json | Out-String | ConvertFrom-Json).name) } catch {}
        $parentInfo = "parent=$($res.parent)$(if ($pname) { "（$pname）" })"
        if ($pname -ne 'supervisor') { $parentInfo += '  注意：parent 不是 supervisor 终端，worker 的回报到不了 supervisor；请从 supervisor 终端直接派活，或自己用 hc wait / 报告文件验收' }
    } else {
        $parentInfo = 'parent=无  注意：没有 parent，worker 无法用 hc send 回报，也不会触发 hc wait --children；请用 hc wait ' + $res.address + ' 并读报告文件'
    }
    Write-Host "# 跨机 worker $($res.address)；$parentInfo"
    Write-Host "# 服务器文件用 hc file read --on $Machine <路径>、hc exec --on $Machine -- <命令> 读取，本机的 Read/Grep 工具读不到。"
    exit 0
}

# ---- 工作目录检查 ----
$workRoot = Join-Path $root 'state\work'
$cwdFull = [IO.Path]::GetFullPath($Cwd)
if (-not (Test-Path $cwdFull)) {
    if ($cwdFull.StartsWith($workRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        New-Item -ItemType Directory -Force $cwdFull | Out-Null
    } else {
        Write-Error "工作目录不存在：$cwdFull"
        exit 2
    }
}
if ($cwdFull.TrimEnd('\') -ieq $root.TrimEnd('\')) {
    Write-Error "不要在 supervisor 仓库根目录里派 worker；杂项任务请用 state\work\<编号>"
    exit 2
}

# ---- 组装启动命令 ----
$templateFile = Join-Path $templateDir "$Command.md"
$launchName = $Command      # 交给 hc run 的 template 名或程序名
$oneShot = $null            # 一次性 template 文件，启动后删除
$meta = [ordered]@{ name = $Name; cwd = $cwdFull; role = $Command; model = $Model; effort = $Effort; launcher = $null; argv = $null; session = $null; created = (Get-Date).ToString('s') }

if (Test-Path $templateFile) {
    $text = [IO.File]::ReadAllText($templateFile)
    $m = [regex]::Match($text, '(?m)^command:\s*(.+?)\s*$')
    $baseArgv = if ($m.Success) { $m.Groups[1].Value -split '\s+' } else { @('claude', '--permission-mode', 'auto') }
    $launcher = if ($Model) { Get-Launcher $Model } else { $baseArgv[0] }

    $argv = $null
    if ($launcher -eq 'claude') {
        if ($baseArgv[0] -ne 'claude') { $baseArgv = @('claude', '--permission-mode', 'auto') }
        $argv = Remove-Flags $baseArgv @('--model', '--effort', '--session-id')
        if ($Model) { $argv += @('--model', $Model) }
        if ($Effort) { $argv += @('--effort', $Effort) }
        $sid = [guid]::NewGuid().ToString()
        $argv += @('--session-id', $sid)
        $meta.session = $sid
    } elseif ($launcher -eq 'omp') {
        # 外面套 @()：否则只有一个元素时 PowerShell 会把数组拆成字符串，后面的 += 就变成字符串拼接
        $argv = @(if ($Model -or $baseArgv[0] -ne 'omp') { 'omp' } else { Remove-Flags $baseArgv @('--model', '--thinking', '--session-dir') })
        if ($Model) { $argv += @('--model', $Model) }
        if ($Effort) { $argv += @('--thinking', $Effort) }
        $sdir = (Join-Path $root "state\sessions\$Name")
        New-Item -ItemType Directory -Force $sdir | Out-Null
        $argv += @('--session-dir', ($sdir -replace '\\', '/'))
        $meta.session = $sdir
    }

    if ($argv) {
        $meta.launcher = $launcher
        $meta.argv = $argv
        $short = [guid]::NewGuid().ToString('N').Substring(0, 6)
        $tag = (@($(if ($Model) { $Model } else { 'default' }), $(if ($Effort) { $Effort } else { 'default' })) | ForEach-Object { $_.ToLower() -replace '[^a-z0-9-]', '-' }) -join '--'
        $launchName = "$Command--$tag--$short"
        $out = $text
        if ($m.Success) {
            $out = $text.Substring(0, $m.Index) + "command: $(Join-ShArgs $argv)" + $text.Substring($m.Index + $m.Length)
        }
        $out = [regex]::Replace($out, '(?m)^name:\s*.+$', "name: $launchName", 1)
        $oneShot = Join-Path $templateDir "$launchName.md"
        [IO.File]::WriteAllText($oneShot, $out, $utf8)
    }
}

# ---- 启动 ----
$space = Get-SupervisorSpace
$hcArgs = @('run', '--bg', '--json', '--name', $Name, '--cwd', $cwdFull)
# 一律 --no-notify：hc 不往 supervisor 的终端里打字（会和用户正在输入的内容混在一起），由 tools\watch.ps1 在后台监听
    $hcArgs += @('--no-notify')
    if ($Detached) { $hcArgs += @('--no-parent') }
if ($space) { $hcArgs += @('--label', "herdr.space=$($space.id)") }
$hcArgs += @('--label', "sv.role=$Command")
if ($Model) { $hcArgs += @('--label', "sv.model=$Model") }
if ($Effort) { $hcArgs += @('--label', "sv.effort=$Effort") }
$hcArgs += @($launchName, $Task)

try {
    $out = & hc @hcArgs | Out-String
    $code = $LASTEXITCODE
} finally {
    # hc run 返回时首条消息已经发出（或已确定没发出），一次性 template 不再需要
    if ($oneShot) { Remove-Item $oneShot -ErrorAction SilentlyContinue }
}
Write-Output $out.Trim()
if ($code -ne 0) { exit $code }

$address = ($out | ConvertFrom-Json).address
if ($meta.session) {
    New-Item -ItemType Directory -Force $workersDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $workersDir "$Name.json"), ($meta | ConvertTo-Json -Depth 4), $utf8)
}
if ($space) { Rename-WorkerTab $space $address $Name }
