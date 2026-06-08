#!/usr/bin/env bash
# SessionStart hook: a compact, always-fresh snapshot of the worktree's state so a
# new session knows where it stands without digging - branch, divergence from the
# upstream (the "am I on stale code?" signal a static file could never keep honest),
# recent commits, uncommitted changes, and the PR this branch belongs to when it can
# be resolved. Everything here is recomputed at launch; nothing is persisted, so
# nothing can go stale.
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

echo '## Current State'
branch="$(git branch --show-current 2>/dev/null)"
echo "Branch: ${branch:-<detached HEAD>}"

# Divergence vs the upstream tracking ref. A behind-count flags a reused worktree
# whose remote moved (the stale-PR trap); an ahead-count flags unpushed local work.
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -n "$upstream" ]; then
  set -- $(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null || echo 0 0)
  behind="${1:-0}"; ahead="${2:-0}"
  if [ "$behind" -gt 0 ] || [ "$ahead" -gt 0 ]; then
    echo "Vs $upstream: $behind behind, $ahead ahead"
  else
    echo "Vs $upstream: up to date"
  fi
fi

# Best-effort PR context (number / title / base branch). Bounded by a timeout so a
# slow or unauthenticated gh call can never stall session start; skipped silently
# when gh, a timeout binary, or a matching PR isn't available.
tmo=""
command -v timeout  >/dev/null 2>&1 && tmo="timeout 3"
command -v gtimeout >/dev/null 2>&1 && tmo="gtimeout 3"
if [ -n "$tmo" ] && command -v gh >/dev/null 2>&1; then
  pr="$($tmo gh pr view --json number,title,baseRefName \
        -q 'if .number then "PR #\(.number): \(.title)  (base: \(.baseRefName))" else empty end' \
        2>/dev/null || true)"
  [ -n "${pr:-}" ] && echo "$pr"
fi

echo ''
echo '## Recent commits:'
git log --oneline -5 2>/dev/null

changed="$(git diff --stat HEAD 2>/dev/null || true)"
if [ -n "$changed" ]; then
  echo ''
  echo '## Uncommitted changes:'
  echo "$changed"
fi
