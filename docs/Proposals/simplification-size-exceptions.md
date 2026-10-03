# Simplification size exceptions

Inventory of changed/new authored files after simplification. Every authored application and test file remains within 400 lines. These exceptions retain existing state ownership, declarative trees, ordered transactions and complete test proofs; they do not authorize larger future helpers. Counts include signatures, body lines, comments and blank lines, excluding preceding attributes/doc comments. Function bodies labeled unchanged match baseline modulo whitespace; moved tests retain their full proof.

15 production functions exceed 50 lines. No struct, enum or trait declaration exceeds 200 lines.

## Production

| Path:line | Function | Lines | Why retained |
| --- | --- | ---: | --- |
| `mosh-core/src/api/voice_call_playback.rs:254` | `voice_call_playback_push_frame` | 59 | Body unchanged; retained ordered Opus decode, frame validation and ring-buffer drift recovery. |
| `mosh-core/src/private_dm_runtime/blob.rs:104` | `send_attachment` | 54 | Existing prepare/encrypt/publish/record ordering retained; repeated serialization/encryption replaced by encrypt_json. |
| `mosh-core/src/private_dm_runtime/calls.rs:245` | `handle_call_control` | 53 | Body unchanged; retained existing per-call signaling dispatch. |
| `mosh-core/src/private_dm_runtime/devices/admission.rs:7` | `receive_device_offer` | 51 | Body unchanged; retained authenticated offer validation and pending installation creation. |
| `mosh-core/src/private_dm_runtime/devices/admission.rs:59` | `pending_device_session` | 54 | Body unchanged; retained complete pending-session initialization. |
| `mosh-core/src/private_dm_runtime/devices/runtime.rs:103` | `receive_device_packet` | 70 | Body unchanged; retained signed-packet verification before variant dispatch. |
| `mosh-core/src/private_dm_runtime/lifecycle.rs:8` | `rehydrate` | 91 | Body unchanged, moved from runtime root; retained best-effort MLS snapshot/room/history restoration. |
| `mosh-core/src/private_dm_runtime/lifecycle.rs:148` | `create_invite` | 56 | Body unchanged, moved from runtime root; retained MLS setup, room acquisition, record persistence and invite result ordering. |
| `mosh-core/src/private_dm_runtime/lifecycle.rs:205` | `accept_invite` | 68 | Body unchanged, moved from runtime root; retained fingerprint-bound join handshake and delayed joiner persistence. |
| `mosh-core/src/private_dm_runtime/resend.rs:51` | `pump_unacked_resends` | 71 | Body unchanged, moved from session; retained epoch-aware retransmission and budget updates only after transport acceptance. |
| `mosh-core/src/private_dm_runtime/session.rs:7` | `new` | 68 | Body unchanged, retained existing PrivateDmSession aggregate initialization. |
| `mosh-core/src/private_group_runtime/close.rs:6` | `close` | 61 | Body unchanged, moved from runtime root; retained self-removal publication before room/session/storage release. |
| `mosh-core/src/private_group_runtime/data.rs:88` | `send_attachment` | 52 | Existing prepare/encrypt/publish/record ordering retained; repeated serialization/encryption replaced by encrypt_json. |
| `mosh-core/src/private_group_runtime/lifecycle.rs:10` | `create_group` | 81 | Ordered MLS/org credential setup, room acquisition/public-key rollback and durable creation retained; GroupSession initializer unified. |
| `mosh-core/src/private_group_runtime/lifecycle.rs:109` | `join_group` | 94 | Ordered invite/org checks, room acquisition/rollback, staged persistence and admission publication retained; GroupSession initializer unified. |

## Test proofs

All 45 functions below are unchanged existing caller-visible behavior/security proofs relocated into focused test modules. Their setup, exercise, restart/recovery sequence and assertions remain together; none was expanded by this refactor.

| Path:line | Test | Lines |
| --- | --- | ---: |
| `mosh-core/src/api/private_dm_tests.rs:105` | `persistence_and_identity_survive_restart` | 73 |
| `mosh-core/src/channel_runtime/runtime_tests/delivery.rs:54` | `failed_send_rehydrates_as_retryable_message` | 74 |
| `mosh-core/src/channel_runtime/runtime_tests/delivery.rs:135` | `a_torn_send_row_rehydrates_as_a_plain_failure` | 89 |
| `mosh-core/src/channel_runtime/runtime_tests/delivery.rs:226` | `retry_message_reuses_message_id_and_clears_failed_attempt` | 66 |
| `mosh-core/src/channel_runtime/runtime_tests/lifecycle.rs:77` | `channel_history_survives_restart_without_duplicate_tail` | 73 |
| `mosh-core/src/channel_runtime/runtime_tests/lifecycle.rs:205` | `a_malformed_frame_does_not_discard_the_valid_frames_behind_it` | 58 |
| `mosh-core/src/org_runtime_tests/offers.rs:4` | `dm_offers_are_roster_gated_targeted_and_accept_once` | 99 |
| `mosh-core/src/org_runtime_tests/roster.rs:109` | `roster_gossip_verifies_persists_and_tracks_removals` | 63 |
| `mosh-core/src/org_runtime_tests/roster.rs:174` | `hello_and_stale_roster_trigger_republish` | 62 |
| `mosh-core/src/private_dm_runtime/runtime_tests/attachments.rs:10` | `a_repeated_chunk_request_still_reaches_the_sender` | 59 |
| `mosh-core/src/private_dm_runtime/runtime_tests/attachments.rs:77` | `chunk_serving_falls_back_to_the_room_wire_when_the_stream_refuses` | 72 |
| `mosh-core/src/private_dm_runtime/runtime_tests/attachments.rs:157` | `a_stream_delivered_chunk_reaches_handle_blob_through_the_carrier` | 52 |
| `mosh-core/src/private_dm_runtime/runtime_tests/attachments.rs:215` | `private_dm_runtime_transfers_attachment_over_moss` | 51 |
| `mosh-core/src/private_dm_runtime/runtime_tests/handshake.rs:12` | `private_dm_runtime_exchanges_e2ee_message_over_moss` | 51 |
| `mosh-core/src/private_dm_runtime/runtime_tests/handshake.rs:118` | `sessions_request_explicit_connect_to_counterpart` | 62 |
| `mosh-core/src/private_dm_runtime/runtime_tests/handshake.rs:187` | `bob_retransmits_key_package_until_joined` | 55 |
| `mosh-core/src/private_dm_runtime/runtime_tests/handshake.rs:247` | `alice_caches_welcome_and_reanswers_repeat_key_package` | 57 |
| `mosh-core/src/private_dm_runtime/runtime_tests/peer_discovery.rs:53` | `key_package_with_new_moss_id_replaces_stale_pin` | 51 |
| `mosh-core/src/private_dm_runtime/runtime_tests/peer_discovery.rs:108` | `forged_delivery_ack_does_not_upgrade` | 76 |
| `mosh-core/src/private_dm_runtime/runtime_tests/peer_discovery.rs:267` | `sessions_share_one_node_and_close_releases_it` | 51 |
| `mosh-core/src/private_dm_runtime/runtime_tests/restore.rs:4` | `waiting_creator_invite_survives_restart` | 54 |
| `mosh-core/src/private_dm_runtime/runtime_tests/restore.rs:60` | `restored_inbound_history_waits_for_live_peer` | 81 |
| `mosh-core/src/private_dm_runtime/runtime_tests/restore.rs:143` | `history_and_session_survive_restart` | 85 |
| `mosh-core/src/private_dm_runtime/runtime_tests/restore.rs:236` | `peer_moss_id_survives_a_restart` | 60 |
| `mosh-core/src/private_dm_runtime/runtime_tests/restore.rs:307` | `joiner_history_and_session_survive_restart` | 70 |
| `mosh-core/src/private_dm_runtime/state_tests/calls.rs:80` | `a_failed_accept_goes_back_to_ringing_for_the_retry` | 57 |
| `mosh-core/src/private_dm_runtime/state_tests/calls.rs:142` | `a_failed_decline_keeps_the_call_for_a_retry` | 60 |
| `mosh-core/src/private_dm_runtime/state_tests/calls.rs:207` | `a_ring_whose_subscribe_failed_is_retried_by_the_next_offer` | 84 |
| `mosh-core/src/private_dm_runtime/state_tests/connection.rs:129` | `duplicate_inbound_data_reacks_without_decrypt` | 51 |
| `mosh-core/src/private_dm_runtime/state_tests/receipt_authorization.rs:6` | `a_message_settles_from_sent_to_delivered_to_read` | 71 |
| `mosh-core/src/private_dm_runtime/state_tests/receipt_authorization.rs:82` | `a_disabled_toggle_sends_nothing_and_ignores_inbound_receipts` | 73 |
| `mosh-core/src/private_dm_runtime/state_tests/receipt_authorization.rs:161` | `a_forged_receipt_never_colors_a_message` | 76 |
| `mosh-core/src/private_dm_runtime/state_tests/receipt_authorization.rs:241` | `a_receipt_travels_encrypted_per_message` | 58 |
| `mosh-core/src/private_dm_runtime/state_tests/receipt_recovery.rs:7` | `read_state_survives_a_restart` | 93 |
| `mosh-core/src/private_dm_runtime/state_tests/receipt_recovery.rs:131` | `a_refused_receipt_is_resent_on_the_next_viewed` | 63 |
| `mosh-core/src/private_dm_runtime/state_tests/typing.rs:6` | `typing_signal_travels_and_a_message_stops_it` | 64 |
| `mosh-core/src/private_group_runtime/runtime_tests/delivery.rs:55` | `failed_send_rehydrates_as_retryable_message` | 75 |
| `mosh-core/src/private_group_runtime/runtime_tests/delivery.rs:132` | `retry_message_reuses_message_id_and_clears_failed_attempt` | 67 |
| `mosh-core/src/private_group_runtime/runtime_tests/delivery.rs:206` | `a_failed_control_frame_is_retried_its_retransmission` | 61 |
| `mosh-core/src/private_group_runtime/runtime_tests/lifecycle.rs:53` | `groups_share_one_node_and_close_releases_it` | 65 |
| `mosh-core/src/private_group_runtime/runtime_tests/recovery_authority.rs:83` | `a_roster_near_the_version_ceiling_rejects_an_unreachable_claim` | 76 |
| `mosh-core/src/private_group_runtime/runtime_tests/restore.rs:4` | `group_history_and_session_survive_restart` | 73 |
| `mosh-core/src/private_group_runtime/runtime_tests/roster_authority.rs:4` | `org_commit_authority_follows_roster_with_lag_buffer` | 130 |
| `mosh-core/src/private_group_runtime/runtime_tests/roster_authority.rs:136` | `roster_reconciliation_kicks_revoked_members_and_survives_restart` | 145 |
| `mosh-core/src/private_group_runtime/runtime_tests/sequencing.rs:125` | `org_admission_enforces_identity_and_roster_with_replace_dedup` | 128 |

## Implementation blocks

If the 200-line/type rule counts each impl block rather than the type declaration, these six changed blocks exceed it. They are concern-specific collections of methods on existing runtime/session types; breaking them into new state-owning types would change ownership boundaries. Each file stays below 400 lines.

| Path:line | Impl | Lines | Concern |
| --- | --- | ---: | --- |
| `mosh-core/src/org_runtime/session.rs:5` | `OrgSession` | 255 | Verified roster, offer routing and snapshot |
| `mosh-core/src/private_dm_runtime/control.rs:5` | `PrivateDmSession` | 337 | Named DM control protocol handlers |
| `mosh-core/src/private_dm_runtime/devices/admission.rs:6` | `PrivateDmRuntime` | 291 | Linked-device admission workflow |
| `mosh-core/src/private_dm_runtime/lifecycle.rs:5` | `PrivateDmRuntime` | 269 | Creation, joining and restoration |
| `mosh-core/src/private_dm_runtime/session_transport.rs:5` | `PrivateDmSession` | 315 | Routing, handshakes and media transport |
| `mosh-core/src/private_group_runtime/control.rs:5` | `GroupSession` | 300 | Named group control protocol handlers |

## Untouched production functions in the owned scope

These exceed 50 lines but their files are unchanged, so they are outside the changed-file exception inventory: api/voice_call_ringtone.rs build_stream57; private_dm_runtime/data.rs handle_data83; private_dm_runtime/snapshot.rs snapshot71; private_dm_runtime/devices/recovery/mod.rs recovery_packets53; private_group_runtime/org_gate.rs apply_org_commit54; channel_runtime/lifecycle.rs join60; channel_runtime/blob.rs send_attachment51.

## Adapter and probe exceptions

The storage, attachment, Moss FFI, diagnostics, secure-storage and stream-transport changes have no production function over 50 lines or type declaration over 200. The MLS roster implementation block in `mosh-core/src/mls_crypto/roster.rs` is 209 lines: membership inspection/removal/replacement share the existing cryptographic state owner.

| File | Function | Lines | Why retained |
| --- | --- | ---: | --- |
| `mosh-probe/src/dispatch.rs` | `run` | 134 | Exhaustive command dispatch preserves flag and argument mapping. |
| `mosh-probe/src/dm.rs` | `listen`, `dial` | 52, 76 | Invite, handshake, polling and verdict keep one timeout budget. |
| `mosh-probe/src/dm_many.rs` | `dial_many`, `listen_many` | 84, 55 | Concurrent sessions share topology and delivery verdicts. |
| `mosh-probe/src/doctor.rs` | `doctor` | 64 | Interface diagnostics and optional live-node sampling. |
| `mosh-probe/src/group.rs` | `group_listen`, `group_dial` | 78, 84 | Admission, send/reception, leave and linger order. |
| `mosh-core/src/conversation/history_tests/messages.rs` | `an_offered_file_can_be_downloaded_after_both_peers_restart` | 86 | Existing complete two-peer restart/download proof. |

## Flutter exceptions

The following existing declaration spans include their signatures and internal comments, excluding leading documentation. Widget build trees retain one readable subtree, and State classes retain one disposal/lifetime owner. Splitting these solely by physical lines would add forwarded properties or divide asynchronous ownership. New shared call-card, theme, focus, diagnostics-section and scripted-facet helpers fit all limits. Nested declarative widget constructors are layout structure; behavior branches retain the existing guards.

| File:line | Declaration | Lines | Why retained |
| --- | --- | ---: | --- |
| `lib/main.dart:36` | `main` | 151 | Ordered native, DEK and provider startup. |
| `lib/src/features/conversation/attachment_card.dart:60` | `AttachmentCard.build` | 78 | Existing declarative widget subtree. |
| `lib/src/features/conversation/attachment_card.dart:186` | `_buildBar` | 79 | Existing declarative widget subtree. |
| `lib/src/features/conversation/attachment_card_branches.dart:26` | `_MediaPreviewCard.build` | 128 | Existing declarative widget subtree. |
| `lib/src/features/conversation/conversation_composer.dart:27` | `ConversationComposer` | 212 | One controlled composer subtree. |
| `lib/src/features/conversation/conversation_composer.dart:96` | `ConversationComposer.build` | 142 | Existing declarative widget subtree. |
| `lib/src/features/conversation/conversation_controller.dart:53` | `ConversationController` | 319 | One action, busy and invalidation owner. |
| `lib/src/features/conversation/conversation_helpers.dart:104` | `DeliveryTicks.build` | 57 | Existing declarative widget subtree. |
| `lib/src/features/conversation/conversation_screen.dart:53` | `_ConversationScreenState` | 233 | Composer/search/pending-open lifetime. |
| `lib/src/features/conversation/conversation_screen.dart:216` | `_ConversationScreenState.build` | 57 | Existing declarative widget subtree. |
| `lib/src/features/conversation/conversation_screen_body.dart:78` | `ConversationScreenBody.build` | 57 | Existing declarative widget subtree. |
| `lib/src/features/conversation/conversation_search_box.dart:80` | `_ConversationSearchBoxState.build` | 51 | Existing declarative widget subtree. |
| `lib/src/features/conversation/voice_message_card.dart:187` | `_VoiceMessageCardState.build` | 80 | Existing declarative widget subtree. |
| `lib/src/features/diagnostics/diagnostics_summary.dart:84` | `diagnosticsSummary` | 111 | Pure localized snapshot summary. |
| `lib/src/features/diagnostics/event_log.dart:79` | `_EventRow.build` | 57 | Existing declarative widget subtree. |
| `lib/src/features/diagnostics/summary_card.dart:230` | `RuntimeError.build` | 54 | Existing declarative widget subtree. |
| `lib/src/features/onboarding/channel_join_step.dart:87` | `_ChannelJoinStepState.build` | 76 | Existing declarative widget subtree. |
| `lib/src/features/onboarding/group_create_step.dart:103` | `_GroupCreateStepState.build` | 71 | Existing declarative widget subtree. |
| `lib/src/features/onboarding/invite_result.dart:42` | `InviteResult.build` | 71 | Existing declarative widget subtree. |
| `lib/src/features/onboarding/new_session_panel.dart:43` | `_NewSessionPanelState.build` | 60 | Existing declarative widget subtree. |
| `lib/src/features/onboarding/onboard_join_step.dart:166` | `_OnboardJoinStepState.build` | 62 | Existing declarative widget subtree. |
| `lib/src/features/onboarding/onboard_menu.dart:62` | `_OnboardMenuState.build` | 60 | Existing declarative widget subtree. |
| `lib/src/features/org/org_section.dart:40` | `OrgSection.build` | 60 | Existing declarative widget subtree. |
| `lib/src/features/org/org_section.dart:182` | `_OfferRow.build` | 69 | Existing declarative widget subtree. |
| `lib/src/features/sessions/rail_item.dart:115` | `RailItem._tapTarget` | 53 | Existing declarative widget subtree. |
| `lib/src/features/sessions/rail_item.dart:252` | `RailSettingsButton.build` | 52 | Existing declarative widget subtree. |
| `lib/src/features/sessions/rail_item.dart:314` | `RailNewButton.build` | 52 | Existing declarative widget subtree. |
| `lib/src/features/sessions/sessions_screen.dart:35` | `_SessionsScreenState.build` | 68 | Existing declarative widget subtree. |
| `lib/src/features/shared/chat_error_banner.dart:24` | `ChatErrorBanner.build` | 52 | Existing declarative widget subtree. |
| `lib/src/features/shared/confirm_dialog.dart:66` | `_ConfirmDialogCard.build` | 111 | Existing declarative widget subtree. |
| `lib/src/features/shared/crypto_notice_banner.dart:40` | `CryptoNoticeBanner.build` | 79 | Existing declarative widget subtree. |
| `lib/src/features/shared/failed_message_retry.dart:40` | `FailedMessageRetry.build` | 52 | Existing declarative widget subtree. |
| `lib/src/features/shared/media_viewer.dart:44` | `MediaViewer.build` | 108 | Existing declarative widget subtree. |
| `lib/src/features/shared/media_viewer_stages.dart:202` | `_AudioStageState.build` | 70 | Existing declarative widget subtree. |
| `lib/src/features/shared/thumbnail.dart:71` | `_createVideoThumbnail` | 84 | Native media acquisition and cleanup. |
| `lib/src/features/shared/voice_composer.dart:62` | `_VoiceComposerState` | 318 | One recording/send/disposal lifetime. |
| `lib/src/features/voice_call/voice_call_layer.dart:68` | `_VoiceCallLayerState` | 225 | One dialog/ringtone/overlay lifetime. |
| `lib/src/features/voice_call/voice_call_layer.dart:101` | `_VoiceCallLayerState._syncDialog` | 61 | Call phase and dialog lifetime mapping. |
| `lib/src/features/voice_call/voice_call_layer.dart:163` | `_VoiceCallLayerState._buildDialogFor` | 59 | Call phase and dialog lifetime mapping. |
| `lib/src/features/voice_call/voice_call_orchestrator.dart:44` | `VoiceCallOrchestrator.attach` | 84 | Capture/playback startup and rollback. |
| `lib/src/features/vpn/vpn_consent_modal.dart:129` | `_VpnConsentModalState.build` | 107 | Existing declarative widget subtree. |
| `lib/src/gateway/bridge_facade.dart:73` | `BridgeFacade` | 256 | Flat generated-call mirrors; ADR 0025. |
| `lib/src/platform/mobile_dek.dart:91` | `resolveHistoryDek` | 61 | Fail-closed platform database/key setup. |
| `lib/src/state/unread_lifecycle_provider.dart:64` | `_UnreadLifecycleNotifier._runDiff` | 75 | One coherent conversation snapshot diff. |
| `lib/src/state/unread_providers.dart:7` | `unreadCounts` | 53 | Shared conversation badge count mapping. |
