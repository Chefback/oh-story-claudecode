#!/usr/bin/env bash
# Dev-mode bootstrap for contributors developing the story-* skills.
#
# Renders the story-setup skill's agent templates + agent-references into the
# repository's local .claude/ so agent prose can resolve <<STORY_REF>>/X.md
# without going through /story-setup. Idempotent: run as often as you like.
#
# Usage: bash scripts/dev-setup.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

SRC_REFS="skills/story-setup/references/agent-references"
SRC_AGENTS="skills/story-setup/references/templates/agents"
DST_REFS=".claude/agent-references"
DST_AGENTS=".claude/agents"

if [ ! -d "$SRC_REFS" ] || [ ! -d "$SRC_AGENTS" ]; then
  echo "[dev-setup] error: missing $SRC_REFS or $SRC_AGENTS — run from repo root" >&2
  exit 1
fi

mkdir -p "$DST_REFS" "$DST_AGENTS"

# Copy reference files (skip _attic archive)
copied_refs=0
for f in "$SRC_REFS"/*.md; do
  [ -f "$f" ] || continue
  cp "$f" "$DST_REFS/"
  copied_refs=$((copied_refs + 1))
done

# Render agent templates: substitute <<STORY_REF>> with the local refs dir.
# Templates without the placeholder are copied verbatim (v8 transitional state).
rendered_agents=0
for f in "$SRC_AGENTS"/*.md; do
  [ -f "$f" ] || continue
  sed 's|<<STORY_REF>>|.claude/agent-references|g' "$f" > "$DST_AGENTS/$(basename "$f")"
  rendered_agents=$((rendered_agents + 1))
done

# Fail loudly if any unresolved placeholders leaked through
if grep -rln '<<STORY_REF>>' "$DST_AGENTS/" >/dev/null 2>&1; then
  echo "[dev-setup] error: unresolved <<STORY_REF>> placeholders in $DST_AGENTS/" >&2
  grep -rln '<<STORY_REF>>' "$DST_AGENTS/" >&2
  exit 2
fi

echo "[dev-setup] refs:   $copied_refs files in $DST_REFS"
echo "[dev-setup] agents: $rendered_agents files in $DST_AGENTS"
echo "[dev-setup] done. To install git hooks: bash scripts/install-hooks.sh"
