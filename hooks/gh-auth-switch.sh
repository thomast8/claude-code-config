#!/usr/bin/env bash
# Auto-switch gh CLI account based on repo remote owner BEFORE git/gh commands.
# Runs as a PreToolUse hook on Bash commands matching git push / gh.
# Default account is personal; an optional work map (installed by `setup --with-work`
# at ~/.config/claude/gh-work-map, lines of "owner account") overrides specific orgs.

# Read tool input from stdin (Claude Code passes it as JSON via stdin)
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if ! echo "$CMD" | grep -qE '(git\s+push|^gh\s|&&\s*gh\s|\|\s*gh\s)'; then
    exit 0
fi

remote_url=$(git remote get-url origin 2>/dev/null) || exit 0

# Extract owner from HTTPS or SSH URLs
# https://github.com/OWNER/REPO.git  or  git@github.com:OWNER/REPO.git
owner=$(echo "$remote_url" | sed -E 's#.*(github\.com[:/])([^/]+)/.*#\2#')
[ -z "$owner" ] && exit 0

target="@@GH_USER@@"
# Work layer (optional): map specific orgs to a work account.
work_map="$HOME/.config/claude/gh-work-map"
if [ -f "$work_map" ]; then
    w=$(awk -v o="$owner" '$1==o {print $2; exit}' "$work_map")
    [ -n "$w" ] && target="$w"
fi

# Check current active account, skip switch if already correct
current=$(gh auth status 2>&1 | grep "Active account: true" -B3 | grep "account " | sed -E 's/.*account ([^ ]+).*/\1/')
if [ "$current" = "$target" ]; then
    exit 0
fi

gh auth switch --user "$target" 2>/dev/null
echo "gh: switched to $target (repo owner: $owner)"
