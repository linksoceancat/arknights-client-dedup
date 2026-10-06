#requires -Version 5.1
<#
  明日方舟 官服 / B服 客户端去重工具
  ------------------------------------------------------------
  利用 NTFS 硬链接，让官服与 B 服客户端共享「逐字节相同」的游戏资源，
  从而在不影响两个客户端正常使用的前提下，节省约一半磁盘占用。

  适用：Windows + NTFS，且官服与 B 服位于同一磁盘分区。
  仅读取并比对文件内容后建立硬链接；不会改动任何游戏内容。
#>
[CmdletBinding()]
param(
  [ValidateSet('Menu', 'Dedup', 'Rollback', 'Status')]
  [string]$Action = 'Menu'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Version      = '1.0.3'
$Root         = $PSScriptRoot
$DataDir      = Join-Path $Root 'data'
$ConfigPath   = Join-Path $Root 'config.json'
$ManifestPath = Join-Path $DataDir 'manifest.csv'
$RollbackPath = Join-Path $DataDir 'rollback.csv'
$LogPath      = Join-Path $DataDir 'run.log'

if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

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
  elseif ($Bytes -ge 1KB) { '{0:N2} KB' -f ($Bytes / 1KB) }
  else { "$Bytes B" }
}

function Get-FixedDrives {
  Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' |
    Select-Object -ExpandProperty DeviceID
}

function Test-GameRoot {
  param([string]$Path, [ValidateSet('Official', 'Bilibili', 'Any')][string]$Kind = 'Any')
  if (-not (Test-Path -LiteralPath (Join-Path $Path 'Arknights.exe'))) { return $false }
  switch ($Kind) {
    'Official' { return (Test-Path -LiteralPath (Join-Path $Path 'hgsdk.dll')) }
    'Bilibili' { return (Test-Path -LiteralPath (Join-Path $Path 'BLPlatform64')) -or (Test-Path -LiteralPath (Join-Path $Path 'PCGameSDK.dll')) }
    default    { return $true }
  }
}

function Find-Clients {
  $result = @{ Official = $null; Bilibili = $null; Others = @() }
  foreach ($d in Get-FixedDrives) {
    $roots = @($d) + @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    foreach ($r in $roots) {
      foreach ($sub in @('games\Arknights', 'games\Arknights Game')) {
        $p = Join-Path $r $sub
        if (Test-GameRoot $p 'Official' -ErrorAction SilentlyContinue) {
          if (-not $result.Official) { $result.Official = $p }
        }
        elseif (Test-GameRoot $p 'Bilibili' -ErrorAction SilentlyContinue) {
          if (-not $result.Bilibili) { $result.Bilibili = $p }
        }
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
  param([string]$Official, [string]$Bilibili)
  [PSCustomObject]@{ Official = $Official; Bilibili = $Bilibili } |
    ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Get-SameDriveError {
  param([string]$A, [string]$B)
  $da = [System.IO.Path]::GetPathRoot($A)
  $db = [System.IO.Path]::GetPathRoot($B)
  if ($da -ne $db) {
    return "官服与B服不在同一磁盘分区（$da 与 $db）。硬链接要求同一分区，请先移动到同一盘。"
  }
  return $null
}

function Resolve-Clients {
  param([switch]$ForceDetect, [switch]$Prompt)

  $cfg = Load-Config
  $official = $null
  $bili = $null

  if ($cfg -and -not $ForceDetect) {
    if ($cfg.Official -and (Test-Path -LiteralPath (Join-Path $cfg.Official 'Arknights.exe'))) { $official = $cfg.Official }
    if ($cfg.Bilibili -and (Test-Path -LiteralPath (Join-Path $cfg.Bilibili 'Arknights.exe'))) { $bili = $cfg.Bilibili }
  }

  if (-not $official -or -not $bili) {
    Write-Host '正在自动探测客户端安装位置...' -ForegroundColor Cyan
    $found = Find-Clients
    if (-not $official) { $official = $found.Official }
    if (-not $bili) { $bili = $found.Bilibili }
  }

  if ($Prompt -or -not $official -or -not $bili) {
    Write-Host ''
    Write-Host ('  官服当前: {0}' -f ($(if ($official) { $official } else { '(未找到)' })))
    Write-Host ('  B服 当前: {0}' -f ($(if ($bili) { $bili } else { '(未找到)' })))
    Write-Host ''
    if ($Prompt -or -not $official) {
      $in = Read-Host '  请输入官服游戏根目录（含 Arknights.exe），回车跳过'
      if ($in) { $official = $in.Trim().Trim('"') }
    }
    if ($Prompt -or -not $bili) {
      $in = Read-Host '  请输入B服游戏根目录（含 Arknights.exe），回车跳过'
      if ($in) { $bili = $in.Trim().Trim('"') }
    }
  }

  if (-not ($official -and (Test-Path -LiteralPath (Join-Path $official 'Arknights.exe')))) {
    throw '官服路径无效：未找到 Arknights.exe'
  }
  if (-not ($bili -and (Test-Path -LiteralPath (Join-Path $bili 'Arknights.exe')))) {
    throw 'B服路径无效：未找到 Arknights.exe'
  }
  $driveErr = Get-SameDriveError $official $bili
  if ($driveErr) { throw $driveErr }

  Save-Config -Official $official -Bilibili $bili
  return @{ Official = $official; Bilibili = $bili }
}

function Assert-NotRunning {
  $p = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Arknights|Launcher' }
  if ($p) {
    $names = ($p.ProcessName | Select-Object -Unique) -join ', '
    throw "检测到游戏/启动器正在运行，请先全部关闭后再操作：$names"
  }
}

function Get-ChildFiles {
  param([string]$GameRoot)
  Get-ChildItem -LiteralPath $GameRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { [PSCustomObject]@{ Rel = $_.FullName.Substring($GameRoot.Length + 1); Size = $_.Length } }
}

function Invoke-Analyze {
  param([string]$Official, [string]$Bilibili)

  Write-Log '枚举文件...'
  $a = Get-ChildFiles $Official
  $b = Get-ChildFiles $Bilibili
  Write-Log ('官服文件 {0} 个，B服文件 {1} 个' -f $a.Count, $b.Count)

  $bmap = @{}
  foreach ($x in $b) { $bmap[$x.Rel] = $x.Size }

  $cands = @($a | Where-Object { $bmap.ContainsKey($_.Rel) -and $bmap[$_.Rel] -eq $_.Size })
  Write-Log ('候选（同路径同大小）: {0} 个' -f $cands.Count)

  $rows = New-Object System.Collections.Generic.List[object]
  $i = 0
  foreach ($x in $cands) {
    $i++
    if ($i % 500 -eq 0) { Write-Log ('  校验 {0}/{1}' -f $i, $cands.Count) }
    $ap = Join-Path $Official $x.Rel
    $bp = Join-Path $Bilibili $x.Rel
    try {
      $ha = (Get-FileHash -LiteralPath $ap -Algorithm MD5).Hash
      $hb = (Get-FileHash -LiteralPath $bp -Algorithm MD5).Hash
      $rows.Add([PSCustomObject]@{ Rel = $x.Rel; Size = $x.Size; Identical = ($ha -eq $hb) })
    }
    catch {
      $rows.Add([PSCustomObject]@{ Rel = $x.Rel; Size = $x.Size; Identical = $false })
    }
  }
  $rows | Export-Csv -LiteralPath $ManifestPath -NoTypeInformation -Encoding UTF8

  $id = @($rows | Where-Object { $_.Identical }).Count
  Write-Log ('分析完成：一致 {0}，不一致 {1}' -f $id, ($rows.Count - $id))
  return $rows
}

function Invoke-Dedup {
  param([string]$Official, [string]$Bilibili)

  Assert-NotRunning
  $rows = Invoke-Analyze -Official $Official -Bilibili $Bilibili
  $targets = @($rows | Where-Object { $_.Identical })
  Write-Log ('开始去重，共 {0} 个文件' -f $targets.Count)

  $rb = New-Object System.Collections.Generic.List[object]
  $ok = 0; $fail = 0; $saved = 0L
  $i = 0
  foreach ($r in $targets) {
    $i++
    if ($i % 500 -eq 0) { Write-Log ('  去重 {0}/{1}' -f $i, $targets.Count) }
    $ap = Join-Path $Official $r.Rel
    $bp = Join-Path $Bilibili $r.Rel
    $action = ''
    try {
      if (-not (Test-Path -LiteralPath $ap)) { throw '官服源缺失' }
      $linked = $false
      if (Test-Path -LiteralPath $bp) {
        $item = Get-Item -LiteralPath $bp -Force
        if ($item.LinkType -eq 'HardLink') { $linked = $true }
        else { Remove-Item -LiteralPath $bp -Force }
      }
      else { throw 'B服目标缺失' }

      if ($linked) {
        $action = 'already-linked'
      }
      else {
        $null = cmd /c mklink /H "$bp" "$ap"
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $bp)) { $action = 'hardlink' }
        else { Copy-Item -LiteralPath $ap -Destination $bp -Force; $action = 'copied' }
      }
      if ($action -eq 'hardlink' -or $action -eq 'already-linked') { $saved += [long]$r.Size }
      $ok++
    }
    catch {
      $action = 'FAIL: ' + $_.Exception.Message
      $fail++
    }
    $rb.Add([PSCustomObject]@{ Rel = $r.Rel; Size = $r.Size; Official = $ap; Bilibili = $bp; Action = $action })
  }

  $rb | Export-Csv -LiteralPath $RollbackPath -NoTypeInformation -Encoding UTF8
  Write-Log ('去重完成：成功 {0}，失败 {1}，预计节省 {2}' -f $ok, $fail, (Format-Size $saved))
}

function Invoke-Rollback {
  param([string]$Official, [string]$Bilibili)

  Assert-NotRunning
  if (-not (Test-Path -LiteralPath $RollbackPath)) { Write-Log '找不到回滚清单 data\rollback.csv，无法回滚'; return }

  $rows = @(Import-Csv -LiteralPath $RollbackPath | Where-Object { $_.Action -eq 'hardlink' -or $_.Action -eq 'already-linked' })
  Write-Log ('开始回滚，共 {0} 个文件（内容不变，仅还原为独立副本）' -f $rows.Count)
  $ok = 0; $fail = 0
  foreach ($r in $rows) {
    try {
      if (-not (Test-Path -LiteralPath $r.Official)) { throw '官服源缺失' }
      if (Test-Path -LiteralPath $r.Bilibili) { Remove-Item -LiteralPath $r.Bilibili -Force }
      Copy-Item -LiteralPath $r.Official -Destination $r.Bilibili -Force
      $ok++
    }
    catch { $fail++; Write-Log ('  失败: {0} {1}' -f $r.Bilibili, $_.Exception.Message) }
  }
  Write-Log ('回滚完成：成功 {0}，失败 {1}' -f $ok, $fail)
}

function Show-Status {
  param([string]$Official, [string]$Bilibili)

  $guSum = (Get-ChildItem -LiteralPath $Official -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  $bbFiles = Get-ChildItem -LiteralPath $Bilibili -Recurse -File -Force -ErrorAction SilentlyContinue
  $shared = 0L; $own = 0L; $ownCount = 0; $linkCount = 0
  foreach ($f in $bbFiles) {
    if ($f.LinkType -eq 'HardLink') { $shared += $f.Length; $linkCount++ }
    else { $own += $f.Length; $ownCount++ }
  }
  Write-Host ''
  Write-Host ('================= 当前状态 (v{0}) =================' -f $Version) -ForegroundColor Cyan
  Write-Host ('官服路径 : {0}' -f $Official)
  Write-Host ('B服 路径 : {0}' -f $Bilibili)
  Write-Host ('官服占用 : {0}' -f (Format-Size $guSum))
  Write-Host ('B服 共享 : {0}（{1} 个硬链接，几乎不额外占盘）' -f (Format-Size $shared), $linkCount)
  Write-Host ('B服 独占 : {0}（{1} 个独立文件）' -f (Format-Size $own), $ownCount)
  Write-Host ('实际总占用 ≈ {0}' -f (Format-Size ($guSum + $own)))
  Write-Host '===========================================' -ForegroundColor Cyan
  Write-Host ''
}

function Show-Menu {
  Clear-Host
  Write-Host '================================================' -ForegroundColor Cyan
  Write-Host ('     明日方舟 官服 / B服 客户端去重工具  v{0}' -f $Version) -ForegroundColor Cyan
  Write-Host '================================================' -ForegroundColor Cyan
  Write-Host '  [1] 扫描并去重（节省磁盘空间）'
  Write-Host '  [2] 查看当前状态'
  Write-Host '  [3] 回滚（还原为各自独立文件）'
  Write-Host '  [4] 重新探测 / 设置客户端路径'
  Write-Host '  [0] 退出'
  Write-Host ''
}

function Start-Menu {
  while ($true) {
    Show-Menu
    $choice = Read-Host '请输入选项'
    switch ($choice) {
      '1' { try { $c = Resolve-Clients; Invoke-Dedup -Official $c.Official -Bilibili $c.Bilibili } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回菜单' | Out-Null }
      '2' { try { $c = Resolve-Clients; Show-Status -Official $c.Official -Bilibili $c.Bilibili } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回菜单' | Out-Null }
      '3' { try { $c = Resolve-Clients; Invoke-Rollback -Official $c.Official -Bilibili $c.Bilibili } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回菜单' | Out-Null }
      '4' { try { $c = Resolve-Clients -ForceDetect -Prompt; Write-Host '已保存配置。' -ForegroundColor Green } catch { Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red }; Read-Host '按回车返回菜单' | Out-Null }
      '0' { return }
      default { }
    }
  }
}

try {
  switch ($Action) {
    'Status'   { $c = Resolve-Clients; Show-Status -Official $c.Official -Bilibili $c.Bilibili }
    'Dedup'    { $c = Resolve-Clients; Invoke-Dedup -Official $c.Official -Bilibili $c.Bilibili }
    'Rollback' { $c = Resolve-Clients; Invoke-Rollback -Official $c.Official -Bilibili $c.Bilibili }
    'Menu'     { Start-Menu }
  }
}
catch {
  Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}




