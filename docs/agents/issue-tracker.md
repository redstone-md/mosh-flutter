# Issue tracker: Linear

The canonical tracker for this repository is
[Mosh in Linear](https://linear.app/ivoxygen/project/mosh-32d1c33dc92a).
Use the direct `mcp__linear__*` tools, rather than the `codex_apps` connector.

- Workspace: `ivoxygen`.
- Team: `Ivoxygen` (`IVO`, ID `149c7831-e646-4972-8e83-4a9c24a652a5`).
- Project: `Mosh` (`P-IVO-2`). Scope issue searches and new issues to this project.

## Operations

- **Publish a spec/task**: check for an existing matching Linear issue, then
  create or update it through `save_issue`. On creation set the team and project;
  send Markdown with actual newlines. Apply the label required by the invoked
  skill using [the triage mapping](triage-labels.md).
- **Read a ticket**: use `get_issue` with its `IVO-*` identifier or Linear URL.
  Fetch comments and relations when they are relevant to the task.
- **Find work**: use `list_issues` with the Mosh project and relevant label,
  status, assignee or parent filters. Follow pagination.
- **Change a ticket**: use `save_issue` for status, assignee, labels and
  relations; preserve unrelated fields and existing labels. Use `save_comment`
  for an authorized comment. Read the available tool schema before calling it.
- **Complete work**: verify the result before setting `Done`. A readiness label
  is separate from workflow status and does not mean work has been implemented.
- **Verify publication**: read back the description, project, status and labels,
  then return the Linear identifier and URL.

If the direct Linear MCP is unavailable, keep the prepared spec locally and
report the access problem. Do not silently substitute GitHub Issues or another
connector. An explicit user instruction naming a different destination takes
precedence.

## GitHub boundary

GitHub remains the source of code, pull requests, reviews, CI and releases.
Use `gh` for those operations. **PRs as a request surface: no.**
Existing GitHub issue links remain valid historical context; read an explicitly
referenced GitHub issue when needed, but publish new project tasks/specs to
Linear. Include the `IVO-*` identifier in related PRs. A GitHub PR number and a
Linear issue identifier are different references.

When correcting a misplaced GitHub spec, verify its Linear replacement before
closing the duplicate and retain a link to the canonical ticket. Do not bulk
migrate or close unrelated historical issues.

## Wayfinding operations

- **Map**: one Linear issue labelled `wayfinder:map`, holding Notes,
  Decisions-so-far and Fog.
- **Child ticket**: create a Linear issue under the map with `parentId` and the
  appropriate `wayfinder:<type>` label (`research`, `prototype`, `grilling` or
  `task`). Retain the Mosh project and team.
- **Blocking**: use native Linear `blockedBy`/`blocks` relations. A ticket is
  unblocked when all blocking tickets are complete.
- **Frontier**: list the map's children, exclude completed/canceled tickets,
  tickets with an open blocker and tickets already assigned, then use map order.
- **Claim**: when the workflow calls for claiming work, set its assignee through
  `save_issue` before implementation.
- **Resolve**: record the verified answer/result, set the appropriate completion
  status and add a context pointer to the map's Decisions-so-far.
