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

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/conversation/clipboard_paste_handler.dart'
    show PasteImageAction;
import 'package:mosh/src/features/shared/voice_composer.dart';

/// React `.composer-box { gap: 8px }`.
const double kComposerGap = 8;

/// React `.send-button` / `.composer-attach` are both 32x32 squares.
const double kComposerButtonSize = 32;

/// The send square's key. React's `.send-button` holds an icon, not a
/// label, so widget tests address it by key rather than by text.
const Key kComposerSendButtonKey = Key('composer-send-button');

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
    this.onTyping,
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

  /// Fires on every input change that grows the draft — the emit-on-input
  /// hook behind the [[Typing indicator]]. The runtime throttles repeats
  /// on its own ~3 s cadence, so a keystroke-per-call is fine here; a
  /// send or a draft clear stops the hint on the runtime side (the send
  /// clears the composer, the counterpart's hint dies when their message
  /// lands or the 5 s expiry passes). Null keeps the composer inert for
  /// kinds that never carry typing (channels).
  final VoidCallback? onTyping;

  @override
  Widget build(BuildContext context) {
    final canSend = !sending && !disabled && controller.text.trim().isNotEmpty;
    // React `.composer { padding: 12px 22px 18px; background: var(--bg-1);
    // border-top: 1px solid var(--line) }`.
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      decoration: const BoxDecoration(
        color: MoshColors.bg1,
        border: Border(top: BorderSide(color: MoshColors.line)),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final enabled = !sending && !disabled && value.text.trim().isNotEmpty;
          // React `.composer-box { min-height: 46px; padding: 6px 6px 6px
          // 14px; border: 1px solid var(--line); border-radius: 10px;
          // background: var(--bg-2); gap: 8px }`.
          return Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: MoshColors.bg2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MoshColors.line),
            ),
            child: Row(
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
                const SizedBox(width: kComposerGap),
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
                const SizedBox(width: kComposerGap),
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
                      // Emit-on-input: every change that leaves a non-empty
                      // draft asks the runtime to signal typing (it throttles
                      // repeats on its own cadence). A cleared draft sends
                      // nothing — the counterpart's hint dies by expiry.
                      onChanged: (_) {
                        if (controller.text.trim().isNotEmpty) {
                          onTyping?.call();
                        }
                      },
                      onSubmitted: (_) {
                        if (canSend) onSend();
                      },
                      // React `.composer input` is a bare 13px field on the
                      // box's own background -- no border, no fill of its own.
                      style:
                          const TextStyle(fontSize: 13, color: MoshColors.fg1),
                      decoration: InputDecoration(
                        hintText: placeholder,
                        hintStyle: const TextStyle(
                            fontSize: 13, color: MoshColors.fg3),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: kComposerGap),
                // React `.send-button { width: 32px; height: 32px;
                // border-radius: 8px; background: var(--moss); color:
                // var(--moss-ink) }`, dropping to --bg-3/--fg-4 when disabled.
                Tooltip(
                  message: sendLabel,
                  child: FilledButton(
                    key: kComposerSendButtonKey,
                    onPressed: enabled ? onSend : null,
                    style: FilledButton.styleFrom(
                      fixedSize: const Size.square(kComposerButtonSize),
                      minimumSize: const Size.square(kComposerButtonSize),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: MoshColors.bg3,
                      disabledForegroundColor: MoshColors.fg4,
                    ),
                    child: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, size: 16),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
