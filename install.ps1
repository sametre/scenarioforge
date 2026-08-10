param(
    [Parameter(Mandatory=$true)][string]$OrgAlias
)
$ErrorActionPreference = "Stop"

if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    throw "Salesforce CLI (sf) is not installed or is not on PATH."
}

Write-Host "`nScenarioForge v3.0.0 - Quick Install" -ForegroundColor Cyan
Write-Host "Target org: $OrgAlias`n"

Write-Host "[1/4] Verifying org authentication..." -ForegroundColor Cyan
$orgCheck = sf org display --target-org $OrgAlias 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Org alias '$OrgAlias' is not authenticated. Opening Salesforce login..." -ForegroundColor Yellow
    sf org login web --alias $OrgAlias
}

Write-Host "[2/4] Deploying Salesforce metadata..." -ForegroundColor Cyan
sf project deploy start --target-org $OrgAlias --manifest manifest/package.xml --wait 30

Write-Host "[3/4] Assigning ScenarioForge Admin permission set..." -ForegroundColor Cyan
sf org assign permset --name ScenarioForge_Admin --target-org $OrgAlias

Write-Host "[4/4] Installing the guided starter pack..." -ForegroundColor Cyan
sf apex run --target-org $OrgAlias --file scripts/apex/installStarterPack.apex

Write-Host "`nScenarioForge is installed." -ForegroundColor Green
Write-Host "Open Salesforce and launch: App Launcher > ScenarioForge"
Write-Host "Or run: sf org open --target-org $OrgAlias`n"
