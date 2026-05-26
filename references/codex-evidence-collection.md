# Cross-Model Evidence Collection Protocol

Reference document for merging review findings from Claude and Codex agents into a unified report.

## Finding Schema

Each finding from either lane must be normalized to:

- **file**: Path relative to repo root
- **line**: Line number or range (e.g., `42` or `42-48`)
- **severity**: `critical`, `important`, or `suggestion`
- **category**: One of: `bugs-and-conventions`, `error-handling`, `simplification`, `comments`, `test-coverage`, `type-design` (`bugs-and-conventions` is the catch-all for the code-reviewer agent, covering bugs, security, and CLAUDE.md convention violations)
- **source**: `claude` or `codex`
- **agent**: The specific agent name (e.g., `code-reviewer`, `silent-failure-hunter`)
- **description**: What the issue is and why it matters
- **fix**: Concrete recommendation

## Deduplication Rules

Match findings across lanes using fuzzy semantic judgment, not exact equality:

1. **Same file** - both findings reference the same file path
2. **Overlapping lines** - line numbers within ~5 lines of each other
3. **Same concern category** - both address the same class of issue

If all three match, merge into a single finding tagged **"confirmed by both"**.

Claude and Codex will describe the same issue differently and may cite slightly different line numbers. Use your judgment. When uncertain, keep them separate rather than incorrectly merging.

## Action Matrix

| Scenario | Action |
|---|---|
| Both agree, critical or important | Auto-fix immediately |
| Both agree, suggestion | Auto-fix |
| One flags critical, other silent | Present to user with both perspectives |
| One flags important, other silent | Present to user (the other model may have had good reason to skip it) |
| One flags suggestion, other silent | Auto-fix (low risk) |
| Direct conflict (opposing recommendations) | Present both, user decides |

## Unified Output Format

Present findings grouped by resolution status:

```
## Review Summary (N Claude + M Codex agents completed)

### Confirmed by Both (auto-fixed)
- `file:line` - [category] description
  Claude: "..."
  Codex: "..."

### Single-Source (auto-fixed)
- `file:line` - [category] [source] description

### Conflicts (your decision needed)
- `file:line` - [category]
  Claude (agent): "recommendation A"
  Codex: "recommendation B"

### Strengths (from either lane)
- Positive observations and well-done patterns noted by reviewers

### Agent Failures (if any)
- [agent-name]: timed out / failed (review proceeded without this agent)
```

Positive observations and strengths reported by either lane should be preserved in the report. They do not go through the deduplication/action matrix.

If no Codex agents completed (graceful degradation), skip the cross-model sections and present Claude findings directly, same as the existing single-lane flow.

## Suppression Scan

After processing all findings, scan the full diff once for lint/type suppressions:

- `# noqa`
- `# type: ignore`
- `# nosec`
- `# pragma: no cover`
- `// @ts-ignore`
- `// eslint-disable`

Each suppression should be removed by fixing the underlying issue. Only keep a suppression if the tool is genuinely wrong and there is no reasonable fix.
