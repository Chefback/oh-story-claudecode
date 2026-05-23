#!/usr/bin/env bash
# cache-write.sh — atomic CHAPTER_META cache writer for /story-review Phase 2A.
#
# Each Phase 2A agent should pipe its CHAPTER_META JSON to this script.
# The script writes to .omc/review-cache/<hash>.json.tmp then atomically
# renames to .omc/review-cache/<hash>.json, and refuses to write when a
# concurrent .tmp file is already present (another /story-review run
# overlapping in the same project).
#
# Usage:
#   cat chapter_meta.json | bash scripts/cache-write.sh <chapter_hash>
#   bash scripts/cache-write.sh <chapter_hash> < chapter_meta.json
#
# Exit codes:
#   0 — written atomically
#   1 — concurrent write detected (existing .tmp); user must resolve
#   2 — usage error or invalid JSON
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "[cache-write] usage: cache-write.sh <chapter_hash> (JSON on stdin)" >&2
  exit 2
fi

HASH="$1"
if ! printf '%s' "$HASH" | grep -qE '^[A-Za-z0-9_.-]+$'; then
  echo "[cache-write] error: hash must match [A-Za-z0-9_.-]+, got: $HASH" >&2
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CACHE_DIR="$REPO_ROOT/.omc/review-cache"
mkdir -p "$CACHE_DIR"

FINAL="$CACHE_DIR/${HASH}.json"
TMP="$CACHE_DIR/${HASH}.json.tmp"

# Concurrent-write guard: if .tmp already exists, another /story-review
# is writing this same cache key. Refuse rather than clobber.
if [ -e "$TMP" ]; then
  echo "[cache-write] error: $TMP already exists (concurrent write in progress)" >&2
  echo "  Resolve: rm '$TMP' after confirming no other /story-review is running, then retry." >&2
  exit 1
fi

# Buffer stdin, validate JSON, then atomic write.
TMP_BUFFER=$(mktemp)
trap 'rm -f "$TMP_BUFFER"' EXIT
cat > "$TMP_BUFFER"

if ! python3 -c "import json, sys; json.load(open('$TMP_BUFFER'))" 2>/dev/null; then
  echo "[cache-write] error: stdin is not valid JSON" >&2
  exit 2
fi

# Move buffered JSON to .tmp, then rename. mv on the same filesystem is atomic on POSIX.
mv "$TMP_BUFFER" "$TMP"
mv "$TMP" "$FINAL"
trap - EXIT

echo "[cache-write] $FINAL"
