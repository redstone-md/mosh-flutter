// Extracted from `channel_screen.dart` (S5-1) as a public widget so the
// screen stays under the AGENTS.md 500-line ceiling. Pure move: the screen's
// `build()` keeps only the `Scaffold` + `AppBar` wiring and delegates the
// `body:` interior (the former inline `SafeArea > Stack [...]` block) here.
// Behavior is byte-identical to the former inline body -- all the state and
// callbacks the block closed over are threaded through the constructor so
// this stays a plain presentational [StatelessWidget] (no `ref`, no
// `setState`; the screen owns mutation and passes closures in).
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
import 'package:mosh/src/features/channel/channel_message_list_view.dart';
import 'package:mosh/src/features/channel/channel_message_row.dart'
    show filterChannelMessages;
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentView;

/// The `Scaffold.body` interior for [ChannelScreen]: the
/// `SafeArea > Stack [ Column [ ChatErrorBanner, CryptoNoticeBanner,
/// ConversationTools (desktop) | MobileConversationSearch +
/// MobileConversationFilterNotice (mobile), Expanded > async.when (message
/// list -> [ChannelMessageListView]), ConversationComposer ], if
/// (showPeerStatus) Positioned.fill(PeerStatusDrawer) ]` block, lifted
/// verbatim from the former inline `build()`.
class ChannelScreenBody extends StatelessWidget {
  const ChannelScreenBody({
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
    required this.channelForDrawer,
    required this.errorForDrawer,
    required this.onRefresh,
  });

  final AsyncValue<ChannelSnapshot> async;
  final String? chatError;
  final bool canRetrySend;
  final VoidCallback? onRetry;
  final String search;
  final ConversationFilter filter;
  final ValueChanged<String> onSearch;
  final ValueChanged<ConversationFilter> onFilter;
  final bool mobileSearchOpen;
  final VoidCallback onCloseMobileSearch;
  final ChannelAttachmentCallbacks Function(AttachmentView? view)
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
  final ChannelSnapshot? channelForDrawer;
  final String? errorForDrawer;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = this.async;
    final channelForDrawer = this.channelForDrawer;
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
              CryptoNoticeBanner(
                // React `PublicNotice` (ActiveChatPanes.tsx ~L434-445):
                // `crypto-banner crypto-banner-public` with `IconHash`.
                // Material `Icons.tag` is the closest hash glyph; the
                // info-blue accent mirrors React's
                // `.crypto-banner-public` border / `.crypto-icon` tint
                // (rgba(108,183,232,*)).
                icon: Icons.tag,
                title: l.channelNoticeTitle,
                body: l.channelNoticeBody,
                accent: const Color(0xFF6CB7E8),
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
              // the AppBar on the same breakpoint).
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
                    // The 1 s auto-poll reloads this family entry; without
                    // this the list would blink to a spinner every tick.
                    skipLoadingOnReload: true,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(e.toString())),
                    data: (snapshot) {
                      if (snapshot.messages.isEmpty) {
                        return _Empty(l: l);
                      }
                      // React's filter-THEN-group order (MessageLists.tsx
                      // `ChannelChatList`): filter the raw list, THEN group
                      // the visible set so the 5-min window is computed
                      // across what the user actually sees. Empty-after-
                      // filter renders the shared `DmSearchEmpty` (the
                      // React `SearchEmpty` branch), mirroring DmScreen.
                      final filtered = filterChannelMessages(
                        snapshot.messages,
                        search,
                        filter,
                      );
                      if (filtered.isEmpty) {
                        return DmSearchEmpty(filter: filter, l: l);
                      }
                      return ChannelMessageListView(
                        messages: filtered,
                        ownFingerprint: snapshot.deviceFingerprint,
                        attachments: snapshot.attachments,
                        attachmentCallbacks: attachmentCallbacks,
                        onRetryMessage: onRetryMessage,
                        peer: PeerActions(
                          ownFingerprint: snapshot.deviceFingerprint,
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
                channel: channelForDrawer,
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

/// Empty-state for a channel with no messages yet (React
/// MessageLists.tsx:170-177 ChannelChatList empty branch;
/// channelEmptyTitle + channelEmptyBody). Mirrors DmScreen _Empty.
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
            Text(
              l.channelEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l.channelEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
