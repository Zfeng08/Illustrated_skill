<#
  DSH 安全清理脚本
  只删除可重建的缓存，不触碰会话 / 附件 / 图片 / 工程 / 配置
  用法：
    clean-dsh.cmd           直接清理
    clean-dsh.cmd -Preview  只预览，不删除
#>
param([switch]$Preview)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$dsh = Join-Path $env:USERPROFILE '.dsh'
$ud  = Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop'

function Get-DirSizeMB([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return 0 }
  $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum
  if ($null -eq $s) { return 0 }
  return [math]::Round($s / 1MB, 1)
}

function Remove-DirSafe([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return $true }
  Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path -LiteralPath $p)) { return $true }
  # 长路径回退
  cmd /c "rd /s /q `"$p`"" 2>$null | Out-Null
  return (-not (Test-Path -LiteralPath $p))
}

# ---------- 白名单：可重建缓存 ----------
$targets = @(
  @{ Path = "$dsh\data\dsh-remotion\npm-cache";    Desc = 'Remotion npm 包缓存' }
  @{ Path = "$dsh\data\dsh-hyperframes\npm-cache"; Desc = 'HyperFrames npm 包缓存' }
  @{ Path = "$dsh\data\dsh-hyperframes\user-home\.cache\hyperframes\chrome"; Desc = 'headless Chrome 下载缓存' }
  @{ Path = "$dsh\data\dsh-remotion\tmp";          Desc = 'Remotion 临时文件' }
  @{ Path = "$dsh\data\dsh-hyperframes\tmp";       Desc = 'HyperFrames 临时文件' }
  @{ Path = "$dsh\cache\attachments";              Desc = '附件缩略图缓存' }
)

$appRunning = [bool](Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)

$electronDirs = @('Cache','Code Cache','GPUCache','GrShaderCache','DawnGraphiteCache','DawnWebGPUCache')

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host '   DSH 缓存清理' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '【将清理】' -ForegroundColor Yellow
$total = 0
foreach ($t in $targets) {
  $mb = Get-DirSizeMB $t.Path
  $total += $mb
  $exists = if (Test-Path -LiteralPath $t.Path) { '' } else { '（不存在，跳过）' }
  Write-Host ("  {0,-34} {1,8:N1} MB {2}" -f $t.Desc, $mb, $exists)
}

$eTotal = 0
foreach ($d in $electronDirs) {
  $p = Join-Path $ud $d
  $eTotal += (Get-DirSizeMB $p)
}
if ($appRunning) {
  Write-Host ("  {0,-34} {1,8:N1} MB （客户端运行中，本次跳过）" -f 'Chromium 界面缓存', $eTotal) -ForegroundColor DarkYellow
} else {
  Write-Host ("  {0,-34} {1,8:N1} MB" -f 'Chromium 界面缓存', $eTotal)
  $total += $eTotal
}

Write-Host ''
Write-Host ("预计释放：{0:N0} MB" -f $total) -ForegroundColor Green
Write-Host ''
Write-Host '【不会删除】' -ForegroundColor DarkGray
Write-Host '  会话记录 / 附件 / 生成图片 / 工程文件 / 技能 / 配置 / 凭据' -ForegroundColor DarkGray
Write-Host '  remotion 与 hyperframes 的 runtime 运行时（删了要重装依赖）' -ForegroundColor DarkGray
Write-Host ''

if ($Preview) {
  Write-Host '预览模式，未做任何删除。' -ForegroundColor Yellow
  Write-Host ''
  return
}

Write-Host '3 秒后开始清理，按 Ctrl+C 可取消 ...' -ForegroundColor Yellow
Start-Sleep -Seconds 3
Write-Host ''

$freed = 0
$failed = @()

foreach ($t in $targets) {
  if (-not (Test-Path -LiteralPath $t.Path)) { continue }
  $mb = Get-DirSizeMB $t.Path
  Write-Host ("  清理 {0} ..." -f $t.Desc) -NoNewline
  if (Remove-DirSafe $t.Path) {
    $freed += $mb
    Write-Host ' 完成' -ForegroundColor Green
  } else {
    $failed += $t.Desc
    Write-Host ' 失败（可能被占用）' -ForegroundColor Red
  }
}

if (-not $appRunning) {
  foreach ($d in $electronDirs) {
    $p = Join-Path $ud $d
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $mb = Get-DirSizeMB $p
    Write-Host ("  清理 Chromium {0} ..." -f $d) -NoNewline
    if (Remove-DirSafe $p) { $freed += $mb; Write-Host ' 完成' -ForegroundColor Green }
    else { $failed += "Chromium $d"; Write-Host ' 失败' -ForegroundColor Red }
  }
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ("  实际释放：{0:N0} MB" -f $freed) -ForegroundColor Green
if ($failed.Count -gt 0) {
  Write-Host ("  跳过/失败：{0}" -f ($failed -join '、')) -ForegroundColor Yellow
  Write-Host '  提示：关闭 DSH 客户端后重新运行可清理被占用的文件。' -ForegroundColor Yellow
}
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '说明：' -ForegroundColor DarkGray
Write-Host '  · headless Chrome 缓存被删后，下次导出 HyperFrames 视频会自动重新下载。' -ForegroundColor DarkGray
Write-Host '  · npm 缓存被删后，下次安装渲染依赖会稍慢一次，属正常。' -ForegroundColor DarkGray
Write-Host '  · 本清理不改变内存占用，UI 卡顿请重启客户端解决。' -ForegroundColor DarkGray
Write-Host ''
