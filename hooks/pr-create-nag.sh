#!/bin/bash
# Simple nag: remind about /review-code before creating a PR. No blocking, no state.
CMD=$(jq -r '.tool_input.command // empty')
if echo "$CMD" | grep -qE 'gh\s+pr\s+create'; then
  echo "Reminder: invoke /review-code before creating this PR." >&2
fi
exit 0
