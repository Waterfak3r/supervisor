# dispatch.ps1 和 resume.ps1 共用的函数。

# Herdr 里名为 Supervisor 的空间。不传 $machine 时只找本机的；传了就找那台机器上的。
# （每台机器各有自己的 Supervisor 空间：Herdr 只显示挂在"同一台机器上的空间"里的终端。）
function Get-SupervisorSpace([string]$machine) {
    try {
        $ls = herdr-app ls 2>$null | Out-String | ConvertFrom-Json
        return ($ls.spaces | Where-Object {
                $_.name -eq 'Supervisor' -and $(if ($machine) { $_.machine -eq $machine } else { -not $_.machine })
            } | Select-Object -First 1)
    } catch { return $null }
}

# 远程机器上的 Supervisor 空间，没有就建一个（会带一个 shell 标签页，这是 Herdr 建空间的要求）。
# Herdr 窗口没开时返回 $null，worker 照常启动，只是不显示在面板里。
function Get-RemoteSupervisorSpace([string]$machine, [string]$folder) {
    $s = Get-SupervisorSpace $machine
    if (-not $s) {
        try { herdr-app do space.new --name Supervisor --machine $machine --folder $folder --tab shell *> $null } catch {}
        $s = Get-SupervisorSpace $machine
    }
    return $s
}

# 给 hc 打的 herdr.space 标签值：远程空间的 id 带 "<机器>/" 前缀，写标签时要去掉
function Get-SpaceLabel($space) {
    return ($space.id -replace '^[^/]+/', '')
}

# 新 worker 的标签页默认叫编号，改成 worker 名
function Rename-WorkerTab($space, [string]$address, [string]$name, [string]$machine) {
    for ($i = 0; $i -lt 15; $i++) {
        $s = Get-SupervisorSpace $machine
        $tab = $s.tabs | Where-Object { $_.terminals.terminal -contains $address } | Select-Object -First 1
        if ($tab) { herdr-app do tab.rename --id $tab.id --name $name *> $null; return }
        Start-Sleep -Milliseconds 300
    }
}

# 哪个程序来跑这个模型：带 provider/ 前缀（如 google-antigravity/gemini-3.8-flash、
# xai-oauth/grok-4.7）的走 omp；Claude 的别名或 claude-* 走 claude。
function Get-Launcher([string]$model) {
    if (-not $model) { return 'claude' }
    if ($model -match '/') { return 'omp' }
    if ($model -match '^(haiku|sonnet|opus|fable)$' -or $model -match '^claude-') { return 'claude' }
    return 'omp'
}

# 从参数数组里去掉 "--flag value" 形式的参数
function Remove-Flags([string[]]$argv, [string[]]$flags) {
    $out = @()
    for ($i = 0; $i -lt $argv.Count; $i++) {
        if ($flags -contains $argv[$i]) { $i++; continue }
        $out += $argv[$i]
    }
    return , $out
}

# 把参数数组拼成给 sh 执行的命令行（template 的 command 由 sh 执行）
function Join-ShArgs([string[]]$argv) {
    return ($argv | ForEach-Object { if ($_ -match '^[A-Za-z0-9_./:=-]+$') { $_ } else { "'" + ($_ -replace "'", "'\''") + "'" } }) -join ' '
}

# ================= 跨机派活（-Machine）用的函数 =================

# 已登记的远程机器。服务器的 hc core 只有最小 PATH，所以 command 里必须写绝对路径；
# 而且 omp 的 shebang 是 `env bun`，bun 在 ~/.npm-global/bin 里，所以还要显式给 PATH
# （PATH 里也要有 ~/.local/bin，worker 要靠它找到 hc 回报）。
$script:RemoteProfiles = @{
    'tc-62' = @{
        Home        = '/home/ubuntu'
        Omp         = '/home/ubuntu/.npm-global/bin/omp'
        Path        = '/home/ubuntu/.npm-global/bin:/home/ubuntu/.local/bin:/home/ubuntu/.grok/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin'
        TemplateDir = '/home/ubuntu/.config/herdr-core/templates'
        MaxWorkers  = 1
    }
}

function Get-RemoteProfile([string]$machine) {
    if ($script:RemoteProfiles.ContainsKey($machine)) { return $script:RemoteProfiles[$machine] }
    return $null
}

# 服务器上 omp 的完整启动命令（数组）。$sessionDir 为空就不带 --session-dir。
function Get-RemoteOmpArgv($rp, [string]$model, [string]$effort, [string]$sessionDir) {
    $argv = @('env', "PATH=$($rp.Path)", $rp.Omp)
    if ($model) { $argv += @('--model', $model) }
    if ($effort) { $argv += @('--thinking', $effort) }
    if ($sessionDir) { $argv += @('--session-dir', $sessionDir) }
    return , $argv
}

# 把本机的 template 文本改写成服务器版：换名字、换 command、追加服务器规则（tools\remote-notes.md），行尾统一成 LF
function ConvertTo-RemoteTemplate([string]$text, [string]$name, [string[]]$argv) {
    $notes = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'remote-notes.md')) -replace "`r`n", "`n"
    $t = $text -replace "`r`n", "`n"
    $nm = [regex]::Match($t, '(?m)^name:[ \t]*.+$')
    if ($nm.Success) { $t = $t.Substring(0, $nm.Index) + "name: $name" + $t.Substring($nm.Index + $nm.Length) }
    $m = [regex]::Match($t, '(?m)^command:[ \t]*.+$')
    $line = "command: $(Join-ShArgs $argv)"
    if ($m.Success) { $t = $t.Substring(0, $m.Index) + $line + $t.Substring($m.Index + $m.Length) }
    return $t.TrimEnd() + "`n`n" + $notes.TrimEnd() + "`n"
}

# 把文本写成远程文件：先写到本机临时文件（UTF-8 无 BOM、保持 LF），再用 cmd 的 < 重定向喂给 hc file write。
# 不经过 PowerShell 管道，所以不会带 BOM（PS 管道和 .NET 的 Process.StandardInput 都会加 BOM，实测）。
function Write-RemoteFile([string]$machine, [string]$path, [string]$text) {
    if ($machine -notmatch '^[A-Za-z0-9_-]+$' -or $path -notmatch '^/[A-Za-z0-9_./-]+$') {
        throw "Write-RemoteFile：机器名或路径含有不允许的字符：$machine $path"
    }
    $hcExe = (Get-Command hc -CommandType Application | Select-Object -First 1).Source
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("sv-rw-" + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $env:ComSpec
        # cmd /c 后面整段再套一层引号，cmd 会剥掉最外层
        $psi.Arguments = '/c ""' + $hcExe + '" file write --json --on ' + $machine + ' ' + $path + ' < "' + $tmp + '""'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $so = $p.StandardOutput.ReadToEnd()
        $se = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { throw "hc file write 失败（exit $($p.ExitCode)）：$se $so" }
        return $so.Trim()
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# ---- 启动 worker，但首条消息不带"做完用 hc send 回报"----
# hc run 从某个终端里发起时（环境变量 HC_TERMINAL_ID 指向发起者），会把模板首条消息包成
#   <hc from="t1f" reach="hc send t1f when done or stuck">…</hc>
# 等于叫 worker 做完后往 supervisor 的终端里打字回报，会和用户正在输入的内容拼在一起；上下文一长，worker 可能更听它的而不是模板。
# 办法（2026-11-10 实测）：发起 hc run 时临时去掉 HC_TERMINAL_ID，hc 就不知道是谁发的，首条消息不再包这一层；
# 父终端改用 --parent 显式指定，parent 关系（状态栏、子终端随父终端结束）照旧。
function Get-ParentArgs([bool]$detached) {
    if ($detached) { return @('--no-parent') }
    if ($env:HC_TERMINAL_ID) { return @('--parent', $env:HC_TERMINAL_ID) }
    return @()
}
function Invoke-HcAnonymous([string[]]$hcArgs) {
    $saved = $env:HC_TERMINAL_ID
    try {
        Remove-Item env:HC_TERMINAL_ID -ErrorAction SilentlyContinue
        & hc @hcArgs | Out-String
    } finally {
        if ($saved) { $env:HC_TERMINAL_ID = $saved }
    }
}