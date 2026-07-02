#!/usr/bin/env bash
# Keep resumable sub-agent IDs visible across compaction.
set -uo pipefail

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

[ -n "${SESSION_ID:-}" ] || exit 0
case "$SESSION_ID" in
  *[!A-Za-z0-9._-]*)
    exit 0
    ;;
esac

STATE_DIR="${HOME}/.claude/agent-rosters"
STATE_FILE="${STATE_DIR}/${SESSION_ID}.json"

derive_transcript_path() {
  [ -n "${TRANSCRIPT_PATH:-}" ] && [ -f "$TRANSCRIPT_PATH" ] && return 0
  [ -n "${CWD:-}" ] || return 1

  project_key=$(printf '%s' "$CWD" | sed 's#/#-#g')
  candidate="${HOME}/.claude/projects/${project_key}/${SESSION_ID}.jsonl"
  [ -f "$candidate" ] || return 1
  TRANSCRIPT_PATH="$candidate"
}

refresh_roster() {
  derive_transcript_path || return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  tmp_file="${STATE_FILE}.$$"

  jq -s '
    [
      .[]
      | select(.toolUseResult.agentId? != null)
      | {
          timestamp: (.timestamp // ""),
          cwd: (.cwd // ""),
          agentId: .toolUseResult.agentId,
          agentType: (.toolUseResult.agentType // "unknown"),
          status: (.toolUseResult.status // "completed"),
          summary: (
            .toolUseResult.prompt
            // .toolUseResult.content[0].text
            // ""
            | split("\n")[0]
            | gsub("[\t\r]+"; " ")
            | .[0:180]
          )
        }
    ]
    | group_by(.agentId)
    | map(max_by(.timestamp))
    | sort_by(.timestamp)
  ' "$TRANSCRIPT_PATH" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$STATE_FILE"
}

print_roster() {
  [ -s "$STATE_FILE" ] || return 0

  count=$(jq 'length' "$STATE_FILE" 2>/dev/null || echo 0)
  [ "$count" -gt 0 ] 2>/dev/null || return 0

  echo '## Active Agent Roster'
  echo 'Compaction can hide consultant IDs from the visible transcript. Before spawning a replacement consultant, resume the matching existing one with SendMessage using the exact agentId below; spawn fresh only if SendMessage is unavailable or fails.'
  jq -r '
    .[-8:][]
    | "- \(.agentType) \(.agentId) [\(.status)] \(.summary)\n  SendMessage: to=\"\(.agentId)\", summary=\"<5-10 word recap>\", content=\"<only the new delta>\""
  ' "$STATE_FILE" 2>/dev/null
}

refresh_roster

case "$EVENT" in
  PostCompact|SessionStart)
    print_roster
    ;;
esac

exit 0
