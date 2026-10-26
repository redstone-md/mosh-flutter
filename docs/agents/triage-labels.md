# Triage Labels

The engineering skills speak in terms of five canonical triage roles. This
file maps those roles to the Linear label names for the Mosh project.

| Canonical role | Linear label | Meaning |
|---|---|---|
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified and ready for an agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation |
| `wontfix` | `wontfix` | Will not be actioned |

When a skill names a canonical role, use the corresponding Linear label above.
Discover labels in the `Ivoxygen` team scope as well as workspace labels;
workspace-only discovery can omit team labels. Reuse the exact existing label.
If an invoked workflow requires a missing canonical label, create only that
label in the team scope before applying it.

Keep triage labels separate from Linear workflow states. A newly specified
`ready-for-agent` task normally uses `Todo`; it must not be marked `In Progress`
or `Done` merely because its spec was published. Discover current states before
changing them. See [tracker instructions](issue-tracker.md) for the project and
direct MCP requirement.
