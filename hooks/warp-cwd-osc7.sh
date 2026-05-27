#!/usr/bin/env bash
# Tell Warp when an agent changes its working directory mid-session.
#
# Warp updates tab metadata, git branch, diff chips, and file explorer cwd from
# OSC 7 terminal sequences. Agent hooks cannot rely on /dev/tty, so this script
# walks up the process tree to the owning Warp PTY and writes the OSC 7 sequence
# there. It accepts either a path argument or hook JSON on stdin.

set -euo pipefail

if [ "$#" -gt 0 ]; then
  cwd="${1:-}"
elif [ -t 0 ]; then
  cwd=""
else
  input=$(cat)
  cwd=$(printf '%s' "$input" | jq -r '.new_cwd // .worktree_path // .cwd // empty' 2>/dev/null || true)
fi

if [ -z "${cwd:-}" ] || [ ! -d "$cwd" ]; then
  exit 0
fi

host=$(hostname 2>/dev/null || true)
if [ -z "$host" ]; then
  exit 0
fi

encoded_path=$(
  jq -rn --arg path "$cwd" '
    $path
    | split("/")
    | map(@uri)
    | join("/")
  '
)

if [ -z "$encoded_path" ]; then
  exit 0
fi

pty="${WARP_CWD_OSC7_TTY:-}"
if [ -z "$pty" ]; then
  pid=$$
  for _ in $(seq 1 16); do
    tty_name=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
      pty="/dev/$tty_name"
      break
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    if [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ]; then
      break
    fi
  done
fi

if [ -n "$pty" ] && [ -w "$pty" ]; then
  printf '\033]7;file://%s%s\a' "$host" "$encoded_path" > "$pty"
fi

exit 0
