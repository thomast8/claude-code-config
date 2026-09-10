---
description: "Address GitHub PR review comments with a compact evidence ledger when useful, standing authorisation for verified fixes, otherwise approval before posting, gh-based posting + readback, PR description updates, and reviewer re-requesting. Use when the user says 'address the review comments', 'reply to the reviewers', 'respond to PR feedback', 'send the PR back to reviewers', or '/review-thread-response'."
---

# Review Thread Response

Respond to PR review comments using evidence and existing authorisation, then post and read back via `gh`. Transport is `gh` + the GitHub GraphQL API (CC has no provider plugin).

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
upstream / still open. For several comments, use a compact ledger; for one verified fix, a concise evidence-backed summary is enough. This is a reporting aid, not another approval gate:

| Thread | Original comment | Code-context reasoning | Status | Evidence | Proposed reply |
|---|---|---|---|---|---|
| 1 — `path:line` | Quoted/summarized enough to identify it | Why it was raised, how the nearby code behaves, why the response is correct | Fixed / handled upstream / rejected / follow-up | Concrete file/function/test/command/PR/result | Exact public reply body |

Keep cells scannable; for a long comment, quote the key part and add a short "Long comments" note
only if the omitted context could change the decision.

## 3. Explain consequential decisions briefly

Lead with the fix and evidence. Explain disputed comments or unresolved risks in plain language;
do not require a tutorial or a second approval ceremony for every verified fix.

## 4. Apply existing authorisation

An implemented and verified fix is standing authorisation to reply concisely and resolve that
exact review thread. Continue without asking again, then read back the reply and resolution.
For an unfixed, disputed or unverified comment, keep it unresolved. Check whether the user has
already authorised the proposed reply; ask only if that authority is missing. A general code
implementation request is not permission to send unrelated messages.

## 5. Post approved replies

Reply to a specific review thread:

```bash
gh api graphql -f query='
mutation($threadId:ID!,$body:String!){
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}){
    comment{ body url }
  }
}' -F threadId=<thread-id> -f body=<approved body>
```

For an implemented and verified fix, resolve only that thread after the reply succeeds:

```bash
gh api graphql -f query='
mutation($threadId:ID!){
  resolveReviewThread(input:{threadId:$threadId}){ thread{ id isResolved } }
}' -F threadId=<thread-id>
```

For a general (non-thread) PR comment, use `gh pr comment <n> --body-file <reply-file>`.

## 6. Read back

Echo the returned `body` and `url` for every posted reply. `gh`/API output is easy to mangle, so the
readback is the only proof the comment posted as written. If a post fails, stop and report which
thread failed — do not invent a readback. Re-run the review-thread query from section 1 and verify
that the exact thread has `isResolved=true`. A posted reply alone is not a resolved thread.

## 7. PR description + reviewer handoff

- Update the PR body (`gh pr edit <n> --body ...`) when behavior, verification, manual testing,
  docs, schema, or rollout notes changed.
- Re-request reviewers who left blocking comments: `gh pr edit <n> --add-reviewer <login>` (or the
  `requestReviews` GraphQL mutation). If the PR `isDraft` and the user didn't ask to mark it ready,
  report that instead of readying it.
- Resolve only the exact thread covered by an implemented, verified fix and standing authorisation; read back `isResolved`. Leave disputed or unverified threads open.

## Reply style

- One or two casual sentences; no bullets, bold, numbered lists, or commit SHAs in public replies.
- Say what changed, not which commit changed it.
- If pushing back, give the reason plainly. If a comment was handled by an upstream PR or a rebase,
  say so and name the PR number. Don't thank every reply.
- The reasoning/evidence columns are for the chat ledger only — keep them out of the posted reply.

See `references/pr-conventions.md` for the full PR body template and comment-quoting mechanics.
