# 把本机 templates 的服务器版推到远程机器的 ~/.config/herdr-core/templates/，文件名统一加 sv- 前缀。
# 用法：
#   & D:\Programming\Project\supervisor\tools\sync-templates.ps1 -Machine tc-62
#   & D:\Programming\Project\supervisor\tools\sync-templates.ps1 -Machine tc-62 -Roles helper,coder -DryRun
# 说明：
#  - 只写 sv-<角色>.md；服务器上已有的 reviewer、fixer、claude-reviewer 等不会被覆盖或删除（本脚本从不删文件）；
#  - 推过去的 command 是 omp 的绝对路径（服务器 core 的 PATH 是最小值）；claude 在服务器上没登录，所以不推 claude 版；
#  - 默认只推 helper、coder、reviewer。planner 要求第 4 档（opus），服务器上用不了，需要时用 -Roles 显式指定；
#  - 内容用 .NET 直接写进 hc file write 的 stdin（无 BOM、LF 行尾）；
#  - dispatch.ps1 -Machine 派活时会另外生成一次性变体，这里推的 sv-<角色> 主要给手动 hc run --on <机器> sv-helper 用。
param(
    [Parameter(Mandatory = $true)][string]$Machine,
    [string[]]$Roles = @('helper', 'coder', 'reviewer'),
    [string]$Model = 'google-antigravity/gemini-3.8-flash',   # Grok 经常被限流，默认用 Gemini
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')][string]$Effort = 'medium',
    [switch]$DryRun
)

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'common.ps1')

$rp = Get-RemoteProfile $Machine
if (-not $rp) { Write-Error "未登记的机器：$Machine（在 tools\common.ps1 的 RemoteProfiles 里加）"; exit 2 }
if ($Model -notmatch '/' -or (Get-Launcher $Model) -ne 'omp') { Write-Error "服务器未登录 claude，默认模型必须是带 provider/ 前缀的 omp 模型：$Model"; exit 2 }

$result = @()
foreach ($role in $Roles) {
    if ($role -notmatch '^[A-Za-z0-9_-]+$') { Write-Error "角色名不合法：$role"; exit 2 }
    $src = Join-Path $root "templates\$role.md"
    if (-not (Test-Path $src)) { Write-Error "本机没有 templates\$role.md"; exit 2 }
    $name = "sv-$role"
    $argv = Get-RemoteOmpArgv $rp $Model $Effort $null
    $text = ConvertTo-RemoteTemplate ([IO.File]::ReadAllText($src)) $name $argv
    $dest = "$($rp.TemplateDir)/$name.md"
    if ($DryRun) {
        $result += [pscustomobject]@{ role = $role; path = $dest; written = $false; bytes = [Text.Encoding]::UTF8.GetByteCount($text) }
        Write-Host "--- $dest ---"; Write-Host $text
        continue
    }
    $o = Write-RemoteFile $Machine $dest $text
    $result += [pscustomobject]@{ role = $role; path = $dest; written = $true; hc = $o }
}
$result | ConvertTo-Json -Compress
