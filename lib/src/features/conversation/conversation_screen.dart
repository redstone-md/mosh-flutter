import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_chrome.dart';
import 'package:mosh/src/features/conversation/conversation_details_panel.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show chatHeaderHeight;
import 'package:mosh/src/features/conversation/conversation_leave_prompt.dart';
import 'package:mosh/src/features/conversation/conversation_screen_body.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_state.dart';
import 'package:mosh/src/features/conversation/conversation_text_sends.dart';
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
  int _composerRevision = 0;
  String _search = '';
  ConversationFilter _filter = ConversationFilter.all;
  bool _mobileSearchOpen = false;
  bool? _showPeerStatus;
  bool _markedInitialView = false;

  bool get _detailsDocked => MediaQuery.sizeOf(context).width >= 1280;
  bool get _detailsOpen => _showPeerStatus ?? _detailsDocked;

  AnyConversationTarget get _target => widget.target;

  ConversationController get _controller =>
      ref.read(conversationControllerProvider(_target).notifier);

  @override
  void initState() {
    super.initState();
    _composer.addListener(_draftChanged);
    _markActive();
  }

  void _draftChanged() => _composerRevision++;

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
      _composerRevision++;
      _mobileSearchOpen = false;
      _showPeerStatus = null;
      _search = '';
      _filter = ConversationFilter.all;
      _markedInitialView = false;
      _markActive();
    }
  }

  /// Capture and clear at submission, so Enter can accept the next draft.
  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    _composer.clear();
    final revision = _composerRevision;
    _restoreRefusedDraft(await _controller.sendBody(body), revision);
  }

  /// Retry may clear the restored failed draft, never a newer draft.
  Future<void> _retryFailedSend() async {
    final failure =
        ref.read(conversationTextSendsProvider(_target)).firstFailure;
    if (failure == null) return;
    if (_composer.text.trim() == failure.body) _composer.clear();
    final revision = _composerRevision;
    _restoreRefusedDraft(await _controller.retryFailedSend(), revision);
  }

  void _restoreRefusedDraft(ConversationSendOutcome outcome, int revision) {
    if (!mounted || _composerRevision != revision) return;
    if (!outcome.sent && outcome.body.isNotEmpty && _composer.text.isEmpty) {
      _composer.value = TextEditingValue(
        text: outcome.body,
        selection: TextSelection.collapsed(offset: outcome.body.length),
      );
    }
  }

  /// Opens an attachment: in the app for media, in the desktop's own app for
  /// anything else.
  void _openAttachment(
      AttachmentDescriptor descriptor, AttachmentView? view, bool own) {
    switch (_controller.openAttachment(descriptor, view, own: own)) {
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

  void _onAttachmentPickError(AttachmentPickError error) {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    _showSnackBar(switch (error) {
      AttachmentPickError.tooLarge => l.attachmentTooLargeMessage,
      AttachmentPickError.previewUnavailable => l.attachmentPreviewUnavailable,
    });
  }

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
        onToggleMobileSearch: () => setState(() {
          if (_mobileSearchOpen) _search = '';
          _mobileSearchOpen = !_mobileSearchOpen;
        }),
        onCloseMobileSearch: () => setState(() {
          _search = '';
          _mobileSearchOpen = false;
        }),
        showPeerStatus: _detailsOpen,
        onOpenPeerStatus: () => setState(() => _showPeerStatus = !_detailsOpen),
        onClosePeerStatus: () => setState(() => _showPeerStatus = false),
        onRequestLeave: _requestLeave,
      );

  @override
  Widget build(BuildContext context) {
    // Every time the conversation is re-read, check whether an attachment
    // the user opened early has finished downloading, and mark the
    // conversation viewed so the DM read receipts fire while it is open.
    ref.listen<AsyncValue<ConversationSnapshot>>(
      conversationSnapshotProvider(_target),
      (_, next) {
        _resolvePendingOpen(next.value);
        if (next.hasValue) _markViewed();
      },
    );
    // Cover a cached snapshot once; later view marks come from the listener.
    if (!_markedInitialView &&
        ref.read(conversationSnapshotProvider(_target)).hasValue) {
      _markViewed();
    }
    final chrome = _chrome;
    final chat = Scaffold(
      // The wrapper aligns the header's preferredSize with the toolbar the
      // ConversationAppBar actually renders (54px under the 640px
      // breakpoint, 70px above it). The kind headers report kToolbarHeight
      // (56) while their AppBar draws 54 or 70: Scaffold clamps its slot to
      // the reported height, so a 70px toolbar was clipped to 56 and a 54px
      // one left a 2px band of app-bar background above the body.
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(chatHeaderHeight(context)),
        child: widget.header(context, chrome),
      ),
      body: ConversationScreenBody(
        target: _target,
        detailsDocked: _detailsDocked,
        chrome: chrome,
        composer: _composer,
        onSend: _send,
        onRetrySend: _retryFailedSend,
        onOpenAttachment: _openAttachment,
        onPeerMessage: _onPeerMessage,
        onVoiceError: _showSnackBar,
        onAttachmentPickError: _onAttachmentPickError,
      ),
    );
    if (!_detailsDocked || !_detailsOpen) return chat;
    return Row(children: [
      Expanded(child: chat),
      const VerticalDivider(width: 1),
      SizedBox(
        width: 320,
        child: ConversationDetailsPanel(
          key: const ValueKey('conversation-details-docked'),
          target: _target,
          async: ref.watch(conversationSnapshotProvider(_target)),
          onClose: chrome.onClosePeerStatus,
          onOpenAttachment: _openAttachment,
        ),
      ),
    ]);
  }

  void _markViewed() {
    _markedInitialView = true;
    _controller.markViewed();
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
