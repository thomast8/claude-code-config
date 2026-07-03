#!/usr/bin/env bash
# Claude Code status line: model + context-usage bar.
# Git branch / worktree / PR state lives in Warp's vertical-tab metadata, so it
# is intentionally omitted here to avoid duplicating what the terminal shows.
input=$(cat)

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
GRAY='\033[90m'
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

# Caffeinate indicator (see hooks/caffeinate-active.sh):
#   ☕ m:ss  turn active, caffeinate holding the Mac awake (AC power)
#   🔋 m:ss  turn active, caffeinate suppressed because on battery
#   (empty)  no turn in progress
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
  caff_state=""
  [ -f "$pidfile" ] && { read -r caff_state caff_epoch < "$pidfile" 2>/dev/null || caff_state=""; }
  if [ -n "$caff_state" ] && [ -n "${caff_epoch:-}" ] && [ "$caff_epoch" -gt 0 ] 2>/dev/null; then
    elapsed=$(( $(date +%s) - caff_epoch ))
    [ "$elapsed" -lt 0 ] && elapsed=0
    printf -v elapsed_fmt '%d:%02d' $((elapsed / 60)) $((elapsed % 60))
    if [ "$caff_state" = "battery" ]; then
      caffeinate_indicator=" ${GRAY}🔋${elapsed_fmt}${RESET}"
    elif ps -o comm= -p "$caff_state" 2>/dev/null | grep -q caffeinate; then
      caffeinate_indicator=" ${YELLOW}☕${elapsed_fmt}${RESET}"
    fi
  fi
fi

echo -e "${CYAN}${model} ${BAR_COLOR}${bar}${RESET} ${CYAN}${pct}%${RESET}${caffeinate_indicator}"
