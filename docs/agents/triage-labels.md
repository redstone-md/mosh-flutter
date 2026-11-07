# Triage Labels

The engineering skills speak in terms of five canonical triage roles. This
file maps those roles to the itsaplan label names in the `MOSH` project.

| Canonical role | itsaplan label | Meaning |
|---|---|---|
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified and ready for an agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation |
| `wontfix` | `wontfix` | Will not be actioned |

When a skill names a canonical role, use the corresponding label above. Labels
are per project: read the current ones with `get_project` and reuse the exact
existing label. The project has `ready-for-agent` and `ready-for-human`; if an
invoked workflow requires a missing canonical label, create only that label in
the `MOSH` project before applying it.

Keep triage labels separate from columns. A newly specified `ready-for-agent`
task normally goes to Todo; it must not be moved to In Progress or Done merely
because its spec was published. See [tracker instructions](issue-tracker.md)
for the project and its columns.
