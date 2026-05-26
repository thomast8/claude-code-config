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

echo -e "${CYAN}${model} ${BAR_COLOR}${bar}${RESET} ${CYAN}${pct}%${RESET}"
