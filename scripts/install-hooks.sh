#!/usr/bin/env bash
# Point git at the repo's tracked hook directory so contributor checks (route
# schema sync, references canonical, etc.) run on `git commit` automatically.
#
# Usage: bash scripts/install-hooks.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "[install-hooks] error: not inside a git repository" >&2
  exit 1
fi
cd "$REPO_ROOT"

if [ ! -d scripts/git-hooks ]; then
  echo "[install-hooks] error: scripts/git-hooks/ does not exist" >&2
  exit 1
fi

git config core.hooksPath scripts/git-hooks/
echo "[install-hooks] core.hooksPath = $(git config core.hooksPath)"
echo "[install-hooks] done. To opt out later: git config --unset core.hooksPath"
