#!/usr/bin/env bash
set -euo pipefail
ORG_ALIAS="${1:-}"
if [[ -z "$ORG_ALIAS" ]]; then
  echo "Usage: ./verify.sh <salesforce-org-alias>"
  exit 1
fi

echo "Running ScenarioForge Apex tests in $ORG_ALIAS..."
sf apex run test \
  --target-org "$ORG_ALIAS" \
  --tests ScenarioForgeRunnerTest \
  --tests ScenarioForgeServiceTest \
  --tests ScenarioForgeValidatorTest \
  --tests ScenarioForgeSuiteServiceTest \
  --tests ScenarioForgeOnboardingServiceTest \
  --result-format human \
  --code-coverage \
  --wait 20
