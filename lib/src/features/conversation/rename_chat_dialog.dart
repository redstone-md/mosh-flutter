import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';

Future<void> showRenameChatDialog(
        BuildContext context, AnyConversationTarget target,
        {required String name,
        required String originalName,
        bool hasPersonalName = false}) =>
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RenameChatDialog(
            target: target,
            initialName: name,
            originalName: originalName,
            hasPersonalName: hasPersonalName));

class RenameChatDialog extends ConsumerStatefulWidget {
  const RenameChatDialog(
      {super.key,
      required this.target,
      required this.initialName,
      required this.originalName,
      this.hasPersonalName = false});
  final AnyConversationTarget target;
  final String initialName;
  final String originalName;
  final bool hasPersonalName;

  @override
  ConsumerState<RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends ConsumerState<RenameChatDialog> {
  late final _text = TextEditingController(text: widget.initialName)
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);
  bool _busy = false;
  bool _invalid = false;
  ConversationActionError? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save({bool reset = false}) async {
    if (_busy) return;
    final name = _text.text.trim();
    if (!reset && !_validName(name)) {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _busy = true;
      _invalid = false;
      _error = null;
    });
    final gateway = ref.read(gatewayProvider);
    try {
      if (reset) {
        await gateway.resetName(widget.target);
      } else {
        await gateway.rename(widget.target, name: name);
      }
      if (!mounted) return;
      ref.invalidate(chatNamesProvider);
      refreshConversation(ref.invalidate, widget.target.ref);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ConversationActionError.of(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final shared = widget.target.kind == ConversationKind.group;
    return ModalFocusTrap(
        onEscape: _busy ? null : () => Navigator.of(context).pop(),
        child: AlertDialog(
          title: Text(l.chatRename),
          content: _content(context, l, shared),
          actions: [
            if (!shared && widget.hasPersonalName)
              TextButton(
                  onPressed: _busy ? null : () => _save(reset: true),
                  child: Text(l.chatNameReset)),
            TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(l.dialogCancel)),
            FilledButton(
                onPressed: _busy ? null : _save, child: Text(l.chatNameSave)),
          ],
        ));
  }

  Widget _content(BuildContext context, AppLocalizations l, bool shared) =>
      SizedBox(
          width: 400,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shared ? l.chatNameShared : l.chatNamePersonal),
                const SizedBox(height: 16),
                TextField(
                    controller: _text,
                    autofocus: true,
                    enabled: !_busy,
                    maxLines: 1,
                    decoration: InputDecoration(
                        labelText: l.chatName,
                        errorText: _invalid ? l.chatNameInvalid : null),
                    onSubmitted: (_) => _save(),
                    onChanged: (_) => setState(() => _invalid = false)),
                if (!shared) ...[
                  const SizedBox(height: 12),
                  Text(l.chatOriginalName(widget.originalName))
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error.describe(l),
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                ],
              ]));
}

bool _validName(String name) =>
    name.isNotEmpty &&
    name.runes.length <= 64 &&
    !name.runes.any((r) =>
        r <= 0x1f || (r >= 0x7f && r <= 0x9f) || r == 0x2028 || r == 0x2029);
