# Godot 工程语法/资源加载快检（无头导入 + 跑主场景 1 帧后退出）。
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root "client\project.godot"

function Resolve-Godot {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }
    $candidates = @(
        "D:\godot\Godot_v4.7.2-stable_win64_console.exe",
        "D:\godot\Godot_v4.7.2-stable_win64.exe",
        "$env:ProgramFiles\Godot\Godot_v4.4-stable_win64.exe",
        "$env:ProgramFiles\Godot\Godot_v4.5-stable_win64.exe",
        "$env:ProgramFiles\Godot\Godot_v4.6-stable_win64.exe",
        "$env:ProgramFiles\Godot\Godot_v4.7-stable_win64.exe",
        "$env:LOCALAPPDATA\Programs\Godot\Godot.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
  $cmd = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

$godot = Resolve-Godot
if (-not $godot) {
    Write-Host "godot_compile_check: SKIP (set GODOT_BIN to Godot 4.7+ executable)"
    exit 2
}
if (-not (Test-Path $Project)) {
    Write-Host "godot_compile_check: FAIL missing $Project"
    exit 1
}

Write-Host "godot_compile_check: using $godot"
& $godot --headless --path (Join-Path $Root "client") --import 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "godot_compile_check: FAIL import exit $LASTEXITCODE"
    exit $LASTEXITCODE
}
& $godot --headless --path (Join-Path $Root "client") --quit-after 1 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "godot_compile_check: FAIL run exit $LASTEXITCODE"
    exit $LASTEXITCODE
}
Write-Host "godot_compile_check: OK"
exit 0