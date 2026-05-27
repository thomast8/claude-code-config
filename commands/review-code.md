---
description: "Run multi-lane Claude code review (correctness, design, security, tests, plus product/API contract and PR-body manual verification when applicable) in parallel before PR."
---

# Review Code

Reviewers with distinct lenses catch bugs any single pass misses. Run this before any PR. Lanes
A-D always run; add lanes E and F when they apply (see Fan out). Scale the review to the change
(see Review depth) — don't fan out on trivial edits.

## When to run

- Before `gh pr create`
- After finishing a feature, plan, or major refactor
- Before pushing or finishing a non-trivial change when standing guidance requires a review gate

## Review depth

Scale the review to the risk and size of the change — don't fan out on trivial edits:

| Change | Depth |
|---|---|
| Tiny docs / config / metadata | Local self-review + targeted checks; no sub-agents |
| Small low-risk code with tests | Local review through the lenses; spawn a lane only if something looks risky |
| Small safety-sensitive (auth, shell, path, writes, permissions) | One focused lane for the primary risk (usually security or correctness) |
| Medium / non-trivial | The warranted subset — usually correctness + tests, adding design/security when relevant |
| Risky, broad refactor, release/publish, data-loss, auth work, PR review, or explicit deep review | Full lane set |

For PR reviews, deep reviews, and changes touching public APIs, schemas, user-visible workflow
artifacts, docs, or integration contracts, include the product/API contract lane (E). Product
findings are formal review findings grounded in a concrete changed surface, held to the same
severity and evidence bar as the other lanes — not private follow-up notes.

Once a change is small, well covered, and prior findings are addressed, stop re-running sub-agents
— do a local final sanity check instead.

## Diff scope

The coordinator owns repo freshness and diff selection before any lane starts. If reviewing an
existing PR, use the PR's actual base, not `main` by assumption.

Resolve the base ref first:
- Existing PR: `base=origin/<baseRefName>`, `head=origin/<headRefName>` from
  `gh pr view <n> --json baseRefName,headRefName`.
- Graphite-tracked stack branch (only when `gt` is in use): inspect `gt log short`; if the current
  branch has an immediate parent branch, use `base=origin/<parent-branch>` so the diff excludes the
  rest of the stack instead of the whole `origin/main..HEAD` range.
- Standalone branch / unknown: the remote default from
  `git symbolic-ref refs/remotes/origin/HEAD --short` (usually `origin/main`). If this might pull
  in unrelated commits, say so.

Run `git status --porcelain=v1`, `git diff --stat HEAD`, and `git log --oneline <base>..HEAD`,
then choose:

| Situation | Diff to review |
|---|---|
| Branch has committed changes | `git diff <base>...HEAD` |
| Uncommitted tracked changes exist | also `git diff HEAD` |
| Untracked files exist | also `git ls-files --others --exclude-standard`, then read those files directly |
| Clean tree, 3+ commits ahead, user wants latest only | `git diff HEAD~1...HEAD` |
| Reviewing an existing PR | `git diff origin/<baseRefName>...origin/<headRefName>` |

Don't let dirty or untracked changes replace the committed branch diff — review the committed diff
first, then overlay dirty/untracked. Pass the same scope string to every lane so they review
identical code.

## Coordinator setup

**Own the setup before spawning lanes** so lanes work from evidence, not re-runs:
- Resolve the diff scope (above) and pass the identical scope string to every lane.
- Discover the repo's canonical commands (`just`, `make`, `npm run`, `uv run --extra ...`,
  `scripts/*`) and prefer them over generic ones. Pre-run the fast ones (lint, type-check). For a
  PR, read the body with `gh pr view <n> --json body` and pre-run one representative manual step.
- When a reviewed path needs setup, make it available with the smallest safe, repo-owned step
  (start a local service, sync deps, seed a fixture, use a documented dry-run/fake target) before
  marking it blocked.
- Pass each lane a **Known Verification Evidence** block: exact commands you ran (with working dir
  + base/head), their results, and commands they should NOT re-run. Lanes cite this instead of
  repeating broad checks; if a lane needs a command it can't run, it records the exact blocker plus
  the closest evidence and keeps going — no cache/shim workaround loops.

Reproduction means proving a concrete candidate finding — not re-running the whole scope or
re-proving coordinator-verified checks. A lane reruns a coordinator-verified command only when it
has a specific finding that file reads or a deterministic trace can't settle.

## Model tier (escalation gate)

Default every lane to Sonnet; escalate only the lanes a risk signal points at. The coordinator
computes signals during Coordinator setup (reusing the diff-stat, PR metadata, and GitNexus it
already gathers) and assigns each warranted lane a model before fan-out.

- Baseline: dispatch every lane with `model:"sonnet"`.
- Escalate a lane to `model:"opus"` per the table below.

Balanced posture — escalate the matched lane on ANY ONE strong signal, or on TWO soft signals:

| Signal | Type | Detection | Escalates |
|---|---|---|---|
| Migration / schema code | strong | diff touches `alembic/versions/`, `migrations/`, `*.sql` | A correctness + D tests |
| Infra / security surface | strong | `gh pr view --json labels` has a security/infra label, OR diff touches `.github/`, `Dockerfile*`, `terraform/`, `k8s/`, or auth/crypto/secret modules | C security |
| High blast radius | strong | GitNexus `impact` on changed symbols shows many downstream dependents (refresh a stale index first; if GitNexus is unavailable, fall back to import fan-out / reverse-dependency count) | A correctness + B design |
| Large change | soft | `git diff --stat` ≥ ~20 files or ~500 changed lines | (pairs only) |
| Low test coverage | soft | source files changed with no/insufficient matching test files in the diff (or repo coverage command shows a low delta) | A correctness + D tests |
| New concurrency / networking | soft | ADDED lines introduce new sync primitives (`Lock`, `Semaphore`, `threading`, `ContextVar`) or new network clients — match added lines only, NOT mere `async def` surface | A correctness |

Escalation is per-lane and targeted — never flip the whole review to Opus. If no signal fires, the
full review runs on Sonnet. State the tier decision (which lanes on which model, and why) in the
coordinator setup summary before fan-out.

## Lane prompt contract

Every lane gets one shared prompt body plus a short lens-specific suffix, so all lanes review the
same code under the same rules. Each lane prompt includes:
- **Role** — lane name and what it owns.
- **Scope** — absolute repo path, base/head (or dirty-tree) scope, key files, PR metadata, intent.
  Identical scope string across lanes.
- **Requirements/claims** — plan text, PR-body excerpts, API/schema excerpts the lane verifies.
- **Known Verification Evidence** — coordinator-run commands, results, and commands not to rerun.
- **Rules** — inspect the actual diff and surrounding code; don't trust summaries or implementer
  reports; DO NOT run `git fetch`/`git pull` or any network git op — local state only.
- **Evidence gate** — report only concrete issues grounded in changed behavior/contracts; if proof
  is blocked, report the exact blocker and closest evidence instead of looping on workarounds.
- **Output** — confirmed findings first; per finding: severity (one of P0–P4, per the shared body's
  scale), file/line, claim, evidence, expected, observed, failure signal, fix. If none, say so and
  note residual risk.

**Shared prompt body:**
```
Review the following change directly through the lens described at the end of this prompt: read the
diff and the surrounding code yourself. Do NOT delegate to another review skill or sub-agent (no
nested Agent calls); you are the reviewer.

Intent + scope: <intent + identical diff scope>

Known Verification Evidence:
<coordinator-run commands, working dir, base/head, results, and commands NOT to rerun>

Rules:
- Inspect the actual diff and relevant surrounding code; don't trust summaries or implementer reports.
- DO NOT run git fetch, git pull, or any network git op — local state only.
- Treat the Known Verification Evidence as authoritative; cite it instead of rerunning broad checks.
- Reproduce only concrete candidate findings before listing them; if a check is blocked, record the
  exact blocker and closest evidence.

Severity scale — use these labels exactly, no other vocabulary (no Critical/High/Med/Low, no 0–100 scores):
- P0 — breaks production/release safety now, broad data loss, or bypasses a critical security control.
- P1 — blocks the PR's main advertised behavior, high-confidence security/data-loss risk, corrupts persisted state, or will almost certainly fail in normal use.
- P2 — real bug or contract break, but with a workaround or limited scope.
- P3 — minor correctness/maintainability/coverage/docs issue; fix it, but it doesn't change core safety or behavior.
- P4 — nit or optional polish; omit unless exhaustive review was requested.

Output:
- Confirmed findings first. Per finding: severity (one of P0–P4), file/line, claim, evidence, expected,
  observed, failure signal, fix.
- If no confirmed issues, say so and note residual risk.
Return the full report.
```

## Fan out

Dispatch the warranted lanes as **background** agents (`run_in_background: true`) in a single
assistant message. Backgrounding decouples each lane from the coordinator's response stream, so a
single dropped connection or interrupted turn no longer aborts the whole batch - each lane keeps
running and the coordinator is re-invoked as reports land, then merges them. Scale the count to the
change (see Review depth): a heavy foreground fan-out of many lanes on one turn is exactly what a
single socket drop can take down with it.

For a small risk-scaled review (1-2 lanes), running them foreground in a single message is fine and
simpler to merge. Every lane snippet below takes `run_in_background: true` even where omitted for
brevity. Each lane's model is assigned by the escalation gate — default `model:"sonnet"`, swap to
`model:"opus"` for escalated lanes. The snippets show the default.

**Lane A — Correctness & bugs:**
```
Agent(subagent_type:"correctness-reviewer", name:"lane-a-correctness", description:"Correctness review", model:"sonnet",
  run_in_background:true,
  prompt:"<shared prompt body>. Lens: correctness only — logic errors, off-by-ones, edge cases, null/empty handling, race conditions, error-path bugs, incorrect async/await, state-machine holes, behavior regressions.")
```

**Lane B — Design & architecture:**
```
Agent(subagent_type:"design-reviewer", name:"lane-b-design", description:"Design review", model:"sonnet",
  prompt:"<shared prompt body>. Lens: design only — API shape, naming, abstraction boundaries, coupling, dead/speculative code, premature abstractions, duplication, maintainability.")
```

**Lane C — Security:**
```
Agent(subagent_type:"security-reviewer", name:"lane-c-security", description:"Security review", model:"sonnet",
  prompt:"<shared prompt body>. Lens: security only — authn/authz, input validation, injection (SQL, command, path, template), SSRF, secrets in code/logs, unsafe deserialization, crypto misuse, dependency risk, unsafe public writes.")
```

**Lane D — Tests & coverage:**
```
Agent(subagent_type:"pr-test-analyzer", name:"lane-d-tests", description:"Test review", model:"sonnet",
  prompt:"<shared prompt body>. Lens: tests only — do tests exercise the changed behavior? mocks hiding real integration? missing edge cases? flaky timing? assertions that would pass on a broken implementation?")
```

**Lane E — Product/API contract** (add when the diff changes public APIs, response schemas,
user-visible docs, workflow artifacts, or integration contracts):
```
Agent(subagent_type:"api-contract-reviewer", name:"lane-e-product", description:"Product/API contract review", model:"sonnet",
  prompt:"<shared prompt body>. Lens: product/API contract only — changed public APIs, response schemas, workflow artifacts, user-visible docs, validation claims, warning surfaces, ambiguous selection rules, unsupported semantics, integration-contract clarity. Findings are formal review findings grounded in a concrete changed surface, not nice-to-haves. Prefer P2/P3; use P1 only when the gap blocks the PR's stated purpose or causes likely user/data/contract harm.")
```

**Lane F — PR-body manual verification** (add only when reviewing a PR whose body has manual /
test-plan / reviewer-runnable steps): see the dedicated section below for the lane prompt and the
required `Manual Verification` output.

## PR-body manual verification

For every PR review, read the PR body before the final review. If it has manual-verification,
test-plan, smoke-test, or reviewer-runnable steps (checkboxes, numbered steps, fenced commands,
endpoint calls, UI flows, DB checks), treat each as a claim by the author and run through it:
- Identify what the step proves; run the exact command/flow when practical.
- If a step needs setup, do the smallest safe repo-owned setup (start local services, sync deps,
  seed fixtures, dry-run/fake target) before marking it blocked.
- If a step is ambiguous, run the smallest reasonable interpretation and say so.
- If it's unsafe, destructive, credential-gated, or impossible after safe setup, mark it blocked
  with the missing dependency — don't fake it.
- A step failing because the PR instructions are wrong is review evidence; calibrate severity by
  whether it blocks reviewers or reveals a real bug.

When fan-out is already warranted and the steps can run in parallel, spawn one focused lane:
```
Agent(subagent_type:"pr-manual-verifier", name:"lane-f-manual", description:"PR-body manual verification", model:"sonnet",
  prompt:"Review <intent + repo path + diff scope + PR-body manual-verification excerpt + Known Verification Evidence>. Lens: PR-body manual verification only — extract each manual/test-plan step, run it after the smallest safe repo-owned setup, treat each as an author claim: state what it proves, run the exact command/flow, record observed output/state. Ambiguous → smallest reasonable interpretation, say so. Unsafe/destructive/credential-gated/impossible after safe setup → mark blocked with the missing dependency, don't fake it. DO NOT run git fetch or any network git op. Return a step-by-step ledger: step label, claim proved, exact command/flow, observed output/state, status (passed/failed/adjusted/blocked), failure signal. Only raise a code finding when a step failure proves a concrete bug or wrong PR instruction.")
```
For small local reviews, the coordinator may run this ledger directly instead of spawning a lane.
When Lane F runs, the final review MUST include a `Manual Verification` section walking each step
(label, what it proves, command/flow used, observed result, status). Never collapse it to "manual
tests passed."

## Finding reproduction gate

Treat every suspected issue as a candidate until reproduced; present only reproduced findings as
review issues. Reproduce with the smallest real check — a failing test, a real CLI/API/app flow, a
DB or state readback, a filesystem inspection, or a deterministic trace through the changed code
with concrete input/state when execution is blocked. Shape it as reviewer-runnable verification (a
command a reviewer could copy from the PR branch), not private debugging notes; for
install/deploy/migration/auth/data-destructive paths use isolated temp state or a clearly-marked
safe target.

For each confirmed finding capture: **claim · safety boundary/setup · exact command or trace ·
expected · observed · failure signal**. **Make this rubric visible in the final review for every
confirmed finding** — don't bury it or summarize as "reproduced." Lanes apply the same gate to
their own candidates; agreement across lanes raises confidence but does not replace reproduction.

A candidate that only means "missing coverage", "stale docs", or a theoretical concern is `P3` or
an Unverified Risk — not a high-severity finding. If a candidate can't be reproduced, drop it or
list it under **Unverified Risks** with the exact blocker.

## Severity calibration

Pick severity from concrete impact, not habit; don't default everything to `P2`.
- **P0** — breaks production/release safety now, broad data loss, or bypasses a critical security control.
- **P1** — blocks the PR's main advertised behavior, high-confidence security/data-loss risk, corrupts persisted state, or will almost certainly fail in normal use.
- **P2** — real bug or contract break, but with a workaround or limited scope.
- **P3** — minor correctness/maintainability/coverage/docs issue; fix it, but it doesn't change core safety or behavior.
- **P4** — nits and optional polish; omit from formal findings unless the user wants exhaustive review.

Between adjacent levels, ask: does this block the PR's stated purpose, can a normal user hit it,
can it lose or expose data, is there a reasonable workaround, and did reproduction prove a real
failure rather than a theoretical concern? A finding that only says "add a test" without a
reproduced behavioral failure is usually `P3` or an Unverified Risk, not `P2`.

## Merge

Use the Cross-Model Evidence Collection Protocol in `references/codex-evidence-collection.md`:
normalize each lane's report, dedupe findings across lanes (same issue raised by multiple agents =
high confidence), auto-fix confirmed issues and single-source valid suggestions, present conflicts
or judgment calls to the user. Apply the reproduction gate before presenting — list only reproduced
findings; put unreproduced concerns under **Unverified Risks** with the blocker.

Normalize every finding's severity onto the P0–P4 scale before tabulating. If a lane emitted a
different vocabulary, remap it: Critical/blocker → P0 or P1, Important/High/Major → P1 or P2,
Medium → P2, Minor/Low/Nit → P3 or P4; a 90–100 confidence score → P0/P1, 80–89 → P2. The merged
table uses P0–P4 exclusively — never carry two scales into one table.

**Fix valid suggestions too**, not just bugs. Only skip suggestions that are clearly out of scope
or need a major design change.

## Final review output

Present confirmed findings first as a table, then a `Verification` line stating the exact checks
run (or coordinator-supplied evidence relied on) and their results. Include the `Manual
Verification` ledger when Lane F ran. If nothing is confirmed, say "No confirmed findings" first,
then list **Unverified Risks**.

| Severity | Finding | File | Claim | Repro setup | Expected | Observed | Failure signal | Fix |
|---|---|---|---|---|---|---|---|---|

The `Severity` column carries only P0–P4 labels (see Severity calibration). A row showing
Critical/High/Med/Low means a lane's scale wasn't normalized — remap it before presenting.

Keep cells concise; if a command is too long for a cell, summarize it and put the exact command
under a `Reproduction Details` block below the table.

## Public review comments

The severity table and reproduction rubric are for the chat review only. When posting a finding to
GitHub (`gh pr comment` / `gh pr review`), rewrite it as one or two sentences of plain human prose
tied to the line: the problem, one concrete impact, and the asked-for fix. No `Severity:` labels,
no table headers, no internal ledger formatting in public comments.

## Failures

If one lane errors out, proceed with the remaining lanes and report the failed lane. If two or more
lanes fail during a full review, rerun those lenses sequentially yourself (in the coordinator) or
stop and surface the errors — for a full review, don't claim the gate passed unless every required
lane completed or each failed required lane was rerun sequentially. For a smaller risk-scaled
review, report exactly which lenses ran and which, if any, failed.
