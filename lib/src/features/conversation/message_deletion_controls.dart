import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';

typedef MessageSelectionBuilder = Widget Function(
    BuildContext context,
    Set<String> selected,
    bool selecting,
    ValueChanged<ConversationMessage> select,
    ValueChanged<ConversationMessage> delete);

/// Selection belongs to the list; durable deletion belongs to the native owner.
class MessageDeletionControls extends ConsumerStatefulWidget {
  const MessageDeletionControls(
      {super.key, required this.snapshot, required this.builder});
  final ConversationSnapshot snapshot;
  final MessageSelectionBuilder builder;
  @override
  ConsumerState<MessageDeletionControls> createState() =>
      _MessageDeletionControlsState();
}

class _MessageDeletionControlsState
    extends ConsumerState<MessageDeletionControls> {
  final _selected = <String>{};
  bool _selecting = false;
  bool _busy = false;
  int _targetGeneration = 0;

  @override
  void didUpdateWidget(covariant MessageDeletionControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.target != widget.snapshot.target) {
      _targetGeneration++;
      _selected.clear();
      _selecting = false;
      _busy = false;
    }
    final available = widget.snapshot.messages.map((m) => m.messageId).toSet();
    _selected.removeWhere((id) => !available.contains(id));
  }

  void _select(ConversationMessage message) {
    if (_busy || message.messageId == null) return;
    setState(() {
      _selecting = true;
      if (!_selected.add(message.messageId!)) {
        _selected.remove(message.messageId!);
      }
    });
  }

  Future<void> _delete(List<ConversationMessage> messages) async {
    if (_busy || messages.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    final target = widget.snapshot.target;
    final generation = _targetGeneration;
    final ids = messages.map((m) => m.messageId!).toList();
    final scope = await showDialog<DeleteScope>(
        context: context,
        builder: (context) => _DeletionPrompt(messages: messages));
    if (!mounted || scope == null || _targetGeneration != generation) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(gatewayProvider)
          .deleteMessages(target, messageIds: ids, scope: scope);
      if (!mounted) return;
      refreshConversation(ref.invalidate, target.ref);
      if (_targetGeneration != generation) return;
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    } catch (_) {
      if (mounted && _targetGeneration == generation) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.messageDeletionFailed)));
      }
    } finally {
      if (mounted && _targetGeneration == generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final messages = widget.snapshot.messages
        .where((m) => _selected.contains(m.messageId))
        .toList();
    return Column(children: [
      if (_selecting)
        SelectionContainer.disabled(
            child: Row(children: [
          IconButton(
              tooltip: l.dialogCancel,
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _selected.clear();
                        _selecting = false;
                      }),
              icon: const Icon(Icons.close)),
          Expanded(child: Text(l.messagesSelected(messages.length))),
          IconButton(
              tooltip: l.messageDelete,
              onPressed:
                  _busy || messages.isEmpty ? null : () => _delete(messages),
              icon: const Icon(Icons.delete_outline)),
        ])),
      Expanded(
          child: widget.builder(context, _selected, _selecting, _select,
              (message) => _delete([message]))),
    ]);
  }
}

class _DeletionPrompt extends StatelessWidget {
  const _DeletionPrompt({required this.messages});
  final List<ConversationMessage> messages;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final everyone = messages.every((m) => m.canDeleteForEveryone);
    return AlertDialog(
      title: Text(l.messageDeleteTitle(messages.length)),
      content: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Text(l.messageDeleteExplanation),
            if (messages.any((m) => m.localOnly))
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(l.messageDeleteLocalOnly)),
            if (!everyone)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(l.messageDeleteMixed)),
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.dialogCancel)),
        TextButton(
            onPressed: everyone
                ? () => Navigator.pop(context, DeleteScope.forEveryone)
                : null,
            child: Text(l.messageDeleteForEveryone)),
        TextButton(
            onPressed: () => Navigator.pop(context, DeleteScope.forMe),
            child: Text(l.messageDeleteForMe)),
      ],
    );
  }
}
