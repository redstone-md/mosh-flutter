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
import 'package:mosh/src/features/shared/voice_composer.dart';

/// The shared DM + channel + group composer. Stateless because all state is
/// transient or owned by the screen (`controller` + `sending` are passed in;
/// the screen owns the `sending` flag + post-send invalidate).
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
              // React Composer renders VoiceComposer after AttachmentPicker
              // (ChatComposer.tsx L93-99). The mic is disabled while a send is
              // in flight (mirrors React's `disabled` prop).
              VoiceComposer(
                disabled: sending,
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
