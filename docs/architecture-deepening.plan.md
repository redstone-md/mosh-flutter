# Architecture deepening

Approved sequence from the architecture review, 2026-10-03. Implement and
verify each item before committing it and continuing to the next.

## Scope and test seams

1. Conversation refresh: the existing list notifier interface owns overlapping
   reads. Background polls skip busy reads; requests after mutations retain a
   subsequent fresh read. Test real notifier state through scripted bridge
   responses, including rebuild/disposal and independent conversation kinds.
2. Device link: one workflow owns pending actions and safe continuation. Test
   the real workflow through delayed native-command responses, plus first-run
   controls and durable setup progress. Rust retains identity and approval.
3. Conversation durable writes: save outcomes govern publication, persisted
   counts and record finalization. Test real redb failures and runtime restart
   behavior. Review any public Rust contract changes before applying them.
4. Saved network adapter choice: share persistence, write outcomes and restart
   knowledge. Test shared policy and existing Settings/setup/consent behavior.
   Setup still completes durably before restart; saved and live differ.
5. Conversation attachments: concentrate transfer interpretation and allowed
   actions inside Conversation. Test message and shared-file transitions.
   Keep rendering distinct; native playback ordering gets its own focused test.

## Constraints and checks

Preserve ADRs, generated bridge contracts, dependencies and storage schemas.
No changes to Moss. No deletion of tracked modules without review.

For each bug, first run a caller-visible regression test and observe failure.
Run focused tests and changed-code coverage, formatter and Flutter analysis.
After Dart work run the full Flutter suite. Before native tests prepare Moss,
build Rust, then run formatting, clippy and native tests. Review changes against
this plan and AGENTS.md. Use one atomic Conventional Commit per item.

## Progress

- [x] Conversation refresh: notifier-owned ordering and caller-visible tests.
- [ ] Device link workflow
- [ ] Conversation durable writes
- [ ] Saved network adapter choice
- [ ] Conversation attachments
