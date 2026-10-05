import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';

const BorderRadius _focusRadius = BorderRadius.all(Radius.circular(6));

/// Puts one message's [body] on the clipboard and confirms with a snackbar.
Future<void> _copyMessageText(BuildContext context, String body) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = AppLocalizations.of(context)!.messageCopied;
  await Clipboard.setData(ClipboardData(text: body));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(copied)));
}

/// Makes the message text under [child] selectable and copyable.
class MessageSelectionArea extends StatefulWidget {
  const MessageSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  State<MessageSelectionArea> createState() => _MessageSelectionAreaState();
}

class _MessageSelectionAreaState extends State<MessageSelectionArea> {
  /// Set by a [CopyableMessage] on pointer down. The row sees the event
  /// before this area does, so the area's own pointer-down handler can tell
  /// a press on a message from a press on the space between them.
  CopyableMessage? _pressedMessage;

  /// The body of the message the last pointer went down on, if any.
  CopyableMessage? _pointedMessage;

  bool _hasSelection = false;

  void _onPointerDown(PointerDownEvent _) {
    _pointedMessage = _pressedMessage;
    _pressedMessage = null;
  }

  Widget _contextMenu(BuildContext context, SelectableRegionState region) {
    final message = _pointedMessage;
    final body = message?.body;
    void action(VoidCallback callback) {
      region
        ..clearSelection()
        ..hideToolbar();
      callback();
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: [
        ...region.contextMenuButtonItems,
        if (body != null && body.isNotEmpty)
          ContextMenuButtonItem(
            label: AppLocalizations.of(context)!.messageCopyText,
            onPressed: () {
              region
                ..clearSelection()
                ..hideToolbar();
              unawaited(_copyMessageText(this.context, body));
            },
          ),
        if (message?.onDelete case final callback?)
          ContextMenuButtonItem(
              label: AppLocalizations.of(context)!.messageDelete,
              onPressed: () => action(callback)),
        if (message?.onSelect case final callback?)
          ContextMenuButtonItem(
              label: AppLocalizations.of(context)!.messageSelect,
              onPressed: () => action(callback)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _onPointerDown,
        child: SelectionArea(
          onSelectionChanged: (content) =>
              _hasSelection = content?.plainText.isNotEmpty ?? false,
          contextMenuBuilder: _contextMenu,
          child: widget.child,
        ),
      );
}

/// One message row whose whole [body] can be copied.
class CopyableMessage extends StatelessWidget {
  const CopyableMessage(
      {super.key,
      required this.body,
      required this.child,
      this.onDelete,
      this.onSelect});

  final String body;
  final Widget child;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  Future<void> _menu(BuildContext context, Offset position) async {
    final l = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
        context: context,
        position: RelativeRect.fromRect(
            position & const Size(1, 1), Offset.zero & overlay.size),
        items: [
          if (onDelete != null)
            PopupMenuItem(value: onDelete, child: Text(l.messageDelete)),
          if (onSelect != null)
            PopupMenuItem(value: onSelect, child: Text(l.messageSelect)),
        ]);
    action?.call();
  }

  _MessageSelectionAreaState? _area(BuildContext context) =>
      context.findAncestorStateOfType<_MessageSelectionAreaState>();

  /// Ctrl+C, or Cmd+C on Apple platforms, copies the focused message. A
  /// selection in the list wins: the key then falls through to the area.
  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    final apple = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final copy = SingleActivator(
      LogicalKeyboardKey.keyC,
      control: !apple,
      meta: apple,
    );
    if (body.isEmpty ||
        event is! KeyDownEvent ||
        !copy.accepts(event, HardwareKeyboard.instance) ||
        (_area(context)?._hasSelection ?? false)) {
      return KeyEventResult.ignored;
    }
    unawaited(_copyMessageText(context, body));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _area(context)?._pressedMessage = this,
        child: Semantics(
          container: true,
          customSemanticsActions: {
            if (body.isNotEmpty)
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.messageCopyText,
              ): () => unawaited(_copyMessageText(context, body)),
            if (onDelete != null)
              CustomSemanticsAction(
                      label: AppLocalizations.of(context)!.messageDelete):
                  onDelete!,
            if (onSelect != null)
              CustomSemanticsAction(
                      label: AppLocalizations.of(context)!.messageSelect):
                  onSelect!,
          },
          child: Focus(
            onKeyEvent: (_, event) => _onKey(context, event),
            child: FocusRing(
                radius: _focusRadius,
                child: body.isNotEmpty || onDelete == null
                    ? child
                    : GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onSecondaryTapUp: (details) =>
                            _menu(context, details.globalPosition),
                        onLongPressStart: (details) =>
                            _menu(context, details.globalPosition),
                        child: child)),
          ),
        ),
      );
}
