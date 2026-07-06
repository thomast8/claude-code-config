# claude-code-config

Generic [Claude Code](https://www.claude.com/product/claude-code) configuration - the reusable parts of `~/.claude`. Personal and work-specific content is kept out and layered in by a private orchestrator at setup time (see [`mac-dev-bootstrap`](https://github.com/thomast8/mac-dev-bootstrap)). The normal private setup installs this alongside Codex config from `Codex-config` when run with `--agents=both`.

## What's here

- `CLAUDE.md` - generic working rules (writing style, dev process, TDD, PR conventions, commit messages, Graphite). No identity, no employer specifics.
- `settings.json`, `plugins/desired-state.json` - permissions, hooks, model + advisor model, plugin/marketplace state. A few `@@GH_USER@@` placeholders point at your own plugin marketplace.
- `hooks/` - `pr-create-nag.sh`, `session-state.sh`, `agent-roster.sh` (re-injects resumable sub-agent IDs after compaction and denies duplicate `fable-planner` spawns while one is resumable), `warp-cwd-osc7.sh`, and `plan-mode-fable.sh` (delegates plan-mode design to the Fable-pinned `fable-planner` agent).
- `agents/` - review subagents plus `fable-planner.md` (plan design on Fable while the session stays on the default model).
- `mcp/user-servers.json` - base MCP servers (mcp-debugger, azure, azure-foundry). Employer-specific servers are added by the work layer.
- `commands/`, `references/`, `scheduled-tasks/`, `statusline-command.sh`.

## Templating

Files contain `@@TOKEN@@` placeholders (`@@GH_USER@@`, `@@GIT_EMAIL@@`, `@@GIT_NAME@@`, `@@SIGNING_KEY@@`) rendered from a values file by `mac-dev-bootstrap/lib/render.sh`. See [`values.example`](https://github.com/thomast8/mac-dev-bootstrap/blob/main/values.example).

## Use it

Render the files and copy them into `~/.claude/`, or let `mac-dev-bootstrap` do it. Used standalone, edit the `@@...@@` placeholders to your own values (or just delete the `@@GH_USER@@`-marketplace lines if you don't have one).
