#requires -Version 5.1
<#
  明日方舟 单客户端 渠道切换器
  ------------------------------------------------------------
  用途：只保留「一份游戏主体」，通过替换登录渠道层，在官服 / B服之间切换登录。

  原理：官服与 B服的游戏主体逐字节相同，区别只在「渠道层」——
  可执行文件(Arknights.exe/GameAssembly.dll/UnityPlayer.dll)、登录SDK、
  以及渠道配置。本工具把这些不同的文件分别打包成两个「渠道包」，
  切换时把目标渠道包覆盖回游戏目录。

  ⚠ 警告：
    - 这是修改游戏客户端文件的操作，官方不支持，可能违反用户协议；
    - 可能触发反作弊(AntiCheatExpert)，有封号风险；
    - 游戏大版本更新后渠道层可能不匹配，需重新构建渠道包。
    请自行评估风险，使用后果自负。
#>
[CmdletBinding()]
param(
  [ValidateSet('Menu', 'Setup', 'Switch', 'Status', 'Launch')]
  [string]$Action = 'Menu',
  [ValidateSet('Official', 'Bilibili')]
  [string]$Channel = 'Official',
  [ValidateSet('Official', 'Bilibili')]
  [string]$Keep = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Version = '1.0.1'
$Root = $PSScriptRoot
$ConfigPath = Join-Path $Root 'channel-config.json'
$LogPath = Join-Path $Root 'channel-run.log'

function Write-Log {
  param([string]$Message)
  $line = '{0} {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
  Write-Host $line
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Format-Size {
  param([long]$Bytes)
  if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) }
  elseif ($Bytes -ge 1MB) { '{0:N2} MB' -f ($Bytes / 1MB) }
  else { "$Bytes B" }
}

function Get-FixedDrives {
  Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object -ExpandProperty DeviceID
}

function Test-GameRoot {
  param([string]$Path, [ValidateSet('Official', 'Bilibili', 'Any')][string]$Kind = 'Any')
  if (-not (Test-Path -LiteralPath (Join-Path $Path 'Arknights.exe'))) { return $false }
  switch ($Kind) {
    'Official' { return (Test-Path -LiteralPath (Join-Path $Path 'hgsdk.dll')) }
    'Bilibili' { return (Test-Path -LiteralPath (Join-Path $Path 'BLPlatform64\PCGamePlatform.exe')) -or (Test-Path -LiteralPath (Join-Path $Path 'PCGameSDK.dll')) }
    default    { return $true }
  }
}

function Find-Clients {
  $result = @{ Official = $null; Bilibili = $null }
  foreach ($d in Get-FixedDrives) {
    $roots = @($d) + @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    foreach ($r in $roots) {
      foreach ($sub in @('games\Arknights', 'games\Arknights Game')) {
        $p = Join-Path $r $sub
        if (Test-GameRoot $p 'Official') { if (-not $result.Official) { $result.Official = $p } }
        elseif (Test-GameRoot $p 'Bilibili') { if (-not $result.Bilibili) { $result.Bilibili = $p } }
      }
    }
  }
  return $result
}

function Load-Config {
  if (Test-Path -LiteralPath $ConfigPath) {
    try { return (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
  }
  return $null
}

function Save-Config {
  param($Obj)
  $Obj | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Assert-NotRunning {
  $p = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Arknights|Launcher' }
  if ($p) {
    $names = ($p.ProcessName | Select-Object -Unique) -join ', '
    throw "检测到游戏/启动器正在运行，请先全部关闭后再操作：$names"
  }
}

function Get-RelFiles {
  param([string]$GameRoot)
  Get-ChildItem -LiteralPath $GameRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { [PSCustomObject]@{ Rel = $_.FullName.Substring($GameRoot.Length + 1); Size = $_.Length } }
}

function Invoke-Compare {
  param([string]$Official, [string]$Bilibili)
  $a = Get-RelFiles $Official
  $b = Get-RelFiles $Bilibili
  $amap = @{}; foreach ($x in $a) { $amap[$x.Rel] = $x.Size }
  $bmap = @{}; foreach ($x in $b) { $bmap[$x.Rel] = $x.Size }

  $officialOnly = @(); $bilibiliOnly = @(); $different = @()
  foreach ($x in $a) { if (-not $bmap.ContainsKey($x.Rel)) { $officialOnly += $x.Rel } }
  foreach ($x in $b) { if (-not $amap.ContainsKey($x.Rel)) { $bilibiliOnly += $x.Rel } }

  foreach ($x in $a) {
    if (-not $bmap.ContainsKey($x.Rel)) { continue }
    if ($bmap[$x.Rel] -ne $x.Size) { $different += $x.Rel; continue }
    $ha = (Get-FileHash -LiteralPath (Join-Path $Official $x.Rel) -Algorithm MD5).Hash
    $hb = (Get-FileHash -LiteralPath (Join-Path $Bilibili $x.Rel) -Algorithm MD5).Hash
    if ($ha -ne $hb) { $different += $x.Rel }
  }
  return @{ OfficialOnly = $officialOnly; BilibiliOnly = $bilibiliOnly; Different = $different }
}

function Copy-Rel {
  param([string]$SrcRoot, [string]$Rel, [string]$DstRoot)
  $src = Join-Path $SrcRoot $Rel
  $dst = Join-Path $DstRoot $Rel
  if (-not (Test-Path -LiteralPath $src)) { return }
  $dstDir = Split-Path -Parent $dst
  if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

function Save-TextList {
  param([string]$Path, [string[]]$Items)
  Set-Content -LiteralPath $Path -Value $Items -Encoding UTF8
}

function Load-TextList {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  @(Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_ })
}

function Invoke-Setup {
  $found = Find-Clients
  if (-not $found.Official -and -not $found.Bilibili) {
    throw '未检测到《明日方舟》PC 客户端。请先安装官服或B服客户端。'
  }

  $official = $found.Official
  $bili = $found.Bilibili
  Write-Host ''
  Write-Host ('  官服: {0}' -f ($(if ($official) { $official } else { '(未安装)' })))
  Write-Host ('  B服: {0}' -f ($(if ($bili) { $bili } else { '(未安装)' })))
  Write-Host ''

  if (-not $official -or -not $bili) {
    Write-Host '⚠ 只检测到一个客户端。要构建完整的两个渠道包，' -ForegroundColor Yellow
    Write-Host '  你需要先安装另一个客户端（或把它的渠道文件放到本机）。' -ForegroundColor Yellow
    Write-Host ''
  }

  # 选择保留哪一个作为“主体”
  $base = $official
  $baseChannel = 'Official'
  if ($official -and $bili) {
    if ($Keep -eq 'Bilibili') { $base = $bili; $baseChannel = 'Bilibili' }
    elseif (-not $Keep) {
      $in = Read-Host '保留哪个客户端作为游戏主体？[1]官服(默认) [2]B服'
      if ($in -eq '2') { $base = $bili; $baseChannel = 'Bilibili' }
    }
  }
  elseif ($bili) { $base = $bili; $baseChannel = 'Bilibili' }

  $packRoot = Join-Path ([System.IO.Path]::GetPathRoot($base)) 'AK-Channel'
  $officialPack = Join-Path $packRoot 'official'
  $bilibiliPack = Join-Path $packRoot 'bilibili'

  Write-Log ('游戏主体(保留): {0}  [{1}]' -f $base, $baseChannel)
  Write-Log ('渠道包目录: {0}' -f $packRoot)

  # 需要两个客户端都在才能做差异比对
  if ($official -and $bili) {
    Write-Log '开始比对两个客户端...'
    $cmp = Invoke-Compare -Official $official -Bilibili $bili
    Write-Log ('  仅官服有: {0}  仅B服有: {1}  内容不同: {2}' -f $cmp.OfficialOnly.Count, $cmp.BilibiliOnly.Count, $cmp.Different.Count)

    foreach ($dir in @($officialPack, $bilibiliPack)) { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force } }
    New-Item -ItemType Directory -Path $officialPack -Force | Out-Null
    New-Item -ItemType Directory -Path $bilibiliPack -Force | Out-Null

    Write-Log '打包官服渠道文件...'
    foreach ($rel in @($cmp.OfficialOnly + $cmp.Different)) { Copy-Rel -SrcRoot $official -Rel $rel -DstRoot $officialPack }
    Write-Log '打包B服渠道文件...'
    foreach ($rel in @($cmp.BilibiliOnly + $cmp.Different)) { Copy-Rel -SrcRoot $bili -Rel $rel -DstRoot $bilibiliPack }

    Save-TextList (Join-Path $packRoot 'officialOnly.txt') $cmp.OfficialOnly
    Save-TextList (Join-Path $packRoot 'bilibiliOnly.txt') $cmp.BilibiliOnly
    Save-TextList (Join-Path $packRoot 'different.txt') $cmp.Different
  }
  else {
    # 只有一个客户端：至少把当前客户端自己的渠道层打包（用于日后还原）
    $only = if ($official) { $official } else { $bili }
    $onlyChannel = if ($official) { 'Official' } else { 'Bilibili' }
    $onlyPack = if ($official) { $officialPack } else { $bilibiliPack }
    foreach ($dir in @($officialPack, $bilibiliPack)) { if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }
    Write-Log ("只检测到一个客户端({0})，无法比对；请在装好另一个客户端后重新运行本菜单的 Setup。" -f $onlyChannel)
  }

  $cfg = [PSCustomObject]@{
    Base = $base
    BaseChannel = $baseChannel
    PackRoot = $packRoot
    OfficialPack = $officialPack
    BilibiliPack = $bilibiliPack
    Current = $baseChannel
  }
  Save-Config $cfg
  Write-Log '渠道包构建完成，配置已保存。'
  Write-Host ''
  Write-Host ('现在可以删除另一个客户端来省空间（手动），或用 [切换] 菜单登录不同渠道。') -ForegroundColor Cyan
}

function Invoke-Switch {
  param([string]$Target)

  $cfg = Load-Config
  if (-not $cfg) { throw '尚未初始化，请先运行 Setup（菜单 [1]）。' }
  Assert-NotRunning

  $base = $cfg.Base
  if (-not (Test-Path -LiteralPath (Join-Path $base 'Arknights.exe'))) { throw "游戏主体缺失: $base" }

  $officialOnly = Load-TextList (Join-Path $cfg.PackRoot 'officialOnly.txt')
  $bilibiliOnly = Load-TextList (Join-Path $cfg.PackRoot 'bilibiliOnly.txt')

  if ($Target -eq 'Official') { $pack = $cfg.OfficialPack; $toDelete = $bilibiliOnly }
  else                        { $pack = $cfg.BilibiliPack; $toDelete = $officialOnly }

  if (-not (Test-Path -LiteralPath $pack)) { throw "渠道包缺失: $pack" }

  Write-Log ('切换到 {0}：移除另一渠道独占文件 {1} 个...' -f $Target, $toDelete.Count)
  foreach ($rel in $toDelete) {
    $p = Join-Path $base $rel
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
  }

  foreach ($rel in $toDelete) {
    $dir = Split-Path -Parent (Join-Path $base $rel)
    while ($dir -and $dir -ne $base -and (Test-Path -LiteralPath $dir)) {
      if (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
        $dir = Split-Path -Parent $dir
      }
      else { break }
    }
  }

  Write-Log ('切换到 {0}：覆盖渠道文件...' -f $Target)
  $files = Get-ChildItem -LiteralPath $pack -Recurse -File -Force
  $i = 0
  foreach ($f in $files) {
    $i++
    $rel = $f.FullName.Substring($pack.Length + 1)
    Copy-Rel -SrcRoot $pack -Rel $rel -DstRoot $base
    if ($i % 200 -eq 0) { Write-Log ('  已覆盖 {0}/{1}' -f $i, $files.Count) }
  }

  $cfg.Current = $Target
  Save-Config $cfg
  Write-Log ('切换完成，当前渠道: {0}' -f $Target)
}

function Invoke-Launch {
  $cfg = Load-Config
  if (-not $cfg) { throw '尚未初始化，请先运行 Setup（菜单 [1]）。' }
  $exe = Join-Path $cfg.Base 'Arknights.exe'
  if (-not (Test-Path -LiteralPath $exe)) { throw "找不到游戏: $exe" }
  Write-Log ('启动游戏: {0}  (当前渠道 {1})' -f $exe, $cfg.Current)
  Start-Process -FilePath $exe -WorkingDirectory $cfg.Base
}

function Show-Status {
  $cfg = Load-Config
  if (-not $cfg) {
    Write-Host ''
    Write-Host '尚未初始化。请先运行菜单 [1] Setup。' -ForegroundColor Yellow
    return
  }
  Write-Host ''
  Write-Host '================= 渠道切换 状态 =================' -ForegroundColor Cyan
  Write-Host ('游戏主体 : {0}' -f $cfg.Base)
  Write-Host ('当前渠道 : {0}' -f $cfg.Current)
  Write-Host ('官服包   : {0}' -f $cfg.OfficialPack)
  Write-Host ('B服包    : {0}' -f $cfg.BilibiliPack)
  $exe = Join-Path $cfg.Base 'Arknights.exe'
  if (Test-Path -LiteralPath $exe) {
    $isBili = (Test-Path -LiteralPath (Join-Path $cfg.Base 'BLPlatform64\PCGamePlatform.exe')) -or (Test-Path -LiteralPath (Join-Path $cfg.Base 'PCGameSDK.dll'))
    $actual = if ($isBili) { 'Bilibili' } else { 'Official' }
    Write-Host ('实际渠道 : {0}（按当前渠道文件判断）' -f $actual)
  }
  Write-Host '===============================================' -ForegroundColor Cyan
  Write-Host ''
}

function Show-Menu {
  Clear-Host
  Write-Host '================================================' -ForegroundColor Magenta
  Write-Host ('     明日方舟 单客户端 渠道切换器  v{0}' -f $Version) -ForegroundColor Magenta
  Write-Host '================================================' -ForegroundColor Magenta
  Write-Host '  [1] 初始化/重建渠道包 (Setup)'
  Write-Host '  [2] 切换到 官服'
  Write-Host '  [3] 切换到 B服'
  Write-Host '  [4] 启动游戏'
  Write-Host '  [5] 查看状态'
  Write-Host '  [0] 退出'
  Write-Host ''
  Write-Host '  ⚠ 改客户端文件有封号风险，请自行评估' -ForegroundColor Yellow
  Write-Host ''
}

function Start-Menu {
  while ($true) {
    Show-Menu
    $choice = Read-Host '请输入选项'
    switch ($choice) {
      '1' { try { Invoke-Setup } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回' | Out-Null }
      '2' { try { Invoke-Switch -Target 'Official' } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回' | Out-Null }
      '3' { try { Invoke-Switch -Target 'Bilibili' } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回' | Out-Null }
      '4' { try { Invoke-Launch } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回' | Out-Null }
      '5' { try { Show-Status } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回' | Out-Null }
      '0' { return }
      default { }
    }
  }
}

try {
  switch ($Action) {
    'Setup'   { Invoke-Setup }
    'Switch'  { Invoke-Switch -Target $Channel }
    'Status'  { Show-Status }
    'Launch'  { Invoke-Launch }
    'Menu'    { Start-Menu }
  }
}
catch {
  Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}


