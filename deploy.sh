#!/usr/bin/env bash
set -euo pipefail
ORG_ALIAS="${1:-scenarioforge-dev}"
ROLE="${2:-ScenarioForge_Admin}"
echo "Deploying ScenarioForge v3.0.0 to ${ORG_ALIAS}..."
sf project deploy start --target-org "$ORG_ALIAS" --source-dir force-app
sf org assign permset --name "$ROLE" --target-org "$ORG_ALIAS"
echo "ScenarioForge deployed. Assigned permission set: ${ROLE}"
