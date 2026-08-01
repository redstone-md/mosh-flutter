/// Shared conversation composer for the channel + group screens -- the
/// 1-в-1 port of React's `ChatComposer.tsx` `Composer` (the DM screen keeps
/// its own `_Composer` because DM attachment-SEND is blocked on the Rust
/// side -- there is no `send_private_attachment` frb binding in this fork,
/// so the DM composer has no paperclip).
//
// React Composer (ChatComposer.tsx): `<form>` -> `.composer-box` ->
// AttachmentPicker (paperclip, when `onAttach` set) -> VoiceComposer (when
// `onSendVoice` set) -> `<input>` (message) -> `.send-button`. This Flutter
// port renders: AttachmentPicker (always wired -- both callers pass it) ->
// TextField -> FilledButton. Voice is a later slice (VoiceComposer widget);
// the `onSendVoice`/`voice` params are not part of this widget's surface
// yet (added when voice lands).
//
// Disabled semantics mirror React: `disabled` gates the picker + the input
// + the send button. `sending` (a separate flag -- React `sending` prop)
// swaps the Send button's icon for a spinner and forces `enabled` false.
// `onSend` fires on the button OR on submit (Enter) when `canSend`.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/features/shared/attachment_picker.dart';

/// The shared channel + group composer. Stateless because all state is
/// transient or owned by the screen (`controller` + `sending` are passed
/// in; the screen owns the `sending` flag + post-send invalidate).
class ConversationComposer extends StatelessWidget {
  const ConversationComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.placeholder,
    required this.sendLabel,
    required this.onSend,
    required this.attachLabel,
    required this.onAttach,
    required this.onAttachmentPickError,
  });

  final TextEditingController controller;
  final bool sending;
  final String placeholder;
  final String sendLabel;
  final VoidCallback onSend;
  final String attachLabel;
  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onAttachmentPickError;

  @override
  Widget build(BuildContext context) {
    final canSend = !sending && controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final enabled = !sending && value.text.trim().isNotEmpty;
          return Row(
            children: [
              // React Composer renders AttachmentPicker before the input
              // (ChatComposer.tsx L86-90). The picker is disabled while a
              // send is in flight (mirrors React's `disabled` prop).
              AttachmentPicker(
                disabled: sending,
                ariaLabel: attachLabel,
                onPick: onAttach,
                onError: onAttachmentPickError,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !sending,
                  onSubmitted: (_) {
                    if (canSend) onSend();
                  },
                  decoration: InputDecoration(
                    hintText: placeholder,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: enabled ? onSend : null,
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(sendLabel),
              ),
            ],
          );
        },
      ),
    );
  }
}
