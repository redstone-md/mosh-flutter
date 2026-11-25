import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, kLiveNumberFontFeatures;
import 'package:mosh/src/features/shared/attachment_picker.dart';
import 'package:mosh/src/features/conversation/clipboard_paste_handler.dart'
    show PasteAttachmentAction, readSystemClipboard;
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show feedPadding;
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show isMobileBreakpoint;
import 'package:mosh/src/features/shared/composer_send_button.dart';
import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:super_clipboard/super_clipboard.dart' show ClipboardDataReader;

/// The send button's key. It holds an icon, not a label, so widget tests
/// address it by key rather than by text.
const Key kComposerSendButtonKey = Key('composer-send-button');

/// The counter shows once this few characters are left.
const int kComposerCounterThreshold = 200;

/// The Composer card, shared by the DM, the channel and the group: one field
/// for everything a person sends. With nothing typed the far end holds the
/// microphone; the first character turns it into Send. Past the limit the
/// field takes the error colour and counts the characters to cut. A voice
/// recording takes over the whole field ([VoiceComposer]).
///
/// Stateless because all state is transient or owned by the conversation's
/// screen and send controllers.
class ConversationComposer extends StatelessWidget {
  const ConversationComposer({
    super.key,
    required this.controller,
    required this.sending,
    this.disabled = false,
    required this.placeholder,
    required this.sendLabel,
    required this.onSend,
    this.textLimit,
    required this.attachLabel,
    required this.onAttach,
    required this.onAttachmentPickError,
    required this.voiceLabels,
    required this.onSendVoice,
    required this.onVoiceError,
    this.inputDeviceId = storedVoiceInputDeviceId,
    this.onTyping,
    this.readClipboard = readSystemClipboard,
  });

  final TextEditingController controller;
  final bool sending;

  /// A hard gate that disables the picker, voice mic, text input, and send
  /// button independently of admission. `sending` gates file/voice picking
  /// and shows progress for an empty draft; text remains editable/submittable.
  final bool disabled;
  final String placeholder;
  final String sendLabel;
  final VoidCallback onSend;

  /// The text limit and how its counter reads; null means no counter.
  final ComposerTextLimit? textLimit;
  final String attachLabel;
  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onAttachmentPickError;
  final VoiceComposerLabels voiceLabels;
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

  /// Reads the stored input-device pick for the voice composer's capture.
  /// Injectable so widget tests (no cdylib) pass a plain getter; the
  /// default reads mosh-core's audio-devices store.
  final String? Function() inputDeviceId;

  /// Reads the clipboard for paste-to-attach. Injectable so widget tests
  /// hand in a fake reader; the default reads the system clipboard.
  final Future<ClipboardDataReader?> Function() readClipboard;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final compact = isMobileBreakpoint(context);
    final side = feedPadding(compact: compact).left;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          side, 0, side, compact ? MoshSpace.s2 : MoshSpace.s4),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final remaining = textLimit?.remaining(value.text);
          final over = remaining != null && remaining < 0;
          return Container(
            padding: MoshShapes.composerPadding,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: MoshShapes.composer,
            ),
            // Drawn over the box, so the edge does not move what is in it.
            foregroundDecoration: over
                ? BoxDecoration(
                    borderRadius: MoshShapes.composer,
                    border: Border.all(color: colors.error),
                  )
                : null,
            child: VoiceComposer(
              // The mic is off while a send is in flight or the hard
              // `disabled` gate is set.
              disabled: sending || disabled,
              labels: voiceLabels,
              onSend: onSendVoice,
              onError: onVoiceError,
              inputDeviceId: inputDeviceId,
              idle: (context, microphone) =>
                  _textRow(context, value.text, remaining, microphone),
            ),
          );
        },
      ),
    );
  }

  /// The row at rest: attach, the field, the counter near the limit and,
  /// at the far end, the one place for both ways to send.
  Widget _textRow(
      BuildContext context, String text, int? remaining, Widget microphone) {
    final colors = MoshColors.of(context);
    final empty = text.trim().isEmpty;
    return Row(
      spacing: MoshShapes.composerGap,
      children: [
        AttachmentPicker(
          disabled: sending || disabled,
          ariaLabel: attachLabel,
          onPick: onAttach,
          onError: onAttachmentPickError,
        ),
        Expanded(child: _field(context)),
        if (remaining != null && remaining <= kComposerCounterThreshold)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s2),
            child: Text(
              '$remaining',
              semanticsLabel: textLimit!.label(remaining),
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                    fontFeatures: kLiveNumberFontFeatures,
                    color: remaining < 0 ? colors.error : colors.onSurfaceMuted,
                  ),
            ),
          ),
        // The microphone while there is nothing to send, Send once there
        // is, unlit while the text is too long. A send on its way with an
        // empty draft (a file, a voice message) spins in the same place.
        if (disabled || (empty && !sending))
          microphone
        else
          ComposerSendButton(
            key: kComposerSendButtonKey,
            label: sendLabel,
            onPressed: _sendable(text, remaining) ? onSend : null,
            busy: empty,
          ),
      ],
    );
  }

  Widget _field(BuildContext context) {
    final colors = MoshColors.of(context);
    final style = Theme.of(context).textTheme.bodyLarge!;
    final paste = PasteAttachmentAction(
      onAttach: onAttach,
      onAttachmentPickError: onAttachmentPickError,
      gate: () => !sending && !disabled,
      readClipboard: readClipboard,
    );
    return Actions(
      // Paste-to-attach: a file or image on the clipboard is attached
      // instead of pasted as text. Flutter 3.44 `TextField` has no
      // `onPaste`, so the paste [Intent] is overridden here, as
      // EditableTextState does with `Action.overridable`; without an image
      // the action defers to `callingAction` and the text paste runs.
      actions: <Type, Action<Intent>>{
        PasteTextIntent: paste as Action<Intent>,
      },
      child: TextField(
        controller: controller,
        enabled: !disabled,
        contextMenuBuilder: (context, editable) =>
            _contextMenu(editable, paste),
        // Finalize IME composition without Flutter's default unfocus,
        // keeping the next keyboard submission ready.
        onEditingComplete: controller.clearComposing,
        // Emit-on-input: every change that leaves a non-empty draft asks
        // the runtime to signal typing (it throttles repeats on its own
        // cadence). A cleared draft sends nothing: the counterpart's hint
        // dies by expiry.
        onChanged: (_) {
          if (controller.text.trim().isNotEmpty) onTyping?.call();
        },
        onSubmitted: (_) {
          final text = controller.text;
          if (_sendable(text, textLimit?.remaining(text))) onSend();
        },
        style: style,
        decoration: _bareField(
          hint: placeholder,
          hintStyle: style.copyWith(
            color: disabled
                ? MoshState.tint(colors.onSurface, MoshState.disabledContent)
                : colors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }

  bool _sendable(String text, int? remaining) =>
      !disabled && text.trim().isNotEmpty && (remaining ?? 0) >= 0;
}

/// A field on the composer's own background: no border, no fill of its own.
InputDecoration _bareField(
        {required String hint, required TextStyle hintStyle}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: hintStyle,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    );

/// The longest text a send accepts and how the counter near it reads.
class ComposerTextLimit {
  const ComposerTextLimit({required this.maxChars, required this.label});

  /// In characters (Unicode scalar values), as mosh-core counts them.
  final int maxChars;

  /// Reads the counter aloud; `remaining` is negative over the limit.
  final String Function(int remaining) label;

  /// What is left of the limit for [draft], counted as it will be sent:
  /// the send trims the draft first.
  int remaining(String draft) => maxChars - draft.trim().runes.length;
}

/// The platform's editing menu, with Paste routed through [paste] so it
/// attaches a copied file or image exactly like Ctrl+V / Cmd+V does.
Widget _contextMenu(EditableTextState editable, PasteAttachmentAction paste) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: [
        for (final item in editable.contextMenuButtonItems)
          item.type == ContextMenuButtonType.paste
              ? item.copyWith(onPressed: () {
                  editable.hideToolbar();
                  paste.paste(
                      () => editable.pasteText(SelectionChangedCause.toolbar));
                })
              : item,
      ],
    );
