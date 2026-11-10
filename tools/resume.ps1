# 恢复一个已经关掉的 worker 的原会话（上下文都还在），然后用 hc send 给它发新指令。
# 用法：
#   & D:\Programming\Project\supervisor\tools\resume.ps1 -Name demo-coder-T003
#   hc wait demo-coder-T003; hc send demo-coder-T003 '追问或返工说明'
# 依赖 dispatch.ps1 写下的 state\workers\<Name>.json。worker 还在运行时什么都不做。
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$Detached
)

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'common.ps1')

$metaFile = Join-Path $root "state\workers\$Name.json"
if (-not (Test-Path $metaFile)) {
    Write-Error "没有 $Name 的记录（$metaFile），无法恢复。只有通过 dispatch.ps1 派出的 worker 才能恢复。"
    exit 3
}
$meta = Get-Content $metaFile -Raw -Encoding utf8 | ConvertFrom-Json

$cur = $null
try { $cur = hc get $Name --json 2>$null | Out-String | ConvertFrom-Json } catch {}
if ($cur -and $cur.state -eq 'live') {
    Write-Output (@{ address = $cur.address; name = $Name; resumed = $false; note = '它还在运行，直接 hc send 即可' } | ConvertTo-Json -Compress)
    exit 0
}
if ($cur) { hc rm $Name *> $null }   # 清掉同名的已结束终端

$argv = @($meta.argv)
if ($meta.launcher -eq 'claude') {
    $argv = Remove-Flags $argv @('--session-id')
    $argv += @('--resume', $meta.session)
} elseif ($meta.launcher -eq 'omp') {
    $argv += @('--continue')
} else {
    Write-Error "不认识的 launcher：$($meta.launcher)"
    exit 3
}

$space = Get-SupervisorSpace
$hcArgs = @('run', '--bg', '--json', '--name', $Name, '--cwd', $meta.cwd)
$hcArgs += @('--no-notify')   # 不往 supervisor 的终端里打字，由 watch.ps1 监听
if ($Detached) { $hcArgs += @('--no-parent') }
if ($space) { $hcArgs += @('--label', "herdr.space=$($space.id)") }
$hcArgs += @('--label', "sv.role=$($meta.role)")
if ($meta.model) { $hcArgs += @('--label', "sv.model=$($meta.model)") }
if ($meta.effort) { $hcArgs += @('--label', "sv.effort=$($meta.effort)") }
$hcArgs += @('--') + $argv

$out = & hc @hcArgs | Out-String
$code = $LASTEXITCODE
Write-Output $out.Trim()
if ($code -ne 0) { exit $code }
if ($space) { Rename-WorkerTab $space (($out | ConvertFrom-Json).address) $Name }
