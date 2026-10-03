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
- [x] Device link workflow: shared action lock, proof-preserving errors,
  cancellation policy and stale-lifetime guards; 234 focused tests passed.
- [x] Conversation durable writes: accepted-row accounting and shared pending
  writes/dequeue; approved Rust Result contracts; real-store refusal/restart
  regressions. Full native run: 482 passed, 21 intentional skips. Review found
  and fixed post-publication DM file/voice errors; 113 DM tests passed afterward.
- [x] Saved network adapter choice: shared durable choice, action ownership,
  retained restart requirement and separate save/restart errors; 62 focused
  tests passed, with 99.4% changed-line and 94.6% branch coverage.
- [x] Conversation attachments: shared readiness, controls, progress, open
  and pending-open policy; voice playback retains intent through load/play
  failures. 353 focused tests passed; changed coverage: 91.9% lines,
  89.6% branches. Distinct cards and existing media_kit playback remain.

## Final verification

- Main Flutter suite: 1,277 passed, five existing skips; analysis has no issues.
  `dart format lib test integration_test`: 487 files, zero changes.
- Full changed-Dart coverage: 474/506 lines (93.68%) and 180/210 branches
  (85.71%). The native-command forwarding adapter is checked by native tests;
  Flutter workflow tests substitute commands below the real controller.
- Main native build, formatting and all-targets clippy with `-D warnings` passed.
  The full native suite passed 482 tests with 21 intentional helper skips before
  the attachment outcome fix. After that fix, all 113 DM tests and both new
  file/voice regressions passed; clippy and formatting were checked again.
- Approved native-patch coverage: 429/477 production lines (89.94%); all three
  subsequently added attachment-outcome lines have 100% narrow coverage.
- Flutter bridge generation using the CI flags passed in the native review
  checkout. Generated Dart/Rust bindings have exactly zero diff in main.
- `git diff --check` passed. Dependencies, database schemas and Moss sources
  remain unchanged. Each item has its own verified Conventional Commit.

## Review after integration

Frozen review: `0da4be1`, compared with starting commit `80e3514`.
Both axes used separate read-only agents. The final source matches the frozen
source apart from the fixes described below and completion documentation.

### Standards

- One documented violation: stale comments said Conversation called the old
  media-open helper. Resolved by identifying both retained opening helpers as
  legacy and naming `ConversationAttachment.openPlan` as the production owner.
- One heuristic, possible duplicated code: legacy pure-helper policies remain
  for existing consumers and tests. Production decisions now live together in
  Conversation; the retained helpers explicitly document their older path-only
  semantics. No tracked helper or contract was deleted.
- Re-review confirmed no remaining blocking Standards findings.

### Spec

- One P1: DM attachments propagated a persistence refusal after their manifest
  had already published. Resolved by retaining/logging the pending write and
  returning the successful transport outcome, matching group/channel behavior.
- File and voice regressions first failed, then passed against encrypted redb.
  They check peer receipt, storage repair, one restored history row, content
  hash, voice metadata and sender cache availability. The complete DM suite
  passed 113 tests afterward. All three added production lines were covered.
- Re-review confirmed the approved post-publication policy and no new findings.

Standards: one hard finding resolved, one heuristic documented; Spec: one P1
resolved. Neither axis has a remaining blocking issue.

## Remaining limits

- Physical filesystem/I/O failure can poison redb and require database reopening.
  Automatic reopening is outside this change. Closing before a refused write is
  accepted preserves the previous durable state and can lose the unsaved update.
- Changed exported Rust helpers require Result handling and additional native
  Persistence error arms. The user approved these changes; internal callers and
  generated bridge drift were verified.
- Native Windows/Android UI and actual media decoding were not exercised on
  physical devices. Widget tests use real owners and the existing bridge/player
  seams; native persistence, crypto and integration tests use existing dependencies.
- Rust branch coverage is unavailable with the installed stable tooling.

## Changed files

73 architecture files at `724b410`, relative to `80e3514`.

- [GLOSSARY.md](../GLOSSARY.md)
- [docs/ADR/0029-private-desktop-device-linking.md](../docs/ADR/0029-private-desktop-device-linking.md)
- [docs/ADR/0037-conversation-write-acceptance.md](../docs/ADR/0037-conversation-write-acceptance.md)
- [docs/Architecture.md](../docs/Architecture.md)
- [docs/Features/first-run-setup.md](../docs/Features/first-run-setup.md)
- [docs/architecture-deepening.plan.md](../docs/architecture-deepening.plan.md)
- [lib/src/features/conversation/attachment_actions.dart](../lib/src/features/conversation/attachment_actions.dart)
- [lib/src/features/conversation/attachment_card.dart](../lib/src/features/conversation/attachment_card.dart)
- [lib/src/features/conversation/attachment_card_branches.dart](../lib/src/features/conversation/attachment_card_branches.dart)
- [lib/src/features/conversation/conversation_attachment.dart](../lib/src/features/conversation/conversation_attachment.dart)
- [lib/src/features/conversation/conversation_controller.dart](../lib/src/features/conversation/conversation_controller.dart)
- [lib/src/features/conversation/conversation_shared_file.dart](../lib/src/features/conversation/conversation_shared_file.dart)
- [lib/src/features/conversation/voice_message_card.dart](../lib/src/features/conversation/voice_message_card.dart)
- [lib/src/features/device_link/device_link_commands.dart](../lib/src/features/device_link/device_link_commands.dart)
- [lib/src/features/device_link/device_link_copy.dart](../lib/src/features/device_link/device_link_copy.dart)
- [lib/src/features/device_link/device_link_provider.dart](../lib/src/features/device_link/device_link_provider.dart)
- [lib/src/features/device_link/device_link_state.dart](../lib/src/features/device_link/device_link_state.dart)
- [lib/src/features/device_link/devices_settings_section.dart](../lib/src/features/device_link/devices_settings_section.dart)
- [lib/src/features/onboarding/first_run_device_step.dart](../lib/src/features/onboarding/first_run_device_step.dart)
- [lib/src/features/onboarding/first_run_network_form.dart](../lib/src/features/onboarding/first_run_network_form.dart)
- [lib/src/features/onboarding/first_run_network_provider.dart](../lib/src/features/onboarding/first_run_network_provider.dart)
- [lib/src/features/onboarding/first_run_provider.dart](../lib/src/features/onboarding/first_run_provider.dart)
- [lib/src/features/shared/attachment_media_src.dart](../lib/src/features/shared/attachment_media_src.dart)
- [lib/src/features/vpn/bind_interface_field.dart](../lib/src/features/vpn/bind_interface_field.dart)
- [lib/src/features/vpn/network_choice_provider.dart](../lib/src/features/vpn/network_choice_provider.dart)
- [lib/src/features/vpn/vpn_consent_modal.dart](../lib/src/features/vpn/vpn_consent_modal.dart)
- [lib/src/state/auto_poll_provider.dart](../lib/src/state/auto_poll_provider.dart)
- [lib/src/state/conversation_providers.dart](../lib/src/state/conversation_providers.dart)
- [mosh-core/src/api/conversation_bridge.rs](../mosh-core/src/api/conversation_bridge.rs)
- [mosh-core/src/channel_runtime.rs](../mosh-core/src/channel_runtime.rs)
- [mosh-core/src/channel_runtime/durability_tests.rs](../mosh-core/src/channel_runtime/durability_tests.rs)
- [mosh-core/src/channel_runtime/lifecycle.rs](../mosh-core/src/channel_runtime/lifecycle.rs)
- [mosh-core/src/channel_runtime/types.rs](../mosh-core/src/channel_runtime/types.rs)
- [mosh-core/src/conversation/history.rs](../mosh-core/src/conversation/history.rs)
- [mosh-core/src/conversation/history_tests.rs](../mosh-core/src/conversation/history_tests.rs)
- [mosh-core/src/conversation/outbound.rs](../mosh-core/src/conversation/outbound.rs)
- [mosh-core/src/conversation/runtime.rs](../mosh-core/src/conversation/runtime.rs)
- [mosh-core/src/conversation/runtime_tests.rs](../mosh-core/src/conversation/runtime_tests.rs)
- [mosh-core/src/conversation/runtime_tests/durability.rs](../mosh-core/src/conversation/runtime_tests/durability.rs)
- [mosh-core/src/conversation/runtime_writes.rs](../mosh-core/src/conversation/runtime_writes.rs)
- [mosh-core/src/persistence.rs](../mosh-core/src/persistence.rs)
- [mosh-core/src/persistence/test_faults.rs](../mosh-core/src/persistence/test_faults.rs)
- [mosh-core/src/private_dm_runtime.rs](../mosh-core/src/private_dm_runtime.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests.rs](../mosh-core/src/private_dm_runtime/devices/history/packet_tests.rs)
- [mosh-core/src/private_dm_runtime/devices/history/packet_tests/recovery.rs](../mosh-core/src/private_dm_runtime/devices/history/packet_tests/recovery.rs)
- [mosh-core/src/private_dm_runtime/devices/rejoin.rs](../mosh-core/src/private_dm_runtime/devices/rejoin.rs)
- [mosh-core/src/private_dm_runtime/durability_tests.rs](../mosh-core/src/private_dm_runtime/durability_tests.rs)
- [mosh-core/src/private_dm_runtime/durability_tests/attachments.rs](../mosh-core/src/private_dm_runtime/durability_tests/attachments.rs)
- [mosh-core/src/private_dm_runtime/outbox.rs](../mosh-core/src/private_dm_runtime/outbox.rs)
- [mosh-core/src/private_dm_runtime/session.rs](../mosh-core/src/private_dm_runtime/session.rs)
- [mosh-core/src/private_dm_runtime/state_tests.rs](../mosh-core/src/private_dm_runtime/state_tests.rs)
- [mosh-core/src/private_group_runtime.rs](../mosh-core/src/private_group_runtime.rs)
- [mosh-core/src/private_group_runtime/durability_tests.rs](../mosh-core/src/private_group_runtime/durability_tests.rs)
- [mosh-core/src/private_group_runtime/error.rs](../mosh-core/src/private_group_runtime/error.rs)
- [mosh-core/src/private_group_runtime/lifecycle.rs](../mosh-core/src/private_group_runtime/lifecycle.rs)
- [mosh-core/src/private_group_runtime/runtime_tests.rs](../mosh-core/src/private_group_runtime/runtime_tests.rs)
- [test/features/conversation/attachment_actions_test.dart](../test/features/conversation/attachment_actions_test.dart)
- [test/features/conversation/attachment_behavior_test.dart](../test/features/conversation/attachment_behavior_test.dart)
- [test/features/conversation/voice_message_card_test.dart](../test/features/conversation/voice_message_card_test.dart)
- [test/features/conversation/voice_message_readiness_test.dart](../test/features/conversation/voice_message_readiness_test.dart)
- [test/features/device_link/device_link_refresh_test.dart](../test/features/device_link/device_link_refresh_test.dart)
- [test/features/device_link/device_link_workflow_test.dart](../test/features/device_link/device_link_workflow_test.dart)
- [test/features/onboarding/first_run_device_pending_test.dart](../test/features/onboarding/first_run_device_pending_test.dart)
- [test/features/onboarding/first_run_provider_test.dart](../test/features/onboarding/first_run_provider_test.dart)
- [test/features/onboarding/first_run_wizard_test.dart](../test/features/onboarding/first_run_wizard_test.dart)
- [test/features/vpn/network_choice_prompt_test.dart](../test/features/vpn/network_choice_prompt_test.dart)
- [test/features/vpn/network_choice_remount_test.dart](../test/features/vpn/network_choice_remount_test.dart)
- [test/features/vpn/network_choice_test.dart](../test/features/vpn/network_choice_test.dart)
- [test/state/conversation_refresh_test.dart](../test/state/conversation_refresh_test.dart)
- [test/support/device_link_workflow.dart](../test/support/device_link_workflow.dart)
- [test/support/first_run.dart](../test/support/first_run.dart)
- [test/support/scriptable_device_link.dart](../test/support/scriptable_device_link.dart)
- [test/support/scripted_calls.dart](../test/support/scripted_calls.dart)
