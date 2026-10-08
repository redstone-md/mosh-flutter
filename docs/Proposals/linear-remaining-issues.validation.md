# Remaining Linear issues: implementation report

Completed 2026-10-08 on `fix/linear-remaining-issues`. Initial verification used
`9da03059`; PR preparation rebased onto `3215ce09` with the current start menu.
Scope and accepted behavior are in [the plan](linear-remaining-issues.plan.md).
The implementation covers IVO-48, IVO-49, IVO-51 and IVO-52.

## Result

Message rows retain focus, selection and keyboard actions without the outline.
Ordinary dialogs share one compact component and route transition; VPN consent
retains its existing overlay owner. Confirmation titles use conversation names
or a generic localized title.

Saved invitations are durable native sessions with separate recent-list
visibility. Opening or validated counterpart admission exposes the same chat.
Replacement changes the signed admission token, preserves the route and keys,
and commits before returning. The native availability flag owns invite actions.
New compact links retain both ownership signatures and are 294 to 348 characters.
Cards show two URI lines and copy the entire URI.

## Verification

All execution was performed by the integration owner. Subagents worked in
separate worktrees and wrote code/tests without running tests or compilation.

| Check | Result |
| --- | --- |
| `node scripts/moss-prepare.mjs` | Passed |
| Rust build | Passed |
| `flutter analyze --no-pub` | No issues |
| `flutter test --no-pub --branch-coverage` | 1778 passed, 4 skipped |
| `dart format lib test integration_test --set-exit-if-changed` | 639 files, zero changes |
| `cargo fmt --manifest-path mosh-core/Cargo.toml -- --check` | Passed |
| `cargo clippy --manifest-path mosh-core/Cargo.toml --all-targets -- -D warnings` | Passed |
| Full native suite through `scripts/moss-test.mjs` with LLVM instrumentation | 695 unit tests and 48 integration tests passed; 27 ignored |
| Native invitation rerun after review fix | 19 passed, including 3 new legacy/replay regressions |
| Final real-Moss invitation integration rerun | 4 passed, 1 worker entry ignored |
| `flutter_rust_bridge_codegen generate`, regenerated-file hash comparison | Zero drift |
| `flutter build linux --debug --no-pub` | Passed |
| Real-font widget previews | Checked ordinary confirmation and saved invite at desktop and phone widths |

The full native run preceded the final metadata-replay fix. Its focused rerun
covers the affected admission/restore code and the final real-Moss rerun covers
creation, rotation, persistence, first admission and bidirectional messaging.

Coverage compares executable added/changed lines against `9da03059`, including
new modules and excluding generated bindings and tests. Dart covers 566/580
lines, 97.6%, and 168/188 branches, 89.4%. Rust covers 565/613 lines, 92.2%.
Rust branch instrumentation requires a nightly compiler; the pinned stable
1.96.0 toolchain provides line coverage here.

## Review and simplifications

Independent reviews checked the accepted behavior and repository standards.
They found a consumed-invitation replay could overwrite contact metadata.
The fix preserves established metadata on retries and validates legacy signers
against actual counterpart MLS membership. Three regressions cover outsider
admission, legitimate retry and altered unsigned replay metadata across restart.
The reviewers rechecked the fix and reported no remaining blocking finding.

Dialogs share Flutter's existing modal, focus and scroll ownership. Invitation
persistence reuses the existing encrypted records and atomic MLS transition.
No dependency or database table was added. Group/org offer creation keeps its
existing entry point. Test workers import the existing crypto and stdio helpers.

## Remaining limits

Older application versions cannot read new compact links. This version still
reads legacy links and saved records. Linux compilation and native execution
were verified here; Windows, macOS and physical mobile devices were not run.

## PR preparation

Rebased onto `3215ce09`, preserving the current inline start menu, invitation
field, group footer and Copy feedback. Saved DM invitations use the same layout
with compact Copy/Open/Replace actions. The start menu owns navigation after
native opening; Back cancels late navigation while the chat remains durable.
A regression reproduced the stale navigation before the owner check was added.

After integration, Flutter analysis, Linux debug build, strict Clippy and both
format checks passed. The full Flutter branch-coverage run passed 1802 tests
with 4 skipped. The current start-menu preview also passed and its created-chat
view was inspected with real fonts. Native runtime sources and generated bridge
bindings are identical to the previously verified implementation.

Coverage against the rebased main covers 567/581 changed Dart lines, 97.6%,
and 172/193 branches, 89.1%. Native coverage remains 565/613 lines, 92.2%.

## PR review and CI follow-up

Fetched all review threads, reviews and general comments for PR #69. Its one
unresolved inline CodeAnt finding was valid: the Message action discarded its
future while creation or publication could fail. The button now awaits that
future and uses the existing localized error reporter, captured before closing
the dialog. A regression failed with an unhandled error before the fix and
passed afterward; all seven sender-meta widget tests passed.

The custom-mesh nitpick was also valid. Both restored and newly created fake
invitations now pass their mesh into the shared snapshot factory. Two regressions
failed before the fix and passed after it, covering replacement and opening.
The combined bridge, saved-invitation and sender-meta run passed 29 tests.

The legacy-Welcome nitpick describes an older record that lost its initial
Welcome before an old-version restart. That record cannot reconstruct the
missing Welcome. Returning an error only logs locally; re-adding the member
would change MLS membership and violate admission guarantees. Already joined
legacy peers use authenticated Hello. New admissions already persist Welcome
atomically and have a restart/retry regression. The legacy limit is now explicit
in the invitation documentation; admission behavior is preserved.

Both failing Rust CI jobs had the same obsolete expectation: a repeated
KeyPackage could change an established address through unsigned fields. The
updated real-Moss regression verifies that retry preserves the address and a
real MLS-encrypted Hello changes it and marks it for persistence. No runtime
behavior was weakened. The full unit run passed 698 tests with 18 ignored;
build, strict Clippy, analysis and format checks passed. Independent Standards
and Spec reviews of the follow-up patch reported no findings.

The full Flutter rerun passed 1805 tests with 4 skipped. The full native rerun
passed 698 unit and 48 integration tests, with 27 ignored. The invitation runtime
and bridge contracts are unchanged by this follow-up; native coverage remains
92.2% of changed executable lines.

macOS Rust CI passed after the address regression update. Windows then exposed
an independent test-isolation failure: the channel deletion fixture reused a
room and accepted a prior fixture's frame from the process-wide inbox. Queuing
that signed frame reproduced the exact empty-chat assertion without timing
dependencies. The fixture now clears the inbox on creation, matching neighboring
tests. Both attachment-lifetime assertions and the strict empty-chat assertion
remain intact. All eight channel deletion tests, the repeated full unit suite
(698 passed, 18 ignored) and strict Clippy passed.
Review found no behavior issue. Test-file exception:
`mosh-core/src/channel_runtime/runtime_tests/deletion.rs` is 412 lines. The
signed-frame setup belongs to its existing attachment-cache regression and
shares that fixture.

## Changed files

- `docs/ADR/0042-durable-compact-dm-invitations.md`
- `docs/Architecture.md`
- `docs/Features/dialogs.md`
- `docs/Features/invitations.md`
- `docs/Features/message-context-menus.md`
- `docs/Features/private-dm.md`
- `docs/Proposals/linear-remaining-issues.plan.md`
- `docs/Proposals/linear-remaining-issues.validation.md`
- `docs/README.md`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ru.arb`
- `lib/src/features/conversation/conversation_leave_prompt.dart`
- `lib/src/features/conversation/conversation_sender_meta.dart`
- `lib/src/features/conversation/dm_screen_header.dart`
- `lib/src/features/conversation/message_copy.dart`
- `lib/src/features/conversation/message_selection_host.dart`
- `lib/src/features/conversation/rename_chat_dialog.dart`
- `lib/src/features/fingerprint/fingerprint_lock.dart`
- `lib/src/features/onboarding/chat_create_step.dart`
- `lib/src/features/onboarding/first_run_network_form.dart`
- `lib/src/features/onboarding/invite_result.dart`
- `lib/src/features/onboarding/new_session_panel.dart`
- `lib/src/features/onboarding/pending_invitation_card.dart`
- `lib/src/features/shared/confirm_dialog.dart`
- `lib/src/features/shared/mosh_dialog.dart`
- `lib/src/features/shared/mosh_dialog_motion.dart`
- `lib/src/features/shared/mosh_dialog_route.dart`
- `lib/src/features/vpn/vpn_consent_modal.dart`
- `lib/src/gateway/bridge_facade.dart`
- `lib/src/invite/invite_uri.dart`
- `lib/src/rust/api/private_dm.dart`
- `lib/src/rust/frb_generated.dart`
- `lib/src/rust/frb_generated.io.dart`
- `lib/src/rust/frb_generated.web.dart`
- `lib/src/rust/private_dm_runtime/contracts.dart`
- `lib/src/state/pending_invites_provider.dart`
- `lib/src/state/session_providers.dart`
- `mosh-core/src/api/private_dm.rs`
- `mosh-core/src/channel_runtime/runtime_tests/deletion.rs`
- `mosh-core/src/frb_generated.rs`
- `mosh-core/src/private_dm_runtime.rs`
- `mosh-core/src/private_dm_runtime/actions.rs`
- `mosh-core/src/private_dm_runtime/admission_authentication.rs`
- `mosh-core/src/private_dm_runtime/compact_invite.rs`
- `mosh-core/src/private_dm_runtime/compact_invite_tests.rs`
- `mosh-core/src/private_dm_runtime/contracts.rs`
- `mosh-core/src/private_dm_runtime/contracts/persistence.rs`
- `mosh-core/src/private_dm_runtime/control.rs`
- `mosh-core/src/private_dm_runtime/devices/types.rs`
- `mosh-core/src/private_dm_runtime/invitation_admission.rs`
- `mosh-core/src/private_dm_runtime/invitation_legacy_tests.rs`
- `mosh-core/src/private_dm_runtime/invitation_recovery_tests.rs`
- `mosh-core/src/private_dm_runtime/invitation_tests.rs`
- `mosh-core/src/private_dm_runtime/invitations.rs`
- `mosh-core/src/private_dm_runtime/invite.rs`
- `mosh-core/src/private_dm_runtime/invite_ownership.rs`
- `mosh-core/src/private_dm_runtime/lifecycle.rs`
- `mosh-core/src/private_dm_runtime/pending_join.rs`
- `mosh-core/src/private_dm_runtime/runtime_tests/handshake.rs`
- `mosh-core/src/private_dm_runtime/runtime_tests/peer_discovery.rs`
- `mosh-core/src/private_dm_runtime/session.rs`
- `mosh-core/src/private_dm_runtime/session_transport.rs`
- `mosh-core/src/private_dm_runtime/snapshot.rs`
- `mosh-core/src/private_dm_runtime/state_tests/restore.rs`
- `mosh-core/src/private_dm_runtime/wire.rs`
- `mosh-core/tests/dm_invitation_lifecycle_flow.rs`
- `mosh-core/tests/invitation_support/mod.rs`
- `mosh-core/tests/invitation_support/worker.rs`
- `mosh-core/tests/link_support/mod.rs`
- `test/chat_rename_test.dart`
- `test/features/conversation/conversation_leave_prompt_test.dart`
- `test/features/conversation/dm_screen_voice_call_error_test.dart`
- `test/features/conversation/group_leave_label_test.dart`
- `test/features/conversation/message_focus_test.dart`
- `test/features/conversation/peer_label_test.dart`
- `test/features/conversation/peer_nickname_test.dart`
- `test/features/conversation/peer_status_drawer_test.dart`
- `test/features/conversation/pending_dm_invitation_test.dart`
- `test/features/conversation/typing_hint_test.dart`
- `test/features/diagnostics/diagnostics_sections_test.dart`
- `test/features/diagnostics/diagnostics_summary_test.dart`
- `test/features/diagnostics/summary_card_test.dart`
- `test/features/onboarding/chat_create_screen_test.dart`
- `test/features/onboarding/pending_invitation_test.dart`
- `test/features/routing/shell_harness.dart`
- `test/features/sessions/rail_conversation_keys_test.dart`
- `test/features/sessions/sessions_new_action_test.dart`
- `test/features/sessions/sessions_screen_active_highlight_test.dart`
- `test/features/sessions/sessions_screen_support.dart`
- `test/features/shared/confirm_dialog_test.dart`
- `test/features/shared/mosh_dialog_test.dart`
- `test/features/voice_call/call_overlay_test.dart`
- `test/features/vpn/vpn_consent_modal_test.dart`
- `test/invite/compact_invite_test.dart`
- `test/state/conversation_providers_test.dart`
- `test/state/unread_lifecycle_provider_support.dart`
- `test/state/unread_providers_test.dart`
- `test/state/voice_call_orchestrator_provider_support.dart`
- `test/support/conversation_cases.dart`
- `test/support/gateway_snapshots.dart`
- `test/support/message_builders.dart`
- `test/support/scriptable_bridge.dart`
- `test/support/scriptable_bridge_test.dart`
- `test/support/scriptable_bridge_conversations.dart`
- `test/support/scriptable_bridge_invitations.dart`
- `test/support/scripted_conversations.dart`
