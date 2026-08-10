#!/usr/bin/env bash
set -euo pipefail

ORG_ALIAS="${1:-}"
if [[ -z "$ORG_ALIAS" ]]; then
  echo "Usage: ./install.sh <salesforce-org-alias>"
  echo "Example: ./install.sh my-sandbox"
  exit 1
fi

if ! command -v sf >/dev/null 2>&1; then
  echo "ERROR: Salesforce CLI (sf) is not installed or not on PATH."
  echo "Install it from https://developer.salesforce.com/tools/salesforcecli and try again."
  exit 1
fi

printf '\nScenarioForge v3.0.0 — Quick Install\n'
printf 'Target org: %s\n\n' "$ORG_ALIAS"

echo "[1/4] Verifying org authentication..."
if ! sf org display --target-org "$ORG_ALIAS" >/dev/null 2>&1; then
  echo "Org alias '$ORG_ALIAS' is not authenticated. Opening Salesforce login..."
  sf org login web --alias "$ORG_ALIAS"
fi

echo "[2/4] Deploying Salesforce metadata..."
sf project deploy start --target-org "$ORG_ALIAS" --manifest manifest/package.xml --wait 30

echo "[3/4] Assigning ScenarioForge Admin permission set to the current user..."
sf org assign permset --name ScenarioForge_Admin --target-org "$ORG_ALIAS"

echo "[4/4] Installing the guided starter pack..."
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/installStarterPack.apex

printf '\nScenarioForge is installed.\n'
printf 'Open Salesforce and launch: App Launcher > ScenarioForge\n'
printf 'Or run: sf org open --target-org %s\n\n' "$ORG_ALIAS"
