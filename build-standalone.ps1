# 生成单文件版：把 ArknightsDedup.ps1 内嵌进一个可自解压的 .bat
# 产物：dist\ArknightsDedup-standalone.bat —— 只需这一个文件即可运行
[CmdletBinding()]
param(
  [string]$SourcePs1,
  [string]$OutFile
)

$ErrorActionPreference = 'Stop'
if (-not $SourcePs1) { $SourcePs1 = Join-Path $PSScriptRoot 'ArknightsDedup.ps1' }
if (-not $OutFile)   { $OutFile   = Join-Path $PSScriptRoot 'dist\ArknightsDedup-standalone.bat' }
if (-not (Test-Path -LiteralPath $SourcePs1)) { throw "找不到源脚本: $SourcePs1" }
$outDir = Split-Path -Parent $OutFile
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$code = Get-Content -LiteralPath $SourcePs1 -Raw -Encoding UTF8

$header = @'
@echo off
chcp 65001 >nul
setlocal
set "AKD_PS1=%~dp0ArknightsDedup.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $i=$t.LastIndexOf('#>>>PS1>>>'); if($i -lt 0){exit 1}; $j=$t.IndexOf([char]10,$i); [IO.File]::WriteAllText('%AKD_PS1%',$t.Substring($j+1),(New-Object System.Text.UTF8Encoding($true)))"
if not exist "%AKD_PS1%" ( echo Failed to extract script. & pause & exit /b 1 )
powershell -NoProfile -ExecutionPolicy Bypass -File "%AKD_PS1%" %*
endlocal
exit /b
#>>>PS1>>>
'@
$header += "`r`n"

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutFile, $header + $code, $utf8Bom)

Write-Host ("已生成: {0}  ({1:N1} KB)" -f $OutFile, ((Get-Item -LiteralPath $OutFile).Length / 1KB))
