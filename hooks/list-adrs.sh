#!/usr/bin/env bash
# Lists every ADR of a git repo, one path per line, relative to the repo root.
# Usage: list-adrs.sh [dir-inside-repo] [--module <Name>]
#
# Only tracked files are listed, so nested worktrees and untracked checkouts
# of the same repo never show up as duplicates. Matching is case-insensitive:
# .ai/ADR/, docs/adr/, doc/adrs/, docs/decisions/ all count.
set -euo pipefail

dir="."
module=""
while [ $# -gt 0 ]; do
  case "$1" in
    --module) module="${2:-}"; shift 2 ;;
    *) dir="$1"; shift ;;
  esac
done

root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0

git -C "$root" ls-files \
  | grep -Ei '(^|/)(adrs?|decisions)/[^/]*\.md$' \
  | grep -Eiv '(^|/)(_?templates?)/|(^|/)(readme|template)\.md$' \
  | { if [ -n "$module" ]; then grep -E "(^|/)${module}/" || true; else cat; fi; }
