/// Shared conversation composer for the DM + channel + group screens -- the
/// 1-в-1 port of React ChatComposer.tsx Composer. All three screens wire
/// AttachmentPicker (paperclip) + VoiceComposer (mic) + TextField + send
/// button through this widget; the screen owns the controller + sending flag
/// + the per-kind send*Attachment / sendVoice Gateway seam.
//
// React Composer (ChatComposer.tsx): form -> .composer-box -> AttachmentPicker
// (when onAttach) -> VoiceComposer (when onSendVoice) -> input -> send-button.
// This Flutter port renders AttachmentPicker -> VoiceComposer -> TextField ->
// FilledButton. Drag-drop (ChatDropZone) is a later slice.
//
// Disabled semantics mirror React: disabled gates the picker + voice mic + input
// + send button; sending (separate flag, React sending prop) swaps the send
// icon for a spinner and forces enabled false. onSend fires on button or submit.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/dm/clipboard_paste_handler.dart' show PasteImageAction;
import 'package:mosh/src/features/shared/voice_composer.dart';

/// The shared DM + channel + group composer. Stateless because all state is
/// transient or owned by the screen (`controller` + `sending` are passed in;
/// the screen owns the `sending` flag + post-send invalidate).
class ConversationComposer extends StatelessWidget {
  const ConversationComposer({
    super.key,
   required this.controller,
   required this.sending,
    this.disabled = false,
   required this.placeholder,
    required this.sendLabel,
    required this.onSend,
    required this.attachLabel,
    required this.onAttach,
    required this.onAttachmentPickError,
    required this.voiceRecordLabel,
    required this.voiceDiscardLabel,
    required this.voiceStopLabel,
    required this.voicePlayLabel,
    required this.voiceSendLabel,
    required this.onSendVoice,
    required this.onVoiceError,
  });

 final TextEditingController controller;
 final bool sending;
  /// Mirrors React `ChatComposer` `disabled` prop (ChatComposer.tsx L58):
  /// a hard gate that disables the picker, voice mic, text input, and send
  /// button INDEPENDENTLY of an in-flight send. `sending` separately swaps
  /// the send label to "Sending" + shows the busy spinner while a send runs.
  /// React gates with `disabled || !value.trim()` for the send button and
  /// `disabled` for the picker/voice/input; Flutter previously conflated
  /// both into `sending`, so a screen that wanted to gate input without
  /// showing a spinner had no seam. Defaults to false so existing callers
  /// (which pass only `sending`) are unchanged.
  final bool disabled;
 final String placeholder;
  final String sendLabel;
  final VoidCallback onSend;
  final String attachLabel;
  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onAttachmentPickError;
  final String voiceRecordLabel;
  final String voiceDiscardLabel;
  final String voiceStopLabel;
  final String voicePlayLabel;
  final String voiceSendLabel;
  final void Function(VoiceSend voice) onSendVoice;
  final void Function(String message) onVoiceError;

  @override
 Widget build(BuildContext context) {
    final canSend = !sending && !disabled && controller.text.trim().isNotEmpty;
   return Padding(
     padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
     child: ValueListenableBuilder<TextEditingValue>(
       valueListenable: controller,
       builder: (context, value, _) {
          final enabled = !sending && !disabled && value.text.trim().isNotEmpty;
         return Row(
           children: [
             // React Composer renders AttachmentPicker before the input
              // (ChatComposer.tsx L86-90). The picker is disabled while a
              // send is in flight OR when the hard `disabled` gate is set
              // (mirrors React's `disabled` prop).
             AttachmentPicker(
                disabled: sending || disabled,
               ariaLabel: attachLabel,
               onPick: onAttach,
               onError: onAttachmentPickError,
             ),
             const SizedBox(width: 4),
             // React Composer renders VoiceComposer after AttachmentPicker
              // (ChatComposer.tsx L93-99). The mic is disabled while a send
              // is in flight OR when the hard `disabled` gate is set.
             VoiceComposer(
                disabled: sending || disabled,
               onSend: onSendVoice,
               onError: onVoiceError,
               recordLabel: voiceRecordLabel,
               discardLabel: voiceDiscardLabel,
               stopLabel: voiceStopLabel,
               playLabel: voicePlayLabel,
               sendLabel: voiceSendLabel,
             ),
             const SizedBox(width: 4),
            Expanded(
              child: Actions(
                // Paste-to-attach (React ChatComposer.tsx:71-82 handlePaste):
                // intercept the paste [Intent] so an image on the clipboard is
                // attached instead of pasted as text. No `onPaste` callback
                // exists on Flutter 3.44 `TextField`, so the ancestor `Actions`
                // override is the interception point (the same `Action.
                // overridable` pattern EditableTextState uses, editable_text
                // .dart:5709). On no image the action defers to `callingAction`
                // so the default text paste runs.
                actions: <Type, Action<Intent>>{
                  PasteTextIntent: PasteImageAction(
                    onAttach: onAttach,
                    onAttachmentPickError: onAttachmentPickError,
                    gate: () => !sending && !disabled,
                  ) as Action<Intent>,
                },
                child: TextField(
                  controller: controller,
                   enabled: !sending && !disabled,
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
