---
description: "Address GitHub PR review comments with a paired original-comment/proposed-reply ledger, explicit approval before posting, gh-based posting + readback, PR description updates, and reviewer re-requesting. Use when the user says 'address the review comments', 'reply to the reviewers', 'respond to PR feedback', 'send the PR back to reviewers', or '/review-thread-response'."
---

# Review Thread Response

Respond to PR review comments through a visible ledger and an explicit approval gate, then post
and read back via `gh`. Transport is `gh` + the GitHub GraphQL API (CC has no provider plugin).

## When to run

- The user asks to address/reply to review comments, or to send a PR back to reviewers.
- After pushing fixes that answer reviewer feedback.

## 1. Resolve the PR and fetch threads (read-only)

Use the PR's **actual** base/head — never assume `main`. Get the number from the current branch
(`gh pr view --json number,baseRefName,headRefName,isDraft`) or the user's argument, then fetch
unresolved review threads:

```bash
gh api graphql -f query='
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      isDraft baseRefName headRefName
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line
          comments(first:20){ nodes{ author{login} body url createdAt } }
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F number=<n>
```

Focus on threads where `isResolved=false`. The thread `id` (a node ID) is what you reply to.

## 2. Inspect the code, then build the ledger

For each open thread, read the cited `path:line` and surrounding code, related commits, and stacked
context, so you can say why the comment matters and whether it is fixed / invalid / already handled
upstream / still open. Build this table and show it **before posting anything**:

| Thread | Original comment | Code-context reasoning | Status | Evidence | Proposed reply |
|---|---|---|---|---|---|
| 1 — `path:line` | Quoted/summarized enough to identify it | Why it was raised, how the nearby code behaves, why the response is correct | Fixed / handled upstream / rejected / follow-up | Concrete file/function/test/command/PR/result | Exact public reply body |

Keep cells scannable; for a long comment, quote the key part and add a short "Long comments" note
only if the omitted context could change the decision.

## 3. Approval gate (matches CLAUDE.md PR rules)

Echo the exact proposed reply bodies in chat and **wait for approval** — draft → approval → post →
readback, never draft-and-post in one turn. If the user revises a body, update only that one.

## 4. Post approved replies

Reply to a specific review thread:

```bash
gh api graphql -f query='
mutation($threadId:ID!,$body:String!){
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
    comment{ body url }
  }
}' -F threadId=<thread-id> -f body=<approved body>
```

For a general (non-thread) PR comment, use `gh pr comment <n> --body <body>`.

## 5. Read back

Echo the returned `body` and `url` for every posted reply. `gh`/API output is easy to mangle, so the
readback is the only proof the comment posted as written. If a post fails, stop and report which
thread failed — do not invent a readback.

## 6. PR description + reviewer handoff

- Update the PR body (`gh pr edit <n> --body ...`) when behavior, verification, manual testing,
  docs, schema, or rollout notes changed.
- Re-request reviewers who left blocking comments: `gh pr edit <n> --add-reviewer <login>` (or the
  `requestReviews` GraphQL mutation). If the PR `isDraft` and the user didn't ask to mark it ready,
  report that instead of readying it.
- **Never resolve threads authored by the PR author** — reply, but leave resolution to the reviewer.

## Reply style

- One or two casual sentences; no bullets, bold, numbered lists, or commit SHAs in public replies.
- Say what changed, not which commit changed it.
- If pushing back, give the reason plainly. If a comment was handled by an upstream PR or a rebase,
  say so and name the PR number. Don't thank every reply.
- The reasoning/evidence columns are for the chat ledger only — keep them out of the posted reply.

See `references/pr-conventions.md` for the full PR body template and comment-quoting mechanics.
