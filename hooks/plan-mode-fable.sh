#!/bin/bash
# Injects a plan-mode instruction so plan design is delegated to the
# fable-planner agent (pinned to claude-fable-5) while the main session
# stays on the default model.
#
# Wired to two events in ~/.claude/settings.json:
#   - UserPromptSubmit: fires on every prompt; injects only when
#     permission_mode == "plan" (covers Shift+Tab entry into plan mode).
#   - PostToolUse matcher EnterPlanMode: covers Claude entering plan mode
#     mid-turn via the EnterPlanMode tool; fires only on success, so no
#     mode check is needed.

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty')

CONTEXT='PLAN MODE MODEL POLICY: The user wants implementation plans designed by the Fable model. Once you have gathered enough context, delegate the design of the plan to the "fable-planner" agent (Agent tool, subagent_type: "fable-planner"), passing the task statement, constraints, and your findings (relevant files, existing patterns). Base the plan you write in the plan file on its output, noting explicitly anywhere you deviate from it. Consult it once per plan: if fable-planner has already been consulted for the current plan and the requirements have not materially changed, do not re-consult it.'

case "$EVENT" in
  UserPromptSubmit)
    if [ "$MODE" = "plan" ]; then
      jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
    fi
    ;;
  PostToolUse)
    jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
    ;;
esac

exit 0
