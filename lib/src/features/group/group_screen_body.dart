// Extracted from `group_screen.dart` (S5-x) as a public widget so the
// screen stays under the AGENTS.md 500-line ceiling. Pure move: the
// screen's `build()` keeps only the `Scaffold` + `AppBar` (`GroupScreenHeader`)
// wiring and delegates the `body:` interior (the former inline
// `SafeArea > Stack [...]` block) here. Behavior is byte-identical to the
// former inline body -- all the state and callbacks the block closed over
// are threaded through the constructor so this stays a plain presentational
// [StatelessWidget] (no `ref`, no `setState`; the screen owns mutation and
// passes closures in).
//
// Beyond the channel body's set, the group body also renders the
// GroupNotice -> needs_rejoin -> orgAddPrompt afterHeader order (React
// ActiveChatPanes.tsx L352-380): the [GroupRejoinNeededError] banner (gated
// by the moved [_needsRejoin] helper) and the [OrgAddMissingBanner] (gated
// by the `orgAddPrompt` prop + the `onInviteMembers` callback).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/conversation_tools.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart' show PeerActions;
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/dm/conversation_composer.dart';
import 'package:mosh/src/features/shared/crypto_notice_banner.dart';
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/features/shared/chat_drop_zone.dart' show ChatDropZone;
import 'package:mosh/src/features/group/group_rejoin_needed_error.dart';
import 'package:mosh/src/features/group/org_add_missing_banner.dart';
import 'package:mosh/src/features/group/group_message_list_view.dart';
import 'package:mosh/src/features/group/group_message_row.dart'
    show filterGroupMessages;
import 'package:mosh/src/state/org_providers.dart' show OrgAddPrompt;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView;

/// The `Scaffold.body` interior for [GroupScreen]: the
/// `SafeArea > Stack [ Column [ ChatErrorBanner, CryptoNoticeBanner,
/// GroupRejoinNeededError (when needsRejoin), OrgAddMissingBanner (when
/// prompt), ConversationTools (desktop) | MobileConversationSearch +
/// MobileConversationFilterNotice (mobile), Expanded > async.when (message
/// list -> [GroupMessageListView]), ConversationComposer ], if
/// (showPeerStatus) Positioned.fill(PeerStatusDrawer) ]` block, lifted
/// verbatim from the former inline `build()`.
class GroupScreenBody extends StatelessWidget {
  const GroupScreenBody({
    super.key,
    required this.async,
    required this.chatError,
    required this.canRetrySend,
    required this.onRetry,
    required this.search,
    required this.filter,
    required this.onSearch,
    required this.onFilter,
    required this.mobileSearchOpen,
    required this.onCloseMobileSearch,
    required this.orgAddPrompt,
    required this.onInviteMembers,
    required this.attachmentCallbacks,
    required this.onRetryMessage,
    required this.offeredFingerprints,
    required this.offerBusy,
    required this.onPeerMessage,
    required this.composerController,
    required this.sending,
    required this.onSend,
    required this.onSendAttachment,
    required this.onAttachmentPickError,
    required this.onSendVoice,
    required this.onVoiceError,
    required this.showPeerStatus,
    required this.onClosePeerStatus,
    required this.groupForDrawer,
    required this.errorForDrawer,
    required this.onRefresh,
  });

  final AsyncValue<GroupSnapshot> async;
  final String? chatError;
  final bool canRetrySend;
  final VoidCallback? onRetry;
  final String search;
  final ConversationFilter filter;
  final ValueChanged<String> onSearch;
  final ValueChanged<ConversationFilter> onFilter;
  final bool mobileSearchOpen;
  final VoidCallback onCloseMobileSearch;
  final OrgAddPrompt? orgAddPrompt;
  final void Function(OrgAddPrompt prompt) onInviteMembers;
  final GroupAttachmentCallbacks Function(AttachmentView? view)
      attachmentCallbacks;
  final void Function(String messageId) onRetryMessage;
  final Set<String> offeredFingerprints;
  final bool offerBusy;
  final Future<void> Function(String peerFingerprint) onPeerMessage;
  final TextEditingController composerController;
  final bool sending;
  final VoidCallback onSend;
  final AttachmentPickedCallback onSendAttachment;
  final AttachmentPickErrorCallback onAttachmentPickError;
  final void Function(VoiceSend voice) onSendVoice;
  final void Function(String message) onVoiceError;
  final bool showPeerStatus;
  final VoidCallback onClosePeerStatus;
  final GroupSnapshot? groupForDrawer;
  final String? errorForDrawer;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = this.async;
    final orgAddPrompt = this.orgAddPrompt;
    final groupForDrawer = this.groupForDrawer;
    final errorForDrawer = this.errorForDrawer;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              // Inline error banner (Gap 3) -- 1-1 with React
              // private-dm-screen.tsx L337-341
              // `{!showWelcome && error ? <ChatError message={error}
              // onRetry={canRetrySend ? retryFailedSend : undefined} /> :
              // null}`. Placed at the top of the chat-pane (above the
              // CryptoNoticeBanner); the Retry button is active iff
              // [canRetrySend].
              if (chatError != null)
                ChatErrorBanner(
                  message: chatError!,
                  onRetry: canRetrySend ? onRetry : null,
                ),
              // React wires the group pane afterHeader (ActiveChatPanes.tsx
              // L352-380) as GroupNotice -> needs_rejoin -> orgAddPrompt.
              // This port follows that order: CryptoNoticeBanner, then
              // RejoinNeeded, then OrgAddMissingBanner.
              CryptoNoticeBanner(
                // React `GroupNotice` (ActiveChatPanes.tsx ~L420-432):
                // `crypto-banner crypto-banner-group` with `IconLock`.
                // Material `Icons.lock` mirrors lucide `IconLock`; the
                // moss-green accent mirrors React's
                // `.crypto-banner-group` border / `.crypto-icon` tint
                // (rgba(183,216,74,*), var(--moss-glow)).
                icon: Icons.lock,
                title: l.groupNoticeTitle,
                body: l.groupNoticeBody,
                accent: const Color(0xFFB7D84A),
              ),
              // React `needs_rejoin` fragment (ActiveChatPanes.tsx L355-360):
              // `<div className="inline-error" role="alert"><strong>
              // {rejoinNeededTitle}.</strong> {" "}{rejoinNeededBody}</div>`.
              // Reads `group.needsRejoin` off the snapshot; renders ONLY when
              // the snapshot is resolved AND the flag is true (loading/error
              // => no banner). Stacks BELOW the GroupNotice, ABOVE
              // ConversationTools -- matching React's afterHeader order.
              if (_needsRejoin(async))
                GroupRejoinNeededError(
                  title: l.orgRejoinNeededTitle,
                  body: l.orgRejoinNeededBody,
                ),
              if (orgAddPrompt != null && orgAddPrompt.count > 0)
                OrgAddMissingBanner(
                  count: orgAddPrompt.count,
                  busy: orgAddPrompt.busy,
                  onAdd: () => onInviteMembers(orgAddPrompt),
                  missingOne: l.orgMissingOne,
                  missingMany: l.orgMissingMany,
                  addLabel: l.orgAddMissing,
                ),
              // Desktop search/filter row -- gated on the desktop
              // breakpoint (React hides `.conversation-tools-desktop` at
              // `max-width: 580px`). On desktop the row renders exactly as
              // before (byte-identical); on mobile the compact trio below
              // replaces it.
              if (!isMobileBreakpoint(context))
                ConversationTools(
                  search: search,
                  filter: filter,
                  onSearch: onSearch,
                  onFilter: onFilter,
                  l: l,
                ),
              // Mobile search/filter trio -- 1-1 with React
              // ActiveChatHeader `mobileSearchOpen ? <MobileConversation
              // Search/> : null` + the always-rendered
              // `MobileConversationFilterNotice` (null-collapses when
              // filter == all). Only on mobile (the toggle is gated in
              // [GroupScreenHeader] on the same breakpoint).
              if (isMobileBreakpoint(context)) ...[
                if (mobileSearchOpen)
                  MobileConversationSearch(
                    search: search,
                    onSearch: onSearch,
                    onClose: onCloseMobileSearch,
                    l: l,
                  ),
                MobileConversationFilterNotice(
                  filter: filter,
                  onFilter: onFilter,
                  l: l,
                ),
              ],
              // ChatDropZone wraps the message list so a desktop file drop
              // reuses the SAME onAttach/onError pair the paperclip uses
              // (ChatComposer.tsx:8-43 React parity). `sending` gates the
              // zone (no overlay + no ingest while a send is in flight).
              // Expanded stays the Column's direct child (Flex parent data);
              // ChatDropZone sits inside it wrapping the list content.
              Expanded(
                child: ChatDropZone(
                  disabled: sending,
                  onAttach: onSendAttachment,
                  onError: onAttachmentPickError,
                  child: async.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(e.toString())),
                    data: (group) {
                      if (group.messages.isEmpty) {
                        return _Empty(l: l);
                      }
                      // React's filter-THEN-group order (MessageLists.tsx
                      // `GroupChatList`): filter the raw list, THEN group
                      // the visible set so the 5-min window is computed
                      // across what the user actually sees. Empty-after-
                      // filter renders the shared `DmSearchEmpty` (the
                      // React `SearchEmpty` branch), mirroring DmScreen.
                      final filtered = filterGroupMessages(
                        group.messages,
                        search,
                        filter,
                      );
                      if (filtered.isEmpty) {
                        return DmSearchEmpty(filter: filter, l: l);
                      }
                      return GroupMessageListView(
                        messages: filtered,
                        ownFingerprint: group.deviceFingerprint,
                        attachments: group.attachments,
                        attachmentCallbacks: attachmentCallbacks,
                        onRetryMessage: onRetryMessage,
                        peer: PeerActions(
                          ownFingerprint: group.deviceFingerprint,
                          offered: offeredFingerprints,
                          busy: offerBusy,
                          onMessage: onPeerMessage,
                        ),
                      );
                    },
                  ),
                ),
              ),
              ConversationComposer(
                controller: composerController,
                sending: sending,
                placeholder: l.chatComposerPlaceholder,
                sendLabel: l.chatSendLabel,
                onSend: onSend,
                attachLabel: l.chatAttachLabel,
                onAttach: onSendAttachment,
                onAttachmentPickError: onAttachmentPickError,
                voiceRecordLabel: l.voiceRecordLabel,
                voiceDiscardLabel: l.voiceDiscardLabel,
                voiceStopLabel: l.voiceStopLabel,
                voicePlayLabel: l.voicePlayLabel,
                voiceSendLabel: l.voiceSendLabel,
                onSendVoice: onSendVoice,
                onVoiceError: onVoiceError,
              ),
            ],
          ),
          if (showPeerStatus)
            Positioned.fill(
              child: PeerStatusDrawer(
                group: groupForDrawer,
                error: errorForDrawer,
                refreshing: false,
                onRefresh: onRefresh,
                onClose: onClosePeerStatus,
              ),
            ),
        ],
      ),
    );
  }
}

/// Reads `group.needsRejoin` off the resolved [GroupSnapshot] for the
/// inline-error gate. Returns `false` while the snapshot is loading or in
/// error (no data) so the banner does not render until the group is known.
/// Mirrors React's `props.group.needs_rejoin` guard in ActiveChatPanes.tsx
/// (the snapshot is always resolved on the React side by the time the pane
/// renders; here the async path can still be pending).
bool _needsRejoin(AsyncValue<GroupSnapshot?> async) {
  final group = async.maybeWhen(data: (g) => g, orElse: () => null);
  return group != null && group.needsRejoin;
}

/// Empty-state for a group with no messages yet (React
/// MessageLists.tsx:79-86 GroupChatList empty branch;
/// groupEmptyTitle + groupEmptyBody). Mirrors DmScreen _Empty.
class _Empty extends StatelessWidget {
  const _Empty({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.groupEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l.groupEmptyBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
