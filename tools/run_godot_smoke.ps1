# §12.7 / headless_smoke.gd — 在 PATH 或参数中定位 Godot 4.x
param(
    [string]$GodotExe = ""
)

$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root "client"
$scene = "res://scenes/qa/headless_smoke.tscn"

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
    Write-Host "Godot not found. Install Godot 4.x or pass -GodotExe 'C:\path\Godot.exe'"
    Write-Host "Then: python sim/validate_config_db.py  (config-only smoke)"
    exit 2
}

& $GodotExe --headless --path $client $scene
exit $LASTEXITCODE