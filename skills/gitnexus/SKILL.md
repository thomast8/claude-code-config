---
name: gitnexus
description: Navigate, debug, impact-analyze, and refactor code using the GitNexus knowledge graph. Use for understanding unfamiliar code, tracing bugs through call chains, blast-radius analysis before a change, and safe renames/extractions.
---

# Code Intelligence with GitNexus

One graph, four workflows. Do the Prerequisites once per session, then jump to the
section matching your task: **Exploring**, **Debugging**, **Impact Analysis**, or **Refactoring**.

## Prerequisites (do these first, every session)

1. **Preload deferred tool schemas.** `mcp__gitnexus__*` tools are deferred - names appear in the startup reminder but schemas are not loaded, and direct calls fail with `InputValidationError`. Hydrate the ones you need:
   `ToolSearch(query="select:mcp__gitnexus__list_repos,mcp__gitnexus__query,mcp__gitnexus__context,mcp__gitnexus__impact,mcp__gitnexus__detect_changes,mcp__gitnexus__rename,mcp__gitnexus__cypher")`
2. **Pick the repo.** Run `mcp__gitnexus__list_repos()` once. If more than one repo is returned, every subsequent call MUST include `repo: "<name>"` or the server errors out. Check `indexedAt` vs `git log -1` - if stale, refresh (`npx gitnexus analyze --skip-agents-md`) before querying. If GitNexus is unavailable, report it as a blocker rather than silently substituting read/grep.
3. **Tool IDs are `mcp__gitnexus__*`** (the bare `query`/`context`/`impact`/`rename`/`detect_changes`/`cypher` names below are shorthand).

Resources you can READ: `gitnexus://repo/{name}/context` (stats + staleness), `…/clusters`, `…/cluster/{name}`, `…/process/{name}` (execution traces).

## Exploring — "how does X work?", project structure, unfamiliar code

```
1. READ gitnexus://repo/{name}/context     → overview, staleness
2. query({query: "<concept>"})             → related execution flows
3. context({name: "<symbol>"})             → callers/callees/processes
4. READ …/process/{name}                   → full execution trace
5. Read source files for implementation detail
```

## Debugging — "why does this fail?", trace an error, who calls this

```
1. query({query: "<error or symptom>"})    → related flows
2. context({name: "<suspect>"})            → callers, callees, external calls
3. READ …/process/{name}                   → trace the flow
4. cypher({query: "MATCH path..."})        → custom call-chain traces if needed
```

| Symptom | Approach |
|---|---|
| Error message | `query` for the text → `context` on throw sites |
| Wrong return value | `context` on the function → trace callees for data flow |
| Intermittent failure | `context` → look for external/async deps |
| Recent regression | `detect_changes` to see what your edits affect |

## Impact Analysis — "is it safe to change X?", blast radius, pre-commit check

```
1. impact({target: "X", direction: "upstream", minConfidence: 0.8, maxDepth: 3})
2. READ …/processes                        → affected execution flows
3. detect_changes({scope: "staged"})       → map current git changes to flows
4. Assess risk and report
```

| Depth | Risk | Meaning |
|---|---|---|
| d=1 | WILL BREAK | direct callers/importers |
| d=2 | LIKELY AFFECTED | indirect deps |
| d=3 | MAY NEED TESTING | transitive |

Risk: <5 symbols = LOW · 5-15 / 2-5 processes = MEDIUM · >15 or many processes = HIGH · auth/payments path = CRITICAL.

## Refactoring — rename, extract, split, restructure

```
1. impact({target: "X", direction: "upstream"})   → map all dependents
2. query / context                                 → find flows + all refs
3. Plan update order: interfaces → implementations → callers → tests
```

Rename safely:
```
- [ ] rename({symbol_name: "old", new_name: "new", dry_run: true})  — preview
- [ ] review graph edits (high confidence) + ast_search edits (review carefully)
- [ ] rename({..., dry_run: false})                                 — apply
- [ ] detect_changes()                                              — verify only expected files changed
- [ ] run tests for affected processes
```

For string/dynamic refs use `query` to find them; for public APIs, version and deprecate.
