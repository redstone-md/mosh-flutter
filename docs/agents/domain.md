# Domain Docs

How engineering skills should consume this repo's domain documentation when
exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repository root.
- **`CONTEXT-MAP.md`** at the repository root if it is added later; it points at one `CONTEXT.md` per context. Read each file relevant to the topic.
- **`docs/ADR/`**; read the ADRs that touch the area being changed.

If one of these files does not exist, proceed silently. Do not flag its absence
or suggest creating it upfront. Domain documentation should be created lazily
when terms or decisions are actually resolved.

## File structure

This is a single-context repository:

```text
/
├── CONTEXT.md
├── docs/ADR/
│   ├── 0001-openmls-private-dm-adapter.md
│   └── 0024-the-bridge-names-shared-conversation-actions.md
├── lib/
├── mosh-core/
└── moss/
```

There is currently no `CONTEXT-MAP.md` and no context-scoped `docs/ADR/`
directory.

## Use the glossary's vocabulary

When output names a domain concept — in an issue title, refactor proposal,
hypothesis, or test name — use the term as defined in `CONTEXT.md`. Do not
silently drift to synonyms that the glossary explicitly avoids.

If the needed concept is not in the glossary, that signals either invented
language that should be reconsidered or a real gap to note for domain modeling.

## Flag ADR conflicts

If output contradicts an existing ADR, surface it explicitly rather than
silently overriding it:

> _Contradicts ADR-0007 — but worth reopening because…_
