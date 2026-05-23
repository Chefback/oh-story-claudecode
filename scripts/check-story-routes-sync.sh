#!/usr/bin/env bash
# check-story-routes-sync.sh — verifies skills/story/SKILL.md frontmatter routes
# stays in sync with the body 路由表 + each skill/agent target actually exists.
#
# Exit codes:
#   0 — frontmatter and body table agree, all targets resolve
#   1 — frontmatter parse error, mismatch, or unresolved target
#
# Usage: bash scripts/check-story-routes-sync.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

SKILL_MD="skills/story/SKILL.md"
AGENT_DIR="skills/story-setup/references/templates/agents"

if [ ! -f "$SKILL_MD" ]; then
  echo "[check-story-routes] error: $SKILL_MD missing" >&2
  exit 1
fi

python3 - "$SKILL_MD" "$AGENT_DIR" <<'PY'
import re
import sys
from pathlib import Path

skill_md = Path(sys.argv[1])
agent_dir = Path(sys.argv[2])
text = skill_md.read_text(encoding="utf-8")

# Split frontmatter / body
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, flags=re.DOTALL)
if not m:
    sys.exit("[check-story-routes] error: SKILL.md missing frontmatter")
fm_text, body = m.group(1), m.group(2)

try:
    import yaml
except ImportError:
    sys.exit("[check-story-routes] error: PyYAML missing — pip install pyyaml")

fm = yaml.safe_load(fm_text) or {}
routes = fm.get("routes")
if not isinstance(routes, list):
    sys.exit("[check-story-routes] error: frontmatter has no `routes:` list")
if len(routes) < 12:
    sys.exit(f"[check-story-routes] error: routes count {len(routes)} < 12")

# Validate each route has intent + (skill OR agent) + triggers
errs = []
fm_intents = []
for i, r in enumerate(routes):
    if not isinstance(r, dict):
        errs.append(f"route #{i}: not a mapping")
        continue
    intent = r.get("intent")
    if not intent:
        errs.append(f"route #{i}: missing intent")
        continue
    fm_intents.append(intent)
    triggers = r.get("triggers")
    if not isinstance(triggers, list) or not triggers:
        errs.append(f"route '{intent}': missing/empty triggers")
    skill = r.get("skill")
    agent = r.get("agent")
    if not (skill or agent):
        errs.append(f"route '{intent}': must have skill or agent")
    if skill and not (Path("skills") / skill).is_dir():
        errs.append(f"route '{intent}': skill '{skill}' dir missing")
    if agent and not (agent_dir / f"{agent}.md").is_file():
        errs.append(f"route '{intent}': agent '{agent}' template missing")

# Parse body table — every | row whose first cell is in fm intents
body_intents = []
for line in body.splitlines():
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 3:
        continue
    first = cells[0]
    # Skip header + separator
    if first in {"用户意图", ""} or set(first) <= set("-: "):
        continue
    body_intents.append(first)

# Body table 应 1:1 镜像 frontmatter
fm_set = set(fm_intents)
body_set = set(body_intents)
only_fm = fm_set - body_set
only_body = body_set - fm_set
if only_fm:
    errs.append(f"intents in frontmatter but not body table: {sorted(only_fm)}")
if only_body:
    errs.append(f"intents in body table but not frontmatter: {sorted(only_body)}")

if errs:
    for e in errs:
        print(f"[check-story-routes] {e}", file=sys.stderr)
    sys.exit(1)

print(f"[check-story-routes] OK: {len(routes)} routes (frontmatter ↔ body table in sync)")
PY
