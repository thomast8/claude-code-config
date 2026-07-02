#!/usr/bin/env bash
# Claude Code status line: model + context-usage bar.
# Git branch / worktree / PR state lives in Warp's vertical-tab metadata, so it
# is intentionally omitted here to avoid duplicating what the terminal shows.
input=$(cat)

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Model (strip trailing context window annotation like " (1M context)")
model=$(echo "$input" | jq -r 'if .model | type == "object" then .model.display_name // .model.id // empty else .model // empty end' | sed 's/ ([0-9]*[KMB] context)//g')

# Context bar
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[ -z "$pct" ] || [ "$pct" = "null" ] && pct=0
if [ "$pct" -ge 90 ] 2>/dev/null; then BAR_COLOR="$RED"
elif [ "$pct" -ge 70 ] 2>/dev/null; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

filled=$((pct / 10))
empty=$((10 - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

# Caffeinate indicator: elapsed time this turn has kept the Mac awake
# (see hooks/caffeinate-active.sh). Empty once the turn ends and the
# assertion is released, since there's nothing left to report.
caffeinate_indicator=""
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

if [ -n "$claude_pid" ]; then
  pidfile="/tmp/claude-caffeinate-${claude_pid}.pid"
  caff_pid=$(cat "$pidfile" 2>/dev/null || true)
  if [ -n "$caff_pid" ] && ps -o comm= -p "$caff_pid" 2>/dev/null | grep -q caffeinate; then
    started=$(stat -f %m "$pidfile" 2>/dev/null || echo 0)
    elapsed=$(( $(date +%s) - started ))
    [ "$elapsed" -lt 0 ] && elapsed=0
    printf -v elapsed_fmt '%d:%02d' $((elapsed / 60)) $((elapsed % 60))
    caffeinate_indicator=" ${YELLOW}☕${elapsed_fmt}${RESET}"
  fi
fi

echo -e "${CYAN}${model} ${BAR_COLOR}${bar}${RESET} ${CYAN}${pct}%${RESET}${caffeinate_indicator}"
