# PR conventions deep-dive

Main rules are in CLAUDE.md. This file covers the full PR body template, GraphQL reply mechanics, and edge cases.

## PR body template

```
## Why
- What problem, risk, or operational pain this change solves
- Why this change is needed now

## What
- What behavior changed
- What stays the same
- Call out endpoints, env vars, models, schema fields, migrations, or deployment behavior explicitly

## How
- Briefly explain the implementation approach
- Note important tradeoffs, invariants, edge cases, backward-compatibility decisions
- Not a file-by-file changelog unless the PR is very small

## Verification
- Exact commands, targeted tests, manual checks, useful counts
- Quickstart or repro steps for API, config, infra, or deployment changes
- Checkboxes for completed and pending validation

## Notes / Deferred
- Explicit non-goals, rollout caveats, follow-ups
```

## What to cut on sight

- Multi-paragraph summaries. One paragraph max.
- Meta-context as its own section. Split/stack/supersedes info gets one line in the summary, not a heading.
- Review narrative ("Codex caught", "Claude lane flagged", "reviewed via the two-lane gate"). The fix is in the diff; the review is repo plumbing.
- Drift-correction prose ("previously claimed X, now correctly says Y"). Write "X: Y" as a fact about the current state.
- `## Strengths` / "Positive observations" sections. That's review-tool output, not PR content.
- `## What's deferred` multi-item lists. One follow-up line is fine; otherwise track in issues/memory.
- Explainer prose bullets longer than ~1.5 lines of wrapped text.

Rule of thumb: if a reviewer could strike out 30% of the body without losing actionable info, it's too heavy.

## Viewing PR comments

```bash
# Top-level comments
gh pr view <pr> --comments

# Inline review comments
gh api repos/{owner}/{repo}/pulls/<pr>/comments --paginate \
  --jq '.[] | {id: .id, path: .path, line: .line, body: .body}'
```

## Replying to comments

**Top-level**: `gh pr comment <pr> -b '…'`

**Quote the original when replying** to any top-level comment (review body, issue comment, etc.) using `> ` so readers can see what you're responding to without scrolling. Applies to every top-level reply.

**Inline review threads**: REST returns 404 — must use GraphQL.

Step 1: get thread node IDs
```bash
gh api graphql -f query='{
  repository(owner: "ORG", name: "REPO") {
    pullRequest(number: PR_NUM) {
      reviewThreads(first: 10) {
        nodes { id comments(first: 1) { nodes { databaseId path } } }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | "\(.id)\t\(.comments.nodes[0].path)"'
```

Step 2: reply to a thread
```bash
gh api graphql -f query='mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: "PRRT_...",
    body: "Your reply here"
  }) { comment { id } }
}'
```

**Review state**: `gh pr review <pr> --comment|--approve|--request-changes -b '…'`

## Branch-rename with an open PR

Never delete the old remote branch before the new PR is ready — deleting a PR's head branch auto-closes the PR, and GitHub won't let you reopen it (the ref is gone).

Correct sequence:
1. Rename locally: `git branch -m old-name new-name`
2. Push the new branch: `git push -u origin new-name`
3. Create a new PR with the same title/body/reviewers (the old PR can't be retargeted)
4. Only then delete the old remote: `git push origin --delete old-name`

## Why echo comment bodies in chat

`gh pr comment`, `gh pr review`, and `addPullRequestReviewThreadReply` all return a URL rather than showing the posted text. Without echoing the body in chat (as a fenced block or blockquote), the user can't catch a bad reply before it's live. Applies to every comment call.

## Rules for PR body revisions

When making changes to a PR based on feedback, update the PR description to reflect the changes. Update affected documentation (README, design docs) when changing features. Don't leave stale descriptions that no longer match the implementation.
