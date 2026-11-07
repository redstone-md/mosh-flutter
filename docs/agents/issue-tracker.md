# Issue tracker: itsaplan

The canonical tracker for this repository is the `Mosh` project in itsaplan:
project key `MOSH` (team `Redstone`, ref `redstone.MOSH`). Issues are named
`MOSH-<number>`. Use the `mcp__itsaplan__*` tools. Linear is no longer used.

Ids other than the issue key (columns, types, labels, members) are per
project: resolve them with `get_project` and never reuse them from memory.

## States

Select a column by its `stateType`, not its name. In Progress and In Review
share `started`, so between those two pick by name from `get_project`:

| Column | `stateType` | Use |
|---|---|---|
| Backlog | `backlog` | Captured, not planned |
| Todo | `unstarted` | Specified and planned |
| In Progress | `started` | Work has begun |
| In Review | `started` | A PR is open |
| Done | `completed` | Verified result |
| Canceled | `canceled` | Not done |

## Operations

- **Read a ticket**: `get_issue_by_number` with `projectKey: "MOSH"` and the
  number. It returns the internal id other tools take, the subtasks and links.
  Read comments with `list_issue_activity` when they matter.
- **Find work**: `list_issues` with `projectKey: "MOSH"` and column, label,
  type or `parentId` filters; `search_issues` for text.
- **Publish a spec/task**: check for an existing matching issue, then
  `create_issue` or `update_issue`. Send Markdown with actual newlines. Apply
  the label required by the invoked skill using
  [the triage mapping](triage-labels.md).
- **Change a ticket**: `update_issue` for column, assignee, labels and parent;
  it replaces the label list, so keep the existing labels. `add_comment` only
  for an authorized comment.
- **Work on a ticket**: move it to In Progress when work starts and to In Review
  when its PR opens. Set Done only after the result is verified; a readiness
  label is separate from the column and does not mean the work is done.
- **Verify publication**: read back the description, column and labels, then
  return the `MOSH-<number>` key.

If the itsaplan MCP is unavailable, keep the prepared spec locally and report
the access problem. Do not silently substitute GitHub Issues or another
tracker. An explicit user instruction naming a different destination takes
precedence.

## GitHub boundary

GitHub remains the source of code, pull requests, reviews, CI and releases.
Use `gh` for those operations. **PRs as a request surface: no.**
Existing GitHub issue links and older Linear `IVO-*` references remain valid
historical context; publish new project tasks/specs to itsaplan. Put the
`MOSH-<number>` key in related PRs. A GitHub PR number and an itsaplan issue
key are different references.

When correcting a misplaced GitHub spec, verify its itsaplan replacement before
closing the duplicate and retain a link to the canonical ticket. Do not bulk
migrate or close unrelated historical issues.

## Wayfinding operations

- **Map**: one issue labelled `wayfinder:map`, holding Notes,
  Decisions-so-far and Fog.
- **Child ticket**: an issue with `parentId` set to the map and the
  appropriate `wayfinder:<type>` label (`research`, `prototype`, `grilling` or
  `task`).
- **Blocking**: `link_issues` with a `blocks` link. A ticket is unblocked when
  every issue blocking it is in a `completed` column.
- **Frontier**: list the map's subtasks, exclude completed/canceled tickets,
  tickets with an open blocker and tickets already assigned, then use map order.
- **Claim**: when the workflow calls for claiming work, set its assignee with
  `update_issue` before implementation.
- **Resolve**: record the verified answer/result, move it to the right
  completed or canceled column and add a context pointer to the map's
  Decisions-so-far.
