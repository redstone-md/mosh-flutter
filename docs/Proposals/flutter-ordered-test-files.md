# Ordered test cleanup: changed files

Code comparison: `c5076e3f` -> `31b6fbc7`. See the
[execution report](flutter-ordered-test-cleanup.md) for contracts, source proof,
commands and measurements. Production, manifests, CI, native/integration tests,
scripts and the policy implementation are unchanged.

## Test files

| Change | Original path | Current path |
| --- | --- | --- |
| Modified | `—` | [test/features/conversation/attachment_ownership_test.dart](../../test/features/conversation/attachment_ownership_test.dart) |
| Modified | `—` | [test/features/conversation/clipboard_file_paste_test.dart](../../test/features/conversation/clipboard_file_paste_test.dart) |
| Modified | `—` | [test/features/conversation/conversation_attachment_test.dart](../../test/features/conversation/conversation_attachment_test.dart) |
| Modified | `—` | [test/features/conversation/conversation_filter_test.dart](../../test/features/conversation/conversation_filter_test.dart) |
| New scoped driver | `—` | [test/features/conversation/conversation_inline_widgets_test.dart](../../test/features/conversation/conversation_inline_widgets_test.dart) |
| Rename + documented edits | `test/features/conversation/conversation_search_box_test.dart` | [test/features/conversation/conversation_search_box_cases.dart](../../test/features/conversation/conversation_search_box_cases.dart) |
| Modified | `—` | [test/features/conversation/peer_status_drawer_test.dart](../../test/features/conversation/peer_status_drawer_test.dart) |
| Rename unchanged | `test/features/conversation/typing_hint_test.dart` | [test/features/conversation/typing_hint_cases.dart](../../test/features/conversation/typing_hint_cases.dart) |
| Rename + documented edits | `test/features/conversation/unread_badge_test.dart` | [test/features/conversation/unread_badge_cases.dart](../../test/features/conversation/unread_badge_cases.dart) |
| Rename unchanged | `test/features/device_link/device_list_test.dart` | [test/features/device_link/device_list_cases.dart](../../test/features/device_link/device_list_cases.dart) |
| New scoped driver | `—` | [test/features/device_link/device_list_contract_test.dart](../../test/features/device_link/device_list_contract_test.dart) |
| Rename unchanged | `test/features/device_link/device_revocation_test.dart` | [test/features/device_link/device_revocation_cases.dart](../../test/features/device_link/device_revocation_cases.dart) |
| Rename unchanged | `test/features/diagnostics/channel_group_diagnostics_test.dart` | [test/features/diagnostics/channel_group_diagnostics_cases.dart](../../test/features/diagnostics/channel_group_diagnostics_cases.dart) |
| New scoped driver | `—` | [test/features/diagnostics/diagnostics_network_events_test.dart](../../test/features/diagnostics/diagnostics_network_events_test.dart) |
| Rename + documented edits | `test/features/diagnostics/diagnostics_sections_test.dart` | [test/features/diagnostics/diagnostics_sections_cases.dart](../../test/features/diagnostics/diagnostics_sections_cases.dart) |
| Rename unchanged | `test/features/diagnostics/diagnostics_summary_test.dart` | [test/features/diagnostics/diagnostics_summary_cases.dart](../../test/features/diagnostics/diagnostics_summary_cases.dart) |
| New scoped driver | `—` | [test/features/diagnostics/diagnostics_summary_contract_test.dart](../../test/features/diagnostics/diagnostics_summary_contract_test.dart) |
| Rename + documented edits | `test/features/diagnostics/event_log_test.dart` | [test/features/diagnostics/event_log_cases.dart](../../test/features/diagnostics/event_log_cases.dart) |
| Rename + documented edits | `test/features/diagnostics/mesh_diagnostics_test.dart` | [test/features/diagnostics/mesh_diagnostics_cases.dart](../../test/features/diagnostics/mesh_diagnostics_cases.dart) |
| Rename unchanged | `test/features/diagnostics/summary_card_test.dart` | [test/features/diagnostics/summary_card_cases.dart](../../test/features/diagnostics/summary_card_cases.dart) |
| New scoped driver | `—` | [test/features/fingerprint/fingerprint_contract_test.dart](../../test/features/fingerprint/fingerprint_contract_test.dart) |
| Rename unchanged | `test/features/fingerprint/fingerprint_emoji_test.dart` | [test/features/fingerprint/fingerprint_emoji_cases.dart](../../test/features/fingerprint/fingerprint_emoji_cases.dart) |
| Rename unchanged | `test/features/fingerprint/fingerprint_lock_test.dart` | [test/features/fingerprint/fingerprint_lock_cases.dart](../../test/features/fingerprint/fingerprint_lock_cases.dart) |
| Modified | `—` | [test/features/onboarding/channel_join_screen_cases.dart](../../test/features/onboarding/channel_join_screen_cases.dart) |
| Modified | `—` | [test/features/onboarding/chat_create_screen_cases.dart](../../test/features/onboarding/chat_create_screen_cases.dart) |
| Modified | `—` | [test/features/onboarding/group_create_screen_cases.dart](../../test/features/onboarding/group_create_screen_cases.dart) |
| Modified | `—` | [test/features/sessions/rail_insets_test.dart](../../test/features/sessions/rail_insets_test.dart) |
| Modified | `—` | [test/features/settings/connection_reopen_test.dart](../../test/features/settings/connection_reopen_test.dart) |

## Documentation

- [Execution report](flutter-ordered-test-cleanup.md): decisions, exact deltas and measurements.
- [Starting audit](flutter-test-audit-2026-11-02.md): historical baseline, with follow-through link.
- [Starting 92-case inventory](flutter-test-audit-2026-11-02-inventory.md): original identities, with current case-library links.
- [Testing policy](../testing.md): points to completed work; rules stay unchanged.
- This changed-file index.

The thirteen original libraries remain separate. Five grouped owners replace
thirteen worker entry points. Fourteen MERGE and five justified DELETE decisions
reduce 1890 -> 1871 executed cases; the same four native-library gates remain.
Three existing cases are strengthened/synchronized; no deletion-confirmation
test, production behavior, dependency or extra required CLI is added.
