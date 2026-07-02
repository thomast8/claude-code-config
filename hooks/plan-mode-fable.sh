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

CONTEXT='PLAN MODE MODEL POLICY: The user wants implementation plans designed by the Fable model. Never stall the handoff waiting for scope or design answers - ambiguities travel to the planner as open points, and only the planner'"'"'s questions come back to the user. Once you have gathered enough context, delegate the design to the "fable-planner" agent (Agent tool, subagent_type: "fable-planner"). The prompt you pass is the ONLY context the planner receives, and its tokens are expensive, so write a curated, self-contained brief: the task statement, constraints, file:line references, and the load-bearing code excerpts inlined so the planner rarely needs to re-read files. Quote the user'"'"'s own words where they state requirements (their wording carries intent that paraphrase loses); include nothing from the conversation the plan does not need. Write its plan into the plan file essentially verbatim - keep its section structure and wording, adjusting formatting only; you are the scribe and fact-checker, not the design editor. Fact-check it against what you explored (files it references exist, user constraints honored, verification steps runnable). If the plan has Open questions, relay them to the user with AskUserQuestion VERBATIM as the planner phrased them - its question text, its options with their trade-offs, its recommendation as the "(Recommended)" option. Never invent, reword, merge, or add questions of your own; if the user cannot be prompted (headless or background run), proceed with the planner'"'"'s recommended defaults and record that in the plan. Apply answers exactly as the plan specifies for the chosen option; go back to the planner only when an answer overturns a design decision, a fact is wrong, a constraint is violated, or the user sends scope changes or plan revisions - otherwise one consultation per plan. When you do go back, do NOT spawn a new fable-planner: resume the existing one via SendMessage to the agentId from its spawn result (it still holds the brief and its own reasoning), send only the delta (the user'"'"'s new words quoted verbatim plus excerpts for any newly relevant code), and ask for the full updated plan back so you can re-transcribe the plan file wholesale instead of splicing. Spawn a fresh planner only if the previous one is not resumable in this session. If you disagree with a design choice, flag it as a note in the plan instead of silently rewriting the stronger model'"'"'s design.'

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
