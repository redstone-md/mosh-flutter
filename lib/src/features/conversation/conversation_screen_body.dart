/// Everything under a conversation's header: the banners, the search row,
/// the message list, the composer, and the overlays on top of them.
///
/// One body for all three kinds. The screen above owns the widget state --
/// the composer, the search text, the filter, whether the drawer is open --
/// and passes it in; the running work comes from the conversation
/// controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_banners.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_state.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart'
    show PeerActions;
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/features/dm/voice_call_layer.dart' show VoiceCallLayer;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/chat_drop_zone.dart' show ChatDropZone;
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentDescriptor, AttachmentView;
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show ringtonePlayerProvider;

class ConversationScreenBody extends ConsumerWidget {
  const ConversationScreenBody({
    super.key,
    required this.target,
    required this.composer,
    required this.search,
    required this.onSearch,
    required this.filter,
    required this.onFilter,
    required this.mobileSearchOpen,
    required this.onCloseMobileSearch,
    required this.showPeerStatus,
    required this.onClosePeerStatus,
    required this.onSend,
    required this.onRetrySend,
    required this.onOpenAttachment,
    required this.onPeerMessage,
    required this.onVoiceError,
    required this.onAttachmentPickError,
  });

  final AnyConversationTarget target;
  final TextEditingController composer;

  final String search;
  final ValueChanged<String> onSearch;
  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;

  final bool mobileSearchOpen;
  final VoidCallback onCloseMobileSearch;

  final bool showPeerStatus;
  final VoidCallback onClosePeerStatus;

  /// Sends what the composer holds.
  final VoidCallback onSend;

  /// Sends the last failed message again.
  final Future<void> Function() onRetrySend;

  /// Opens an attachment. The screen owns the viewer and the file launcher.
  final void Function(AttachmentDescriptor descriptor, AttachmentView? view)
      onOpenAttachment;

  /// Starts a DM with a peer of this channel or group.
  final Future<void> Function(String peerFingerprint) onPeerMessage;

  /// The microphone refused to record, or the recording would not start.
  final ValueChanged<String> onVoiceError;

  /// The picked file was too big.
  final AttachmentPickErrorCallback onAttachmentPickError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(conversationSnapshotProvider(target));
    final state = ref.watch(conversationControllerProvider(target));
    final controller =
        ref.watch(conversationControllerProvider(target).notifier);
    final snapshot = async.value;
    final chatError = state.chatError;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              if (chatError != null)
                ChatErrorBanner(
                  message: chatError,
                  onRetry: state.canRetrySend ? onRetrySend : null,
                ),
              ConversationBanners(snapshot: snapshot),
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
              ] else
                ConversationTools(
                  search: search,
                  filter: filter,
                  onSearch: onSearch,
                  onFilter: onFilter,
                  l: l,
                ),
              // Dropping a file on the list sends it the same way the
              // paperclip does. The zone is off while a send is in flight.
              Expanded(
                child: ChatDropZone(
                  disabled: state.sending,
                  onAttach: controller.sendAttachment,
                  onError: onAttachmentPickError,
                  child: async.when(
                    // The conversation re-reads every second. Without this
                    // the list would flash a spinner on every tick.
                    skipLoadingOnReload: true,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(child: Text(error.toString())),
                    data: (snapshot) => _messages(
                      context,
                      snapshot,
                      controller: controller,
                      state: state,
                      l: l,
                    ),
                  ),
                ),
              ),
              ConversationComposer(
                controller: composer,
                sending: state.sending,
                placeholder: l.chatComposerPlaceholder,
                sendLabel: l.chatSendLabel,
                onSend: onSend,
                attachLabel: l.chatAttachLabel,
                onAttach: controller.sendAttachment,
                onAttachmentPickError: onAttachmentPickError,
                voiceRecordLabel: l.voiceRecordLabel,
                voiceDiscardLabel: l.voiceDiscardLabel,
                voiceStopLabel: l.voiceStopLabel,
                voicePlayLabel: l.voicePlayLabel,
                voiceSendLabel: l.voiceSendLabel,
                onSendVoice: controller.sendVoice,
                onVoiceError: onVoiceError,
              ),
              if (target.kind == ConversationKind.dm)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    l.chatCryptoFooter,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          if (showPeerStatus)
            Positioned.fill(
              child: _peerStatusDrawer(
                snapshot,
                error: async.hasError ? async.error.toString() : null,
                onRefresh: controller.refresh,
              ),
            ),
          // The call modals and the in-call bar. The layer draws nothing
          // until there is a call.
          if (target.kind == ConversationKind.dm)
            Positioned.fill(
              child: VoiceCallLayer(
                sessionId: target.id,
                l: l,
                ringtone: ref.read(ringtonePlayerProvider),
                onVoiceCallError: controller.showError,
              ),
            ),
        ],
      ),
    );
  }

  /// The message list, or one of the two empty states: nothing sent yet, or
  /// the search and the filter hid everything.
  Widget _messages(
    BuildContext context,
    ConversationSnapshot snapshot, {
    required ConversationController controller,
    required ConversationControllerState state,
    required AppLocalizations l,
  }) {
    if (snapshot.messages.isEmpty) {
      return _ConversationEmpty(kind: snapshot.target.kind, l: l);
    }
    final visible =
        filterConversationMessages(snapshot.messages, search, filter);
    if (visible.isEmpty) return ConversationSearchEmpty(filter: filter, l: l);
    return ConversationMessageListView(
      messages: visible,
      snapshot: snapshot,
      attachmentCallbacks: controller.attachmentCallbacks(onOpenAttachment),
      onRetryMessage: controller.retryMessage,
      peer: snapshot.target.kind == ConversationKind.dm
          ? null
          : PeerActions(
              ownFingerprint: snapshot.ownFingerprint,
              offered: state.offeredFingerprints,
              busy: state.offerBusy,
              onMessage: onPeerMessage,
            ),
    );
  }

  /// The drawer that shows who is on the other side and how the traffic gets
  /// there. It reads the source snapshot, so each kind hands it its own.
  Widget _peerStatusDrawer(
    ConversationSnapshot? snapshot, {
    required String? error,
    required VoidCallback onRefresh,
  }) =>
      PeerStatusDrawer(
        session: snapshot is DmConversation ? snapshot.source : null,
        channel: snapshot is ChannelConversation ? snapshot.source : null,
        group: snapshot is GroupConversation ? snapshot.source : null,
        error: error,
        refreshing: false,
        onRefresh: onRefresh,
        onClose: onClosePeerStatus,
      );
}

/// Shown when a conversation has no messages at all. The wording follows the
/// kind.
class _ConversationEmpty extends StatelessWidget {
  const _ConversationEmpty({required this.kind, required this.l});

  final ConversationKind kind;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (kind) {
      ConversationKind.dm => (l.chatEmptyTitle, l.chatEmptyBody),
      ConversationKind.channel => (l.channelEmptyTitle, l.channelEmptyBody),
      ConversationKind.group => (l.groupEmptyTitle, l.groupEmptyBody),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
