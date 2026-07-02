#!/usr/bin/env bash
# Keep the Mac awake only while Claude Code is actively working a turn.
#
# UserPromptSubmit runs `start`: spawn `caffeinate -i -w <claude_pid> -t 3600`.
# Stop runs `stop`: kill it. The -w releases the assertion if the claude
# process dies mid-turn; the -t is a dead-man's switch for interrupted turns
# (the Stop hook does not fire on user interrupts). Both invocations rederive
# the owning claude PID by walking the process tree (same technique as
# warp-cwd-osc7.sh), so no state is shared between hook invocations and
# concurrent sessions each get their own caffeinate and PID file.

set -euo pipefail

mode="${1:-}"

pid=$$
claude_pid=""
for _ in $(seq 1 16); do
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
  if [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ]; then
    break
  fi
  args=$(ps -o command= -p "$pid" 2>/dev/null || true)
  case "$args" in
    claude|claude\ *|*/claude|*/claude\ *|*share/claude/versions/*)
      claude_pid="$pid"
      break
      ;;
  esac
done

if [ -z "$claude_pid" ]; then
  exit 0
fi

pidfile="/tmp/claude-caffeinate-${claude_pid}.pid"

kill_existing() {
  local old
  old=$(cat "$pidfile" 2>/dev/null || true)
  case "$(ps -o comm= -p "${old:-0}" 2>/dev/null)" in
    *caffeinate*) kill "$old" 2>/dev/null || true ;;
  esac
  rm -f "$pidfile"
}

case "$mode" in
  start)
    kill_existing
    caffeinate -i -w "$claude_pid" -t 3600 >/dev/null 2>&1 </dev/null &
    echo $! > "$pidfile"
    ;;
  stop)
    kill_existing
    ;;
esac

exit 0
