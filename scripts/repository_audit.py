from pathlib import Path
import json
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
errors = []

for path in (ROOT / "force-app").rglob("*.xml"):
    try:
        ET.parse(path)
    except Exception as exc:
        errors.append(f"Invalid XML: {path.relative_to(ROOT)}: {exc}")

for rel in ["sfdx-project.json", "package.json", "config/project-scratch-def.json"]:
    try:
        json.loads((ROOT / rel).read_text())
    except Exception as exc:
        errors.append(f"Invalid JSON: {rel}: {exc}")

required = [
    "README.md", "LICENSE",
    "force-app/main/default/classes/ScenarioForgeRunner.cls",
    "force-app/main/default/classes/ScenarioForgeValidator.cls",
    "force-app/main/default/classes/ScenarioForgeSuiteQueueable.cls",
    "force-app/main/default/classes/ScenarioForgeOnboardingService.cls",
    "force-app/main/default/lwc/scenarioForgeApp/scenarioForgeApp.js",
    "force-app/main/default/lwc/scenarioForgeOnboarding/scenarioForgeOnboarding.js",
    "install.sh", "install.ps1", "verify.sh", "verify.ps1",
]
for rel in required:
    if not (ROOT / rel).exists():
        errors.append(f"Missing required repository file: {rel}")

for path in ROOT.rglob("*"):
    if not path.is_file() or ".git" in path.parts or "node_modules" in path.parts:
        continue
    if path.suffix.lower() in {".pem", ".key", ".p12", ".pfx"} or path.name == ".env":
        errors.append(f"Potential credential file committed: {path.relative_to(ROOT)}")

apex = "\n".join(p.read_text(errors="ignore") for p in (ROOT / "force-app").rglob("*.cls"))
for pattern, label in [(r"(?i)password\s*=\s*['\"]", "hard-coded password"), (r"(?i)bearer\s+[A-Za-z0-9._-]{20,}", "bearer token")]:
    if re.search(pattern, apex):
        errors.append(f"Potential {label} detected in Apex source")

if errors:
    print("Repository audit failed:")
    for error in errors:
        print(f" - {error}")
    sys.exit(1)
print("ScenarioForge repository audit passed.")
