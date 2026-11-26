# Junction client/data -> repo data (run from game_design root)
$root = Split-Path -Parent $PSScriptRoot
$clientData = Join-Path $root "client\data"
$repoData = Join-Path $root "data"
if (Test-Path $clientData) {
    Write-Host "client/data already exists — remove or use existing copy"
    exit 1
}
cmd /c mklink /J "$clientData" "$repoData"
Write-Host "Linked client/data -> data"