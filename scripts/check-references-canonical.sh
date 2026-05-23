#!/usr/bin/env bash
# check-references-canonical.sh — advisory drift report between the canonical
# story-setup reference files and the per-skill copies in sibling skills.
#
# Sibling copies are intentionally allowed to diverge (see
# skills/story-setup/references/agent-references/README.md). This script prints
# a diff summary so maintainers can review whether each divergence is on purpose.
#
# Always exits 0. Not a CI gate.
#
# Usage: bash scripts/check-references-canonical.sh [--verbose]
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

CANONICAL_DIR="skills/story-setup/references/agent-references"
SIBLING_SKILLS=(
  story-long-write
  story-deslop
  story-review
  story-short-analyze
  story-short-write
)

VERBOSE=0
if [ "${1:-}" = "--verbose" ]; then VERBOSE=1; fi

if [ ! -d "$CANONICAL_DIR" ]; then
  echo "[check-refs] canonical dir missing: $CANONICAL_DIR" >&2
  exit 0
fi

total=0
identical=0
drifted=0
missing=0

for canonical in "$CANONICAL_DIR"/*.md; do
  [ -f "$canonical" ] || continue
  fname="$(basename "$canonical")"
  case "$fname" in README.md) continue ;; esac

  for skill in "${SIBLING_SKILLS[@]}"; do
    sibling="skills/$skill/references/$fname"
    if [ ! -f "$sibling" ]; then
      missing=$((missing + 1))
      [ "$VERBOSE" = 1 ] && echo "  - missing: $sibling (canonical exists, sibling does not)"
      continue
    fi
    total=$((total + 1))
    if cmp -s "$canonical" "$sibling"; then
      identical=$((identical + 1))
    else
      drifted=$((drifted + 1))
      echo "[drift] $sibling vs $canonical"
      if [ "$VERBOSE" = 1 ]; then
        diff -u "$canonical" "$sibling" | head -40 | sed 's/^/    /'
        echo
      fi
    fi
  done
done

echo
echo "[check-refs] summary: $identical identical, $drifted drifted, $missing canonical-only (sibling missing) across $total comparisons"
echo "[check-refs] note: drifts may be intentional skill-specific customizations. See $CANONICAL_DIR/README.md."
exit 0
