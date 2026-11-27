# S1b.5 · 两次 Godot 进程：写 user:// 槽位后新进程读档
param(
    [string]$GodotExe = ""
)

$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root "client"
$scene = "res://scenes/qa/headless_save_kill.tscn"

if (-not $GodotExe) {
    $localGodot = "D:\godot\Godot_v4.7.2-stable_win64_console.exe"
    if (Test-Path -LiteralPath $localGodot) {
        $GodotExe = $localGodot
    } else {
        $candidates = @(
            (Get-Command godot -ErrorAction SilentlyContinue).Source,
            (Get-Command godot4 -ErrorAction SilentlyContinue).Source
        ) | Where-Object { $_ }
        if ($candidates) { $GodotExe = $candidates[0] }
    }
}

if (-not $GodotExe -or -not (Test-Path -LiteralPath $GodotExe)) {
    Write-Host "Godot not found for save_kill smoke"
    exit 2
}

Write-Host "== save_kill write =="
& $GodotExe --headless --path $client $scene
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== save_kill verify (new process) =="
& $GodotExe --headless --path $client $scene -- --verify
exit $LASTEXITCODE