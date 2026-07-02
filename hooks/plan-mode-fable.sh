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

CONTEXT='PLAN MODE MODEL POLICY: The user wants implementation plans designed by the Fable model. Once you have gathered enough context, delegate the design of the plan to the "fable-planner" agent (Agent tool, subagent_type: "fable-planner"). The prompt you pass is the ONLY context the planner receives, and its tokens are expensive, so write a curated, self-contained brief: the task statement, constraints, file:line references, and the load-bearing code excerpts inlined so the planner rarely needs to re-read files. Quote the user'"'"'s own words where they state requirements (their wording carries intent that paraphrase loses); include nothing from the conversation the plan does not need. Write its plan into the plan file essentially verbatim, adjusting formatting only; you are the scribe and fact-checker, not the design editor. Fact-check it against what you explored (files it references exist, user constraints honored, verification steps runnable) and surface its Open questions to the user. If a fact is wrong or a constraint violated, re-consult fable-planner with that specific issue; if you disagree with a design choice, flag it as a note in the plan for the user instead of silently rewriting the stronger model'"'"'s design. Consult it once per plan: if fable-planner has already been consulted for the current plan and the requirements have not materially changed, do not re-consult it.'

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
