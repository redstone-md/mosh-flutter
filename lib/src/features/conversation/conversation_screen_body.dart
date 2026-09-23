/// Everything under a conversation's header: the banners, the search row,
/// the message list, the composer, and the overlays on top of them.
///
/// One body for all three kinds. The screen above owns the widget state and
/// passes it in as [ConversationChrome]; the running work comes from the
/// conversation controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_banners.dart';
import 'package:mosh/src/features/conversation/conversation_call_binding.dart'
    show ConversationCallHost, conversationCallBindingProvider;
import 'package:mosh/src/features/conversation/conversation_chrome.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart'
    show PeerActions;
import 'package:mosh/src/features/conversation/conversation_peer_status.dart';
import 'package:mosh/src/features/conversation/conversation_search_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_state.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/typing_hint.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/chat_drop_zone.dart' show ChatDropZone;
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor, AttachmentView;
import 'package:mosh/src/state/conversation_providers.dart';

/// The gap around the DM's "messages are end-to-end encrypted" line.
const EdgeInsets _cryptoFooterPadding = EdgeInsets.fromLTRB(16, 4, 16, 8);

/// Who is typing, from the async snapshot: nobody while a poll is in
/// flight or failed — the hint is a decoration, never a load signal.
List<String> typingNamesOf(ConversationSnapshot? snapshot) =>
    snapshot == null ? const [] : typingNames(snapshot);

class ConversationScreenBody extends ConsumerWidget {
  const ConversationScreenBody({
    super.key,
    required this.target,
    required this.chrome,
    required this.composer,
    required this.onSend,
    required this.onRetrySend,
    required this.onOpenAttachment,
    required this.onPeerMessage,
    required this.onVoiceError,
    required this.onAttachmentPickError,
  });

  final AnyConversationTarget target;

  /// The search text, the filter and the two panels, owned by the screen.
  final ConversationChrome chrome;

  final TextEditingController composer;

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

  bool get _isDm => target.kind == ConversationKind.dm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(conversationSnapshotProvider(target));
    final state = ref.watch(conversationControllerProvider(target));
    final controller =
        ref.watch(conversationControllerProvider(target).notifier);
    final call = ref.watch(conversationCallBindingProvider);
    final chatError = state.chatError;
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              if (chatError != null)
                ChatErrorBanner(
                  message: chatError.describe(l),
                  onRetry: state.canRetrySend ? onRetrySend : null,
                ),
              ConversationBanners(target: target, snapshot: async.value),
              ConversationSearchRow(chrome: chrome),
              Expanded(child: _messages(async, state, controller, l)),
              TypingHint(names: typingNamesOf(async.value)),
              _composer(l, state, controller),
              if (_isDm) _cryptoFooter(context, l),
            ],
          ),
          if (chrome.showPeerStatus)
            Positioned.fill(
              child: ConversationPeerStatus(
                async: async,
                onRefresh: controller.refresh,
                onClose: chrome.onClosePeerStatus,
              ),
            ),
          // The call modals and the in-call bar, when the app has bound a
          // call module. The overlay draws nothing until there is a call.
          // Keyed: the peer-status slot above comes and goes, and without a
          // key its arrival shifts this slot's index, remounting the layer
          // and leaving its open modal orphaned under a fresh one.
          if (_isDm && call != null)
            Positioned.fill(
              key: const ValueKey('conversation-call-overlay'),
              child: call.overlay(
                context,
                ConversationCallHost(
                  conversationId: target.id,
                  l: l,
                  onError: controller.showError,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The message list, wrapped so a dropped file sends the same way the
  /// paperclip does. The zone is off while a send is in flight.
  Widget _messages(
    AsyncValue<ConversationSnapshot> async,
    ConversationControllerState state,
    ConversationController controller,
    AppLocalizations l,
  ) =>
      ChatDropZone(
        disabled: state.sending,
        onAttach: controller.sendAttachment,
        onError: onAttachmentPickError,
        child: async.when(
          // The conversation re-reads every second. Without this the list
          // would flash a spinner on every tick.
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
          data: (snapshot) => _list(snapshot, state, controller, l),
        ),
      );

  /// The visible messages, or one of the two empty states: nothing sent yet,
  /// or the search and the filter hid everything.
  Widget _list(
    ConversationSnapshot snapshot,
    ConversationControllerState state,
    ConversationController controller,
    AppLocalizations l,
  ) {
    if (snapshot.messages.isEmpty) {
      return _ConversationEmpty(kind: target.kind, l: l);
    }
    final visible = filterConversationMessages(
      snapshot.messages,
      chrome.search,
      chrome.filter,
    );
    if (visible.isEmpty) {
      return ConversationSearchEmpty(filter: chrome.filter, l: l);
    }
    return ConversationMessageListView(
      messages: visible,
      snapshot: snapshot,
      attachmentCallbacks: controller.attachmentCallbacks(onOpenAttachment),
      onRetryMessage: controller.retryMessage,
      // A DM has one peer and it is already open, so its names do nothing.
      peer: _isDm
          ? null
          : PeerActions(
              ownFingerprint: snapshot.ownFingerprint,
              offered: state.offeredFingerprints,
              busy: state.offerBusy,
              onMessage: onPeerMessage,
            ),
    );
  }

  Widget _composer(
    AppLocalizations l,
    ConversationControllerState state,
    ConversationController controller,
  ) =>
      ConversationComposer(
        controller: composer,
        sending: state.sending,
        placeholder: l.chatComposerPlaceholder,
        sendLabel: l.chatSendLabel,
        onSend: onSend,
        onTyping: controller.signalTyping,
        attachLabel: l.chatAttachLabel,
        onAttach: controller.sendAttachment,
        onAttachmentPickError: onAttachmentPickError,
        voiceRecordLabel: l.voiceRecordLabel,
        voiceDiscardLabel: l.voiceDiscardLabel,
        voiceStopLabel: l.voiceStopLabel,
        voicePlayLabel: l.voicePlayLabel,
        voiceSendLabel: l.voiceSendLabel,
        voicePermissionDeniedLabel: l.voicePermissionDenied,
        onSendVoice: controller.sendVoice,
        onVoiceError: onVoiceError,
      );

  Widget _cryptoFooter(BuildContext context, AppLocalizations l) => Padding(
        padding: _cryptoFooterPadding,
        child: Text(
          l.chatCryptoFooter,
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
