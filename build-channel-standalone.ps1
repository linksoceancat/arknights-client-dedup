# 生成单文件版：把 ArknightsChannelSwitch.ps1 内嵌进可自解压的 .bat
# 产物：
#   dist\ArknightsChannelSwitch-standalone.bat  菜单版
#   dist\ArknightsChannelSwitch-official.bat    一键切换官服
#   dist\ArknightsChannelSwitch-bilibili.bat    一键切换B服
[CmdletBinding()]
param(
  [string]$SourcePs1,
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'
if (-not $SourcePs1) { $SourcePs1 = Join-Path $PSScriptRoot 'ArknightsChannelSwitch.ps1' }
if (-not $OutDir)   { $OutDir   = Join-Path $PSScriptRoot 'dist' }
if (-not (Test-Path -LiteralPath $SourcePs1)) { throw "找不到源脚本: $SourcePs1" }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$code = Get-Content -LiteralPath $SourcePs1 -Raw -Encoding UTF8

$extract = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText(''%~f0'',[Text.Encoding]::UTF8); $i=$t.LastIndexOf(''#>>>PS1>>>''); if($i -lt 0){exit 1}; $j=$t.IndexOf([char]10,$i); [IO.File]::WriteAllText(''%AKD_PS1%'',$t.Substring($j+1),(New-Object System.Text.UTF8Encoding($true)))"'

function New-OneFileBat {
  param([string]$OutFile, [string]$RuntimeLine)
  $header = @'
@echo off
chcp 65001 >nul
setlocal
set "AKD_PS1=%~dp0ArknightsChannelSwitch.ps1"
'@ + "`r`n" + $extract + "`r`n" + @'
if not exist "%AKD_PS1%" ( echo Failed to extract script. & pause & exit /b 1 )
'@ + "`r`n" + $RuntimeLine + @'

endlocal
exit /b
#>>>PS1>>>
'@
  $utf8Bom = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($OutFile, ($header + "`r`n" + $code), $utf8Bom)
  Write-Host ("已生成: {0}  ({1:N1} KB)" -f $OutFile, ((Get-Item -LiteralPath $OutFile).Length / 1KB))
}

New-OneFileBat (Join-Path $OutDir 'ArknightsChannelSwitch-standalone.bat') 'powershell -NoProfile -ExecutionPolicy Bypass -File "%AKD_PS1%" %*'

New-OneFileBat (Join-Path $OutDir 'ArknightsChannelSwitch-official.bat') @'
powershell -NoProfile -ExecutionPolicy Bypass -File "%AKD_PS1%" -Action Switch -Channel Official
echo.
pause
'@

New-OneFileBat (Join-Path $OutDir 'ArknightsChannelSwitch-bilibili.bat') @'
powershell -NoProfile -ExecutionPolicy Bypass -File "%AKD_PS1%" -Action Switch -Channel Bilibili
echo.
pause
'@
