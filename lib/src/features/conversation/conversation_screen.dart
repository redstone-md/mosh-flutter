/// The screen behind a DM, a channel and a group.
///
/// It owns the widget state -- the composer, the search text, the filter,
/// the mobile search panel, the peer-status drawer -- and the two things the
/// controller deliberately does not do: it clears the composer after a
/// successful send, and it navigates.
///
/// Each kind supplies only its header. Everything else is shared.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_chrome.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_leave_prompt.dart';
import 'package:mosh/src/features/conversation/conversation_screen_body.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_state.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/shared/attachment_launcher.dart';
import 'package:mosh/src/features/shared/attachment_open.dart';
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';
import 'package:mosh/src/features/shared/media_viewer.dart'
    show showMediaViewer;
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor, AttachmentView;
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/util/format.dart' show readableError;

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.target,
    required this.header,
    this.onLeft,
  });

  /// Which conversation this screen shows.
  final AnyConversationTarget target;

  /// Builds the kind's app bar.
  final ConversationHeaderBuilder header;

  /// Runs after the conversation has been left, before navigating away.
  final VoidCallback? onLeft;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final TextEditingController _composer = TextEditingController();
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;
  bool _mobileSearchOpen = false;
  bool _showPeerStatus = false;

  AnyConversationTarget get _target => widget.target;

  ConversationController get _controller =>
      ref.read(conversationControllerProvider(_target).notifier);

  @override
  void initState() {
    super.initState();
    _markActive();
  }

  /// Marks this conversation as the one on screen, so its unread badge
  /// clears on the next read. Deferred by a microtask: Riverpod does not
  /// allow writing to a provider during initState.
  void _markActive() {
    final key = _target.key;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(activeConversationKeyProvider.notifier).set(key);
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The router can reuse this screen for another conversation. Close the
    // mobile search panel so the new one does not inherit it, and point the
    // unread lifecycle at the conversation now on screen.
    if (widget.target != oldWidget.target) {
      _mobileSearchOpen = false;
      _markActive();
    }
  }

  /// Sends what the composer holds, then clears it -- but only if it still
  /// holds the same text, so anything typed during the send survives.
  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    _clearComposerAfter(await _controller.sendBody(body));
  }

  /// Sends the last failed message again, with the same clearing rule.
  Future<void> _retryFailedSend() async {
    _clearComposerAfter(await _controller.retryFailedSend());
  }

  void _clearComposerAfter(ConversationSendOutcome outcome) {
    if (!mounted) return;
    if (outcome.sent && _composer.text.trim() == outcome.body) {
      _composer.clear();
    }
  }

  /// Opens an attachment: in the app for media, in the desktop's own app for
  /// anything else.
  void _openAttachment(AttachmentDescriptor descriptor, AttachmentView? view) {
    switch (_controller.openAttachment(descriptor, view)) {
      case AttachmentExternalOpenIntent(:final localPath):
        unawaited(_openWithSystemApp(localPath));
      case AttachmentMediaOpenIntent(:final descriptor, :final src):
        showMediaViewer(context: context, descriptor: descriptor, src: src);
      case AttachmentNoopOpenIntent():
        break;
    }
  }

  Future<void> _openWithSystemApp(String localPath) async {
    try {
      await ref.read(attachmentLauncherProvider).open(localPath);
    } catch (error) {
      _showSnackBar(readableError(error));
    }
  }

  /// Starts a DM with a peer of this channel or group and opens it.
  Future<void> _onPeerMessage(String peerFingerprint) async {
    final result = await _controller.onPeerMessage(peerFingerprint);
    if (!mounted) return;
    final sessionId = result.sessionId;
    if (sessionId != null) context.go(AppRoutes.dmFor(sessionId));
  }

  void _onVoiceError(String message) => _showSnackBar(message);

  void _onAttachmentPickError(AttachmentPickError error) =>
      _showSnackBar(AppLocalizations.of(context)!.attachmentTooLargeMessage);

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks first, then leaves.
  Future<void> _requestLeave() async {
    final l = AppLocalizations.of(context)!;
    final prompt = ConversationLeavePrompt.of(
      l,
      _target,
      ref.read(conversationSnapshotProvider(_target)).value,
    );
    final confirmed = await showConfirmDialog(
      context: context,
      title: prompt.title,
      body: prompt.body,
      confirmLabel: prompt.confirmLabel,
      cancelLabel: l.dialogCancel,
    );
    if (confirmed) await _leave();
  }

  Future<void> _leave() async {
    // A failed leave keeps the conversation on screen, so it stays the
    // active one until the leave has actually happened.
    if (!await _controller.leave() || !mounted) return;
    ref.read(activeConversationKeyProvider.notifier).clear();
    widget.onLeft?.call();
    // On a wide window the chat route shows the "start a conversation"
    // panel; on a narrow one the rail is the way back.
    context.go(
      isMobileBreakpoint(context) ? AppRoutes.sessions : AppRoutes.chat,
    );
  }

  ConversationChrome get _chrome => ConversationChrome(
        search: _search,
        onSearch: (value) => setState(() => _search = value),
        filter: _filter,
        onFilter: (value) => setState(() => _filter = value),
        mobileSearchOpen: _mobileSearchOpen,
        onToggleMobileSearch: () =>
            setState(() => _mobileSearchOpen = !_mobileSearchOpen),
        onCloseMobileSearch: () => setState(() => _mobileSearchOpen = false),
        showPeerStatus: _showPeerStatus,
        onOpenPeerStatus: () => setState(() => _showPeerStatus = true),
        onClosePeerStatus: () => setState(() => _showPeerStatus = false),
        onRequestLeave: _requestLeave,
      );

  @override
  Widget build(BuildContext context) {
    // Every time the conversation is re-read, check whether an attachment
    // the user opened early has finished downloading.
    ref.listen<AsyncValue<ConversationSnapshot>>(
      conversationSnapshotProvider(_target),
      (_, next) => _resolvePendingOpen(next.value),
    );
    final chrome = _chrome;
    return Scaffold(
      appBar: widget.header(context, chrome),
      body: ConversationScreenBody(
        target: _target,
        chrome: chrome,
        composer: _composer,
        onSend: _send,
        onRetrySend: _retryFailedSend,
        onOpenAttachment: _openAttachment,
        onPeerMessage: _onPeerMessage,
        onVoiceError: _onVoiceError,
        onAttachmentPickError: _onAttachmentPickError,
      ),
    );
  }

  void _resolvePendingOpen(ConversationSnapshot? snapshot) {
    final attachments = snapshot?.attachments;
    if (attachments == null || attachments.isEmpty) return;
    switch (_controller.resolvePendingOpen(attachments)) {
      case ConversationPendingShow(:final descriptor, :final src):
        showMediaViewer(context: context, descriptor: descriptor, src: src);
      case ConversationPendingDropped():
      case ConversationPendingNone():
        break;
    }
  }
}
