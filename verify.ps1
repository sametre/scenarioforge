param([Parameter(Mandatory=$true)][string]$OrgAlias)
$ErrorActionPreference = "Stop"
Write-Host "Running ScenarioForge Apex tests in $OrgAlias..." -ForegroundColor Cyan
sf apex run test --target-org $OrgAlias --tests ScenarioForgeRunnerTest --tests ScenarioForgeServiceTest --tests ScenarioForgeValidatorTest --tests ScenarioForgeSuiteServiceTest --tests ScenarioForgeOnboardingServiceTest --result-format human --code-coverage --wait 20
