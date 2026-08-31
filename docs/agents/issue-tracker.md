# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues in
`redstone-md/mosh-flutter`. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Keep commands on one line; for longer bodies, use `--body-file <path>`.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` when needed and fetching labels as part of the issue data.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`.
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

Infer the repo from `git remote -v`; `gh` resolves the current repository
when run inside this clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** Set this to `yes` only if this repo treats
external PRs as feature requests; `/triage` reads this flag.

When set to `yes`, PRs run through the same labels and states as issues, using
the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>`.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`, then keep only authors with `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE`.
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label` / `--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs. Resolve a bare `#42`
with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as
tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. Create it with `gh issue create --label wayfinder:map`.
- **Child ticket**: link the issue to the map as a GitHub sub-issue through the sub-issues API. If sub-issues are unavailable, put `Part of #<map>` at the top of the child body and add the child to a task list in the map body. Use `wayfinder:<type>` labels (`research`, `prototype`, `grilling`, or `task`). Once claimed, assign the ticket to the driving developer.
- **Blocking**: use GitHub native issue dependencies as the canonical UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric database id, not its issue number or node id. If dependencies are unavailable, put `Blocked by: #<n>, #<n>` at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children, drop any with an open blocker or an assignee, and choose the first remaining ticket in map order.
- **Claim**: `gh issue edit <n> --add-assignee @me` is the session's first write.
- **Resolve**: comment with the answer, close the issue, then append a context pointer to the map's Decisions-so-far.
