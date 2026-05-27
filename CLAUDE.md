## Terminal (Warp)
- **Warp is the primary terminal for Claude Code.** `Cmd+T` opens a plain terminal that inherits the active tab's repo (`working_directory_config = previous_dir`); start Claude with `ca`. Worktrees: run `caw` from a repo shell (or a `Cmd+D` split, which also inherits the repo) - it picks an open PR or a new branch, creates the worktree, copies gitignored dev files (`.env*`, `.claude/settings.local.json`), `cd`s in, and launches Claude. The `claude_worktree` / `claude_pr` tab configs do the same from the `+` menu; a tab config opens in `$HOME`, so the launchers prompt for the repo (recents first) when not run from inside one. Worktrees live centrally in `${WARP_WORKTREES_DIR:-~/worktrees}/<repo>/<name>`, never as `~/GitRepos` siblings. No `phantom`.
- **Newlines**: `Ctrl+J` always inserts a newline; `Shift+Enter` may submit in Warp+Claude Code, so prefer `Ctrl+J`.
- **Notifications** come from the official `warp@claude-code-warp` plugin (desktop + in-app).
- **Two unrelated "remote control" features**: Claude Code's own (`settings.json: remoteControlAtStartup: true`, links the session to claude.ai / the Claude phone app) vs Warp's `/remote-control` toolbar chip (publishes the session to Warp's cloud as a share link). They are independent; Warp's chip never reflects CC's state.

## Writing Style
- **Never use em dashes (--).** Use a regular dash (-), a comma, a semicolon, or rewrite.

## Command and Execution
- Run scripts and monitor output without asking for confirmation.
- **NEVER delete files without asking first.** If a file blocks a commit, fix the issue or ask. Moving to temp is acceptable; `rm` without permission is not.

## Git Freshness (IMPORTANT)
- **Before any git operation or PR review, fetch first**: `git fetch --all`, then inspect divergence manually (or pull the current branch). This plain-git path is the default. Graphite is optional (see below): only when you have explicitly confirmed Graphite is in use *and* there are no unpushed local commits on any stack branch, `gt sync --force --no-interactive --restack` — but note it is a force-*pull* that fast-forwards local to remote tip and silently discards any local commit the remote doesn't have.

## PR Review Diff Scope (IMPORTANT)
- **Always check the PR's actual base branch** with `gh pr view <number> --json baseRefName,headRefName`. Stacked PRs target their parent — `git diff main...HEAD` would include the whole stack. Correct form: `git diff origin/<baseRefName>...origin/<headRefName>`.

## GitNexus — MANDATORY for codebase exploration
- **Preload at session start**: `ToolSearch(query="select:mcp__gitnexus__list_repos,mcp__gitnexus__query,mcp__gitnexus__context,mcp__gitnexus__impact,mcp__gitnexus__detect_changes,mcp__gitnexus__rename,mcp__gitnexus__cypher")`. Deferred tools fail with InputValidationError until loaded.
- **Stale = refresh, not fall back (IMPORTANT)**: `mcp__gitnexus__list_repos` first. If `indexedAt` is behind `git log -1 --format=%H`, run `npx gitnexus analyze --skip-agents-md` and re-check before querying. Do NOT substitute grep/Read/Explore for a stale index — that defeats the point of having the graph.
- **Fast indexing by default.** Use `gitnexus analyze --skip-agents-md` for stale or missing indexes; reserve `--embeddings` for explicit semantic/vector indexing requests. The global hooks (`~/.claude/hooks/gitnexus-init.sh`, the PostToolUse commit/merge hook in settings.json) use the fast path; run `--embeddings` by hand only when you need semantic `query` backed by fresh vectors.
- **Multi-repo** needs `repo: "<name>"` on every call.
- **Flow**: `query` → `context` → `impact`. Narrate ("querying GitNexus for X") so silent omission is visible. The merged `gitnexus` skill has the per-task workflows.
- **Never commit GitNexus sections in CLAUDE.md.** The `# GitNexus — Code Intelligence` block is injected by `gitnexus analyze`. Strip before committing.

## Development Process
- **TDD by default** for new functions, bug fixes, behavior changes. Skip for config, docs, migrations, trivial edits.
- **Find root cause before fixing.** If three fix attempts fail, stop and question the architecture (the built-in `systematic-debugging` skill).
- **Design first**: for tasks needing design exploration, sketch the approach in 2-3 sentences and align with the user before coding.
- **Real smoke tests over mocks**: when verifying a fix, also run against real objects/providers. Mocks prove wiring matches the test author's mental model, not that the code works against the real wire. Report what actually happened (params, response), not just "tests passed". If real credentials are missing, say so and stop — don't pretend mocks cover it.
- **Get as close to reality as possible in every verification step.** Passing unit tests with `tmp_path` / mocks / synthetic layouts is a floor, not a ceiling. Before claiming done, *exercise the actual code*: run the real script/binary in the real filesystem, the real git worktree (not a synthesized one), against the real DB, real network call, real CLI invocation. When full prod isn't accessible, write an ad-hoc script that **imports your real modules** and drives them with realistic inputs — this is the middle ground between fixture tests and prod, and it routinely catches what fixture tests miss (default-argument binding, env-var scoping, path resolution, permission quirks, timing, encoding). If the user asks "did you really stress test this?", the answer is only "yes" when the code has been exercised end-to-end against production-like conditions with real objects — not just against a contrived harness.
- **Don't commit proactively** during ad-hoc work — ask first. When executing a plan, commit at each provisioned checkpoint without asking.
- **Run fast linters before committing**: `uv run ruff check src/ tests/ && uv run ruff format --check src/ tests/ && uv run mypy src/ tests/`. Catches errors in seconds instead of waiting for the pytest-heavy pre-commit hook.
- **Code review before finishing**: invoke `/review-code` and fix all issues before considering the work done.
- **Before claiming done**, exercise the change end-to-end. Type checks verify correctness, not completeness.
- **Handling review comments**: decide if valid. Fix if yes; push back with a reason if no. Never capitulate silently. Fix valid suggestions too, not just bugs — skip only when clearly out of scope.
- **.env files**: never create or edit. Use the Settings class in src/config/settings.py.
- **Keep changes focused.** Don't sweep across many files; confirm with user before sweeping.
- **Don't name non-pytest files "test"**.

## Tools and Conventions
- Working inside Zed (editor); Warp (terminal).
- Always use `uv` commands over naked python/pip. Use f-strings, not %-formatting (loguru prefers f-strings).
- Use `gh` for GitHub. Pick the account per command by repo owner via token injection - `GH_TOKEN=$(gh auth token -u <account>) gh ...` (same prefix for `git push`). This never touches the shared active account, so concurrent sessions can't flip it out from under each other. The commit-auth mapping says which account each owner uses.
- **Avoid lint/type suppressions** (`# noqa`, `# type: ignore`, `# nosec`, `# pragma: no cover`). Fix the underlying issue. Only suppress when the tool is genuinely wrong.
- **Never commit design docs** (`.design/*`) — they are local working documents.
- When invoking skills, use the exact name from the available skills list.
- **Worktrees**: from a repo shell run `caw` (PR or new-branch picker -> worktree in `${WARP_WORKTREES_DIR:-~/worktrees}/<repo>/<name>` -> Claude); the `claude_worktree` / `claude_pr` tab configs do the same from the `+` menu. Not in a repo -> the launcher prompts for one (recents first). **When you need to start a new feature branch or PR slice mid-session, use `EnterWorktree` (the Claude Code tool) — never `git checkout -b` — so the current session directory's branch stays clean and the new work gets an isolated worktree.**
- Check for an open PR on the current branch before creating a new one.

## Commit Messages
Use Conventional Commit prefixes: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `ci:`, `test:`. Atomic; title = squash-commit title when this is a PR. Explain WHY in the body if not obvious. Never model on Mend/license-update noise. Never bypass hooks (`--no-verify`, `--no-gpg-sign`) unless the user explicitly asks. **Never open a commit message in an external editor during commits or rebases** - use non-interactive forms (`git commit -m`, `git commit -F <file>`, `GIT_EDITOR=true git rebase --continue`), which an agent can't drive interactively. Before the first commit of a session, verify `git config user.email` matches the repo's intended identity; commits must be signed (hooks verify).

## Graphite (optional)

**Default to plain git** for local branch and rebase work, and `gh` + `git push` for GitHub pushes and PRs. Graphite (`gt`) is optional: access on org repos may be unavailable or expired, so don't assume `gt submit`, `gt sync`, or the Graphite dashboard are usable. Use `gt` only when I explicitly ask for it, or when you have just confirmed it works for the current repo. If a `gt` command fails because the org plan is expired or access is unavailable, stop using Graphite for that task and continue with plain git.

**Branch naming (IMPORTANT, applies either way)**: `<type>/<slug>` format. Valid types: `feat`, `feature`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `build`, `perf`, `hotfix`, `release`, `revert`. `codex/` is not a valid branch prefix. **Use the full prefix `feature/` rather than `feat/` when the pre-commit hook requires it.** Slug: lowercase kebab-case `[a-z0-9._-]+`. Always pass an explicit branch name - never auto-name.

**When you do use Graphite**: `gt restack` and `gt submit --stack` are one unit of work; track untracked branches first (`gt branch track <branch> --parent <parent>`). **Never reach for `gt sync --force` to reconcile a remote-diverged branch** — it is a force-*pull* that fast-forwards local to remote tip and silently discards any unpushed local commit. Instead `git fetch`, inspect both sides, `git pull --rebase` (or merge), then re-run `gt submit --stack`.

See `references/graphite.md` for the full `gt` ↔ raw-git mapping, diverged-branch recovery, ghost-branch cleanup, the restack cascade workflow, and `gt submit` limitations.

## Code Quality / LLM Model Lookups
- Before using a library or framework you're unsure of, query the `context7` MCP.
- **When writing code with LLM model IDs** (OpenAI, Google, etc.), always verify current IDs via `context7` or the provider's API docs — training data is stale. Anthropic: `claude-opus-4-7` (1M context). See `references/llm-models.md` for OpenAI + Gemini IDs and API patterns.

## Deployment (Railway)
- Prefer Railpack over Dockerfile when possible (zero-config, smaller images).
- Railway sets `PORT` dynamically — use shell-form CMD: `CMD uvicorn ... --port ${PORT}`.
- See `references/railway.md` for CLI command reference.

## Documentation Tracking
- TODO.md tracks major implemented features, newest-completed-first, with dates.
- Keep database-schema.md and README.md updated as features land.

## Releases
- Tag commits before creating a release: `git tag vX.Y.Z <sha> && git push origin vX.Y.Z`. Never point releases at branch names (they drift as commits land). Verify with `git log --oneline -1 vX.Y.Z`.

## PR Management — essentials
- **Always open PRs as draft**: `gh pr create --draft`.
- **PR title = squash-commit title**.
- **PR body** uses Why / What / How / Verification / Notes-Deferred structure (one paragraph each). Reviewer-focused: behavior first, implementation second.
- **Verification = reviewer-runnable**: the Verification section lists the exact steps a reviewer can copy from the PR branch — smallest real check first (CLI invocation, API call, app flow, DB/state readback); pytest/fixtures are supporting evidence, not the primary steps. Run those exact steps from the pushed branch *before* encoding them, and record observed output/state, not a narrative of what you ran. No opaque heredocs or one-off harnesses; if a step can't run, mark it blocked with the missing dependency rather than faking a pass.
- **PR comment tone**: short, casual, one or two sentences. No bullet points, bold, numbered lists in replies. If it reads AI-written, rewrite.
- **Never cite commit SHAs in replies** — reviewers can't follow them. Write what changed, not which commit did it.
- **Echo comment bodies in chat and wait for my approval before posting**, then echo the readback after posting. Draft → approval → post → readback; never draft-and-post in one turn. `gh pr comment` / `gh api` results only show URLs, so the pre-post echo is the only way I can catch a bad reply before it's public, and the post-post readback is the only way to catch silent character-mangling.
- **Never delete a PR's remote head branch** until the new PR is ready. GitHub auto-closes the PR and won't let you reopen it.
- **After a PR review, update the PR description** to reflect changes made.

See `references/pr-conventions.md` for the full PR body template, inline-comment GraphQL mechanics, comment-quoting rules, and the branch-rename-with-open-PR sequence.

## Config Location & Backup
- Live runtime homes (real files, no symlinks, no iCloud): `~/.claude/`, `~/.warp/`, `~/.zshrc`, `~/.config/{git,zed}`, `~/.ssh`. Default model in `~/.claude/settings.json` (`claude-opus-4-7[1m]`, the 1M-context variant).
- Backup is split across **public workflow repos** + a **private orchestrator** (all account `@@GH_USER@@`):
  - Public: `warp-claude-workflow` (-> `~/.warp`), `claude-code-config` (-> `~/.claude`, generic), `shell-editor-dotfiles` (zsh + zed), `mac-dev-bootstrap` (bootstrap framework + templated git/ssh + the render engine). Personal identity is rendered in from `profiles/personal/values` via placeholder tokens.
  - Private orchestrator `warp-dev-environment`: `manifest.toml` (public repos + pinned refs), `profiles/personal/{values,overlay}`, `profiles/work/{values,overlay}`, `setup [--with-work]`.
- **New Mac**: `ORCH_REPO=@@GH_USER@@/warp-dev-environment /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/@@GH_USER@@/mac-dev-bootstrap/main/bare-mac.sh)" -- --agents=both` -> installs Xcode CLT + Homebrew + gh, prompts `gh auth login`, clones the orchestrator, and runs the personal setup. Add `--with-work` only on a machine that should receive the work overlay.
- **Mirror rule (IMPORTANT)**: generic content is edited in its PUBLIC repo (it is rendered into the live file at setup) - never hand-edit the rendered live copy as the source of truth, or real identity could leak back into a public repo. Personal/work specifics live only in the orchestrator profiles. Runtime state (caches, sessions, auth, `~/.claude.json`, `*.local`, `*.pre-*-backup-*`, `plugins/cache`, `plugins/marketplaces`) is machine-local; never mirror it.
- Plugin source repos under `~/GitRepos/` (`claude-find-reviewer`, `claude-session-title`), published via the `@@GH_USER@@/claude-plugins` marketplace.
- Project memory: `~/.claude/projects/<project>/memory/`.

## Commit Authentication
**Before the first commit in any session**, verify `git config user.email` matches the repo's intended identity. Fix with `git config user.email "<correct>"`. For `gh`/`git push`, select the account inline per command - `GH_TOKEN=$(gh auth token -u <account>) gh ...` - not a global `gh auth switch`. Commits must be signed; hooks verify (investigate only if a hook fails or GitHub shows "Unverified").
- Default (personal): `@@GIT_EMAIL@@`, account `@@GH_USER@@`, signing key `~/.ssh/@@SIGNING_KEY@@` (reload: `ssh-add ~/.ssh/@@SIGNING_KEY@@`). `ADG-Projects/*` and all non-work repos use this - the git global default.
