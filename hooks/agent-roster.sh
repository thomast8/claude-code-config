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
#     compaction" ordering. Prints only when PostCompact has left a marker for
#     this session (then clears it), so the roster is injected once per
#     compaction instead of bloating every prompt.
#   - PostCompact: output is ignored by the harness, but the hook still runs;
#     used purely as a side effect to set the marker UserPromptSubmit checks.
#   - PreToolUse[Agent]: guardrail, not injection. Denies spawning a second
#     fable-planner while the roster already holds one (the model must
#     SendMessage-resume it instead); the deny reason carries the exact resume
#     call. Bypass by putting "fresh-planner: forced" on its own line in the
#     Agent prompt (resume failed, or a genuinely unrelated new plan).
#     Known limitation: the roster only records a spawn after its tool call
#     completes, so two planner spawns dispatched in the same parallel batch
#     both pass the guard; the injected plan-mode policy is the only defense
#     against that ordering.
# All five events are wired in settings.json. PostToolUse[Agent] refreshes the
# state file the instant an agent is spawned.
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
COMPACT_MARKER="${STATE_DIR}/${SESSION_ID}.compacted"

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
  PreToolUse)
    # One fable-planner per session: a resumable planner already holds the
    # brief and its own reasoning, so a fresh spawn re-bills the whole brief
    # at Fable rates and loses that context. Deny and hand back the resume.
    subtype=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)
    [ "$subtype" = "fable-planner" ] || exit 0
    # The marker must stand on its own line (whitespace-trimmed exact match):
    # a substring test would be defeated by the prompt merely quoting or
    # negating the phrase in prose (e.g. an excerpt of this very script).
    if printf '%s' "$INPUT" | jq -e '(.tool_input.prompt // "") | split("\n") | any(gsub("^[[:space:]]+|[[:space:]]+$"; "") == "fresh-planner: forced")' >/dev/null 2>&1; then
      exit 0
    fi
    [ -s "$STATE_FILE" ] || exit 0
    existing=$(jq -r '[.[] | select(.agentType == "fable-planner")] | last | .agentId // empty' "$STATE_FILE" 2>/dev/null || true)
    [ -n "$existing" ] || exit 0
    existing_desc=$(jq -r --arg id "$existing" '[.[] | select(.agentId == $id)] | last | .description // ""' "$STATE_FILE" 2>/dev/null || true)
    reason="A fable-planner already exists in this session: agentId ${existing} (\"${existing_desc}\"). Do not spawn a replacement - resume it, it still holds the full brief and its own reasoning. If SendMessage is not loaded yet, load it first with ToolSearch (query \"select:SendMessage\"), then call SendMessage with to: \"${existing}\", summary: \"<5-10 word recap>\", and a message containing only the delta (the user's new words quoted verbatim plus any newly relevant excerpts), asking for the full updated plan back. Spawn a fresh planner ONLY if that resume just failed (agent dead or errored) or this is a genuinely unrelated new planning task - in those cases re-issue this exact Agent call with \"fresh-planner: forced\" added to the prompt on its own line."
    jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
    ;;
esac

case "$EVENT" in
  PostCompact)
    # Output is ignored for this event; just flag that a compaction happened
    # so the next UserPromptSubmit re-injects the roster exactly once.
    mkdir -p "$STATE_DIR" 2>/dev/null && touch "$COMPACT_MARKER" 2>/dev/null
    ;;
  SessionStart)
    print_roster
    # SessionStart fires on the compact source too; consume the marker so the
    # UserPromptSubmit backstop doesn't inject the same roster a second time.
    rm -f "$COMPACT_MARKER" 2>/dev/null
    ;;
  UserPromptSubmit)
    if [ -f "$COMPACT_MARKER" ]; then
      rm -f "$COMPACT_MARKER"
      print_roster
    fi
    ;;
esac

exit 0
