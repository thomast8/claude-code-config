# Graphite deep-dive

Main rules are in CLAUDE.md. This file covers recovery, cleanup, and edge cases.

## Key commands
```bash
gt create <type>/<slug> -m "message"  # New branch in stack
gt restack                            # Rebase entire stack (auto-cascades)
gt submit --stack                     # Create/update PRs for whole stack
gt log short                          # Large stacks, branch names only
gt sync --force --no-interactive --restack  # Pull trunk, drop merged branches, restack
gt modify -c                          # Amend current commit + restack descendants
gt track <branch> -f                  # Re-track a diverged branch (auto-picks parent)
```

Deprecated names: `gt stack rebase` (use `gt restack`), `gt stack submit` (use `gt submit --stack`).

## Diverged branches

If you commit/push outside Graphite, branches diverge. `gt log short` lists them under "WARNING: The following branches have diverged from Graphite's tracking".

Fix:
- `gt track <branch> -f` — auto-picks the most recent tracked ancestor as parent. Without `-f`, Graphite opens a picker that stalls non-interactive sessions.
- Batch: `for b in branch1 branch2 …; do gt track "$b" -f; done`
- Then `gt restack` (or `gt sync --force --no-interactive --restack`) cascades rebases across newly re-tracked branches.
- Sanity-check parents with `gt log short` — auto-pick is usually right but can land on surprising parents for branches cut from now-merged parents.

## Workflow after fixing a mid-stack branch

```bash
gt track feature/branch-name
gt restack --no-interactive --no-verify
for branch in branch1 branch2 branch3; do
  git push --force-with-lease --no-verify origin "$branch"
done
```

## Ghost branch cleanup (local AND remote)

Deleting locally-tracked branches whose PRs are MERGED/CLOSED leaves remote refs that `git fetch --all` re-pulls, reintroducing the "diverged" warnings.

- Why the remote keeps them: GitHub's "auto-delete head branches" isn't on by default for every org repo.
- Detect: `gh pr list --state all --head <branch>` — if MERGED/CLOSED and the branch still exists on remote, it's a ghost.
- Clean up (after `gt delete` or `gt sync` removes locals):
  ```bash
  for b in ghost1 ghost2 …; do git push origin --delete "$b"; done
  git fetch --all --prune
  ```
- `gt sync --force` offers to delete merged branches locally but does NOT touch the remote. Remote cleanup is a separate explicit step.
- **Safety**: only delete a remote branch if its PR is confirmed MERGED or CLOSED. Deleting the head of an OPEN PR auto-closes it permanently.

## `gt submit` limitations
- Requires Graphite team subscription for org repos (e.g., `your-org`).
- If `gt submit` errors with "join a team", push branches manually with `git push --force-with-lease`.

## "Branch has been updated remotely outside of Graphite"

`gt submit --stack` refuses this way when the remote has commits your local copy doesn't — a parallel session, collaborator, or bot pushed to your branch. The trap is reaching for `gt sync --force` to "refresh"; that's a force-*pull* which fast-forwards local to remote tip and silently drops any local commit the remote doesn't have.

Recover without losing work:

```bash
# 1. Fetch without mutating local.
git fetch origin

# 2. Inspect both sides.
git log --oneline HEAD..origin/<branch>       # what remote has and you don't
git log --oneline origin/<branch>..HEAD       # what you have and remote doesn't

# 3. Fold remote commits under your local work.
git pull --rebase origin <branch>             # or `git merge` if you prefer a merge commit

# 4. Resubmit.
gt submit --stack
```

If `gt submit` still balks on the safety check after you've reconciled, `gt submit --stack --force` (force on `gt submit`, NOT on `gt sync`) is the right override. On org repos without a Graphite team subscription, fall back to `git push --force-with-lease` per branch.

The earliest-warning sign the trap is about to bite: you're already in the middle of a workflow (commits made locally, hooks passed) and `gt submit` errors instead of succeeding. Stop. Do not run `gt sync --force` to "fix it" — run `git fetch` instead.

## Tracking existing branches

```bash
gt branch track <branch> --parent <parent-branch>
```

Only works if parent commits are in the child branch's history. Typically `--parent main` for standalone branches.

## When Graphite is useful

- Creating a series of dependent PRs (feature broken into reviewable chunks)
- After making changes to a PR that has downstream PRs
- Rebasing an entire stack onto updated main

Not useful for branches with independent histories (Graphite needs true parent-child Git history).

Setup: `gt repo init` once per repository.
