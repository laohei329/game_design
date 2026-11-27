# Push this repo to GitHub (account laohei329). Run after: gh auth login
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$gh = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { $gh = "gh" }

& $gh auth status
if ($LASTEXITCODE -ne 0) {
    Write-Host "Run: gh auth login -h github.com -p https -w"
    exit 1
}

$repoName = if ($args.Count -gt 0) { $args[0] } else { "game_design" }
$vis = if ($args.Count -gt 1) { $args[1] } else { "public" }

if (-not (git remote get-url origin 2>$null)) {
    & $gh repo create $repoName --$vis --description "Doomsday Train — design docs, sim, Godot client" --source=. --remote=origin
}
git push -u origin main
Write-Host "Done: https://github.com/laohei329/$repoName"