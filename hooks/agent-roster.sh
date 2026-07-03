#!/usr/bin/env bash
# Keep resumable sub-agent IDs visible across compaction.
#
# Compaction drops spawned-agent IDs from the model's live context; without them
# the model re-spawns a fresh consultant instead of SendMessage-resuming the one
# that already holds the brief (wasting its accumulated reasoning and paying to
# rebuild context). This hook rebuilds the roster from the on-disk transcript
# plus the subagent meta files (both survive compaction) and re-injects it:
#   - SessionStart: fires on the "compact" source for both auto and manual
#     compaction, so the roster lands in the fresh post-compaction context.
#   - UserPromptSubmit: backstop for the "model stopped, user returns after a
#     compaction" ordering, where the injected text lands post-compaction.
# Wired to both in settings.json. PostToolUse[Agent] is also wired so the state
# file refreshes the instant an agent is spawned.
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
  subagents_dir="${TRANSCRIPT_PATH%.jsonl}/subagents"
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0

  # agentId + human description + latest timestamp from the transcript. The
  # launch record carries agentId/description reliably; agentType does not
  # appear there for background agents, so it is enriched from meta.json below.
  base_file="${STATE_FILE}.base.$$"
  jq -c -s '
    [
      .[]
      | select(.toolUseResult.agentId? != null)
      | {
          agentId: .toolUseResult.agentId,
          timestamp: (.timestamp // ""),
          description: (.toolUseResult.description // "" | gsub("[\t\r\n]+"; " ") | .[0:180])
        }
    ]
    | group_by(.agentId)
    | map({
        agentId: .[0].agentId,
        timestamp: ([.[].timestamp] | max),
        description: ([.[].description] | map(select(length > 0)) | (.[0] // ""))
      })
    | sort_by(.timestamp)
    | .[]
  ' "$TRANSCRIPT_PATH" > "$base_file" 2>/dev/null || { rm -f "$base_file"; return 0; }
  [ -s "$base_file" ] || { rm -f "$base_file"; return 0; }

  # Enrich agentType from each agent's meta.json and drop the kinds not worth
  # resuming: one-shot Explore searches, forks, and empty/placeholder spawns.
  # (if/[ ] tests, not case, to avoid a bash 3.2 parser bug with ) patterns.)
  lines_file="${STATE_FILE}.lines.$$"
  : > "$lines_file"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    aid=$(printf '%s' "$row" | jq -r '.agentId' 2>/dev/null || true)
    [ -n "$aid" ] || continue
    # Transcript description is a fallback; meta.json is authoritative and also
    # covers foreground agents, whose completion record carries no description.
    desc=$(printf '%s' "$row" | jq -r '.description' 2>/dev/null || true)

    meta="${subagents_dir}/agent-${aid}.meta.json"
    atype="agent"
    isfork="false"
    if [ -f "$meta" ]; then
      atype=$(jq -r '.agentType // "agent"' "$meta" 2>/dev/null || echo agent)
      isfork=$(jq -r '(.isFork // false) | tostring' "$meta" 2>/dev/null || echo false)
      mdesc=$(jq -r '.description // ""' "$meta" 2>/dev/null || true)
      [ -n "$mdesc" ] && desc="$mdesc"
    fi
    [ "$atype" = "Explore" ] && continue
    [ "$isfork" = "true" ] && continue
    [ -z "$desc" ] && continue
    [ "$desc" = "placeholder" ] && continue

    printf '%s' "$row" | jq -c --arg t "$atype" --arg d "$desc" '. + {agentType: $t, description: $d}' >> "$lines_file" 2>/dev/null || true
  done < "$base_file"

  tmp_file="${STATE_FILE}.$$"
  if [ -s "$lines_file" ]; then
    jq -s '.' "$lines_file" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$STATE_FILE"
  fi
  rm -f "$base_file" "$lines_file" "$tmp_file"
}

print_roster() {
  [ -s "$STATE_FILE" ] || return 0

  count=$(jq 'length' "$STATE_FILE" 2>/dev/null || echo 0)
  [ "$count" -gt 0 ] 2>/dev/null || return 0

  echo '## Resumable agent roster (survives compaction)'
  echo 'You spawned these agents earlier this session. Compaction can hide their IDs from the visible transcript. To continue one with its full context intact, SendMessage to its agentId below instead of spawning a fresh agent of the same kind; if the resume fails (agent dead or errored), spawn fresh.'
  jq -r '
    .[-6:][]
    | "- \(.agentType) — \(.description)\n  SendMessage to=\"\(.agentId)\", summary=\"<5-10 word recap>\", message=\"<only the new delta>\""
  ' "$STATE_FILE" 2>/dev/null
}

# Refresh the cached roster on session start and whenever an agent is spawned
# (PostToolUse[Agent]); UserPromptSubmit only prints the cache, to avoid
# re-slurping a multi-megabyte transcript on every prompt.
case "$EVENT" in
  UserPromptSubmit) : ;;
  *) refresh_roster ;;
esac

case "$EVENT" in
  SessionStart|UserPromptSubmit)
    print_roster
    ;;
esac

exit 0
