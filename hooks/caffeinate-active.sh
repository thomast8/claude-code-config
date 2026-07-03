#!/usr/bin/env bash
# Keep the Mac awake only while Claude Code is actively working a turn, and
# only while on AC power.
#
# UserPromptSubmit runs `start`: do an immediate synchronous power check,
# then spawn a background watcher (this same script re-invoked with an
# internal `__watch` mode) that polls power state every
# CLAUDE_CAFFEINATE_POLL_SECS (default 30s) for the rest of the turn,
# starting/stopping `caffeinate -i -w <claude_pid> -t 3600` to keep it in
# sync with AC vs battery. Stop runs `stop`: kill the watcher and any live
# caffeinate. The -w releases the assertion if the claude process dies
# mid-turn; the -t is a dead-man's switch for interrupted turns (the Stop
# hook does not fire on user interrupts), and the watcher enforces the same
# deadline itself since a bare polling loop has no -w of its own.
#
# The watcher is re-exec'd as its own top-level process (`"$0" __watch ...`)
# rather than backgrounded as a shell function, because macOS ships bash 3.2
# (no $BASHPID), where a backgrounded function can't reliably learn its own
# PID to verify it still owns the watcherfile. A fresh process's $$ is
# always correct.
#
# `start`/`stop` rederive the owning claude PID by walking the process tree
# (same technique as warp-cwd-osc7.sh), so no state is shared between hook
# invocations and concurrent sessions each get their own caffeinate, watcher,
# and PID file.
#
# The pidfile holds "<state> <turn_epoch>", where <state> is either the
# caffeinate PID or the literal "battery" (suppressed, on battery power).
# The epoch is captured once at turn start and never changes across
# AC/battery flips, so the status line's elapsed-time counter stays
# anchored to turn start rather than resetting on every rewrite.

set -euo pipefail

mode="${1:-}"

if [ "$mode" = "__watch" ]; then
  claude_pid="$2"
  epoch="$3"
else
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
fi

pidfile="/tmp/claude-caffeinate-${claude_pid}.pid"
watcherfile="/tmp/claude-caffeinate-watcher-${claude_pid}.pid"
POLL_SECS="${CLAUDE_CAFFEINATE_POLL_SECS:-30}"
MAX_TURN_SECS=3600

on_ac_power() { pmset -g batt | head -1 | grep -q "AC Power"; }

start_caffeinate() {  # $1 = turn epoch
  caffeinate -i -w "$claude_pid" -t "$MAX_TURN_SECS" >/dev/null 2>&1 </dev/null &
  echo "$! $1" > "$pidfile"
}

kill_caffeinate() {
  local state _rest
  state=""
  [ -f "$pidfile" ] && { read -r state _rest < "$pidfile" 2>/dev/null || state=""; }
  case "$(ps -o comm= -p "${state:-0}" 2>/dev/null)" in
    *caffeinate*) kill "$state" 2>/dev/null || true ;;
  esac
}

kill_existing() {
  local w
  w=$(cat "$watcherfile" 2>/dev/null || true)
  case "$(ps -o command= -p "${w:-0}" 2>/dev/null)" in
    *caffeinate-active.sh*) kill "$w" 2>/dev/null || true ;;
  esac
  rm -f "$watcherfile"
  kill_caffeinate
  rm -f "$pidfile"
}

reconcile() {  # $1 = turn epoch; enforce: caffeinate alive iff on AC
  local state _rest
  state=""
  [ -f "$pidfile" ] && { read -r state _rest < "$pidfile" 2>/dev/null || state=""; }
  if on_ac_power; then
    if ! ps -o comm= -p "${state:-0}" 2>/dev/null | grep -q caffeinate; then
      start_caffeinate "$1"
    fi
  else
    if [ "$state" != "battery" ]; then
      kill_caffeinate
      echo "battery $1" > "$pidfile"
    fi
  fi
}

case "$mode" in
  start)
    kill_existing
    epoch=$(date +%s)
    reconcile "$epoch"
    bash "$0" __watch "$claude_pid" "$epoch" >/dev/null 2>&1 </dev/null &
    echo $! > "$watcherfile"
    ;;
  stop)
    kill_existing
    ;;
  __watch)
    deadline=$(( epoch + MAX_TURN_SECS ))
    while sleep "$POLL_SECS"; do
      [ "$(cat "$watcherfile" 2>/dev/null)" = "$$" ] || exit 0
      if ! kill -0 "$claude_pid" 2>/dev/null || [ "$(date +%s)" -ge "$deadline" ]; then
        kill_caffeinate
        rm -f "$pidfile" "$watcherfile"
        exit 0
      fi
      reconcile "$epoch"
    done
    ;;
esac

exit 0
