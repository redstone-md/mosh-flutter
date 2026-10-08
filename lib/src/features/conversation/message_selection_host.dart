import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/conversation/message_selection.dart';
import 'package:mosh/src/features/conversation/message_selection_bar.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/features/shared/mosh_dialog.dart';
import 'package:mosh/src/features/shared/mosh_dialog_route.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';

/// Builds the chat around [header], which is the selection bar while
/// messages are selected.
typedef MessageSelectionChatBuilder = Widget Function(
    BuildContext context, Widget header);

/// Selection belongs to the screen; durable deletion belongs to the native
/// owner. Only messages the search and filter show stay selectable.
class MessageSelectionHost extends ConsumerStatefulWidget {
  const MessageSelectionHost({
    super.key,
    required this.target,
    required this.search,
    required this.filter,
    required this.header,
    required this.builder,
  });
  final AnyConversationTarget target;
  final String search;
  final ConversationFilter filter;
  final Widget header;
  final MessageSelectionChatBuilder builder;

  @override
  ConsumerState<MessageSelectionHost> createState() =>
      _MessageSelectionHostState();
}

class _MessageSelectionHostState extends ConsumerState<MessageSelectionHost> {
  final _selection = MessageSelection();

  ConversationSnapshot? get _snapshot =>
      ref.read(conversationSnapshotProvider(widget.target)).value;

  List<ConversationMessage> get _visible => filterConversationMessages(
        _snapshot?.messages ?? const [],
        widget.search,
        widget.filter,
      );

  @override
  void initState() {
    super.initState();
    _retainVisible(notify: false);
  }

  @override
  void didUpdateWidget(covariant MessageSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This build rebuilds the whole chat, so the rows need no notification.
    if (oldWidget.target != widget.target) {
      _selection.reset();
    }
    _retainVisible(notify: false);
  }

  void _retainVisible({bool notify = true}) => _selection.retain([
        for (final m in _visible)
          if (m.messageId case final id?) id,
      ], notify: notify);

  List<ConversationMessage> get _selected {
    final byId = {for (final m in _visible) m.messageId: m};
    return [
      for (final id in _selection.selectedIds)
        if (byId[id] case final message?) message,
    ];
  }

  String _selectedText() => _selected
      .map((m) => m.body)
      .where((body) => body.isNotEmpty)
      .join('\n\n');

  Future<void> _delete(List<ConversationMessage> messages) async {
    if (_selection.busy || messages.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    final target = widget.target;
    final generation = _selection.generation;
    final ids = messages.map((m) => m.messageId!).toList();
    final scope = await showMoshDialog<DeleteScope>(
      context: context,
      builder: (context) => _DeletionPrompt(messages: messages),
    );
    if (!mounted || scope == null || _selection.generation != generation) {
      return;
    }
    _selection.busy = true;
    final toaster = context.toaster;
    try {
      await ref
          .read(gatewayProvider)
          .deleteMessages(target, messageIds: ids, scope: scope);
      if (!mounted) return;
      refreshConversation(ref.invalidate, target.ref);
      if (_selection.generation != generation) return;
      _selection
        ..busy = false
        ..exit();
    } catch (_) {
      // Only for the selection it promises to keep: another chat's, or a
      // closed one's, failure would name the wrong selection.
      if (mounted && _selection.generation == generation) {
        toaster.show(l.messageDeletionFailed, kind: ToastKind.error);
      }
    } finally {
      if (mounted && _selection.generation == generation) {
        _selection.busy = false;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_selection.active) {
      return KeyEventResult.ignored;
    }
    _selection.exit();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      conversationSnapshotProvider(widget.target),
      (_, __) => _retainVisible(),
    );
    final header = ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => _selection.active
          ? MessageSelectionBar(
              count: _selection.count,
              busy: _selection.busy,
              onDelete: () => _delete(_selected),
              onCancel: _selection.exit,
            )
          : widget.header,
    );
    return MessageSelectionScope(
      selection: _selection,
      onDelete: (message) => _delete([message]),
      selectedText: _selectedText,
      child: ListenableBuilder(
        listenable: _selection,
        // System back leaves the mode before it leaves the chat.
        builder: (context, chat) => PopScope(
          canPop: !_selection.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _selection.exit();
          },
          child: chat!,
        ),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: widget.builder(context, header),
        ),
      ),
    );
  }
}

class _DeletionPrompt extends StatelessWidget {
  const _DeletionPrompt({required this.messages});
  final List<ConversationMessage> messages;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final everyone = messages.every((m) => m.canDeleteForEveryone);
    return MoshDialog(
      title: l.messageDeleteTitle(messages.length),
      closeLabel: l.dialogCancel,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.messageDeleteExplanation),
          if (messages.any((m) => m.localOnly))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(l.messageDeleteLocalOnly),
            ),
          if (!everyone)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(l.messageDeleteMixed),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.dialogCancel),
        ),
        TextButton(
          onPressed: everyone
              ? () => Navigator.pop(context, DeleteScope.forEveryone)
              : null,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(l.messageDeleteForEveryone),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, DeleteScope.forMe),
          style: moshDangerButtonStyle(),
          child: Text(l.messageDeleteForMe),
        ),
      ],
    );
  }
}
