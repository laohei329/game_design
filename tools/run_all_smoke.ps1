# M1/M2 自动化：Python 配置 + Godot 无头 + 缺表探针
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "== validate_data_ci =="
python tools/validate_data_ci.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== validate_config_db =="
python sim/validate_config_db.py --probe balance.population.foodPerCapitaDay --probe balance.population.waterPerCapitaDay
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$weather = Join-Path $root "data\weather.json"
$bak = Join-Path $root "data\weather.json.smoke_bak"
$configOk = $true
if (Test-Path -LiteralPath $weather) {
    Write-Host "== missing weather.json should fail load =="
    Rename-Item -LiteralPath $weather -NewName "weather.json.smoke_bak"
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        python sim/validate_config_db.py *> $null
        $ErrorActionPreference = $prevEap
        $configOk = ($LASTEXITCODE -ne 0)
    } finally {
        if (Test-Path -LiteralPath $bak) {
            Rename-Item -LiteralPath $bak -NewName "weather.json"
        }
    }
    if (-not $configOk) {
        Write-Error "weather.json 删除后 validate 应失败"
        exit 1
    }
    Write-Host "OK weather probe"
}

Write-Host "== Godot headless smoke =="
& "$PSScriptRoot\run_godot_smoke.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== save kill smoke =="
& "$PSScriptRoot\run_save_kill_smoke.ps1"
exit $LASTEXITCODE