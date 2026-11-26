# Bake portable VFX pack from assets/vfx_portable/manifest.json
param(
    [string]$Manifest = "",
    [string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if (-not $Manifest) { $Manifest = Join-Path $RepoRoot "assets\vfx_portable\manifest.json" }
$PixelfxGodot = Join-Path $RepoRoot "third_party\pixelfx-godot\godot"
$Pfx = Join-Path $PixelfxGodot "pfx"

if (-not (Test-Path $Manifest)) { throw "Missing manifest: $Manifest" }
if (-not (Test-Path $Pfx)) { throw "Missing pfx: $Pfx (pixelfx toolchain)" }

$meta = Get-Content $Manifest -Raw | ConvertFrom-Json
$packId = $meta.packId
if (-not $packId) { throw "manifest.json needs packId" }
$ids = @($meta.effects)
if ($ids.Count -eq 0) { throw "manifest.json effects[] is empty" }

$OutDir = Join-Path $RepoRoot "assets\vfx_portable\packs\$packId"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Resolve-Godot {
    if ($Godot -and (Test-Path $Godot)) { return $Godot }
    foreach ($name in @("godot", "godot4")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw "Set GODOT to Godot 4.7+ executable, or add godot to PATH"
}

$GodotBin = Resolve-Godot
$outGodot = $OutDir -replace '\\', '/'

Write-Host "pack=$packId effects=$($ids.Count)"
Write-Host "out=$OutDir"

$argList = @(
    "--headless", "--no-header", "--path", $PixelfxGodot,
    "-s", "res://tools/cli.gd", "--",
    "sheets"
) + $ids + @("--spriteframes", "--out", $outGodot)

& $GodotBin @argList
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Done. Copy packs/$packId/ to any Godot project (no pixelfx plugin)."