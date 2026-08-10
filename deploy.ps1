param([string]$OrgAlias = "scenarioforge-dev", [string]$Role = "ScenarioForge_Admin")
$ErrorActionPreference = "Stop"
Write-Host "Deploying ScenarioForge v3.0.0 to $OrgAlias..."
sf project deploy start --target-org $OrgAlias --source-dir force-app
sf org assign permset --name $Role --target-org $OrgAlias
Write-Host "ScenarioForge deployed. Assigned permission set: $Role"
