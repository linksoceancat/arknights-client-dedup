# 生成单文件版：把 ArknightsDedup.ps1 内嵌进可自解压的 .bat
# 产物：
#   dist\ArknightsDedup-standalone.bat  交互菜单版（双击后弹菜单）
#   dist\ArknightsDedup-silent.bat      一键静默去重版（双击直接去重，结束暂停）
[CmdletBinding()]
param(
  [string]$SourcePs1,
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'
if (-not $SourcePs1) { $SourcePs1 = Join-Path $PSScriptRoot 'ArknightsDedup.ps1' }
if (-not $OutDir)   { $OutDir   = Join-Path $PSScriptRoot 'dist' }
if (-not (Test-Path -LiteralPath $SourcePs1)) { throw "找不到源脚本: $SourcePs1" }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$code = Get-Content -LiteralPath $SourcePs1 -Raw -Encoding UTF8

$extract = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText(''%~f0'',[Text.Encoding]::UTF8); $i=$t.LastIndexOf(''#>>>PS1>>>''); if($i -lt 0){exit 1}; $j=$t.IndexOf([char]10,$i); [IO.File]::WriteAllText(''%AKD_PS1%'',$t.Substring($j+1),(New-Object System.Text.UTF8Encoding($true)))"'

$headerMenu = @'
@echo off
chcp 65001 >nul
setlocal
set "AKD_PS1=%~dp0ArknightsDedup.ps1"
'@ + "`r`n" + $extract + "`r`n" + @'
if not exist "%AKD_PS1%" ( echo Failed to extract script. & pause & exit /b 1 )
powershell -NoProfile -ExecutionPolicy Bypass -File "%AKD_PS1%" %*
endlocal
exit /b
#>>>PS1>>>
'@

$headerSilent = @'
@echo off
chcp 65001 >nul
setlocal
set "AKD_PS1=%~dp0ArknightsDedup.ps1"
'@ + "`r`n" + $extract + "`r`n" + @'
if not exist "%AKD_PS1%" ( echo Failed to extract script. & pause & exit /b 1 )
echo.
echo ============================================
echo   One-click dedup. Close the game/launcher
echo   of both Official and Bilibili first.
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%AKD_PS1%" -Action Dedup
echo.
pause
endlocal
exit /b
#>>>PS1>>>
'@

$utf8Bom = New-Object System.Text.UTF8Encoding($true)

$outMenu   = Join-Path $OutDir 'ArknightsDedup-standalone.bat'
$outSilent = Join-Path $OutDir 'ArknightsDedup-silent.bat'

[System.IO.File]::WriteAllText($outMenu,   ($headerMenu   + "`r`n" + $code), $utf8Bom)
[System.IO.File]::WriteAllText($outSilent, ($headerSilent + "`r`n" + $code), $utf8Bom)

Write-Host ("已生成: {0}  ({1:N1} KB)" -f $outMenu,   ((Get-Item -LiteralPath $outMenu).Length / 1KB))
Write-Host ("已生成: {0}  ({1:N1} KB)" -f $outSilent, ((Get-Item -LiteralPath $outSilent).Length / 1KB))
