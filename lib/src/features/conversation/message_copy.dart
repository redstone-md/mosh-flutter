import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'message_context_menu.dart';

part 'message_selection_area.dart';
part 'message_selection_delegate.dart';

const BorderRadius _focusRadius = BorderRadius.all(Radius.circular(6));

SingleActivator get _copyShortcut {
  final apple = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return SingleActivator(LogicalKeyboardKey.keyC, control: !apple, meta: apple);
}

/// One row's copy shortcut and semantic actions, within the shared selection.
class CopyableMessage extends StatefulWidget {
  const CopyableMessage({
    super.key,
    required this.body,
    required this.child,
    this.onDelete,
    this.onSelect,
  });
  final String body;
  final Widget child;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  @override
  State<CopyableMessage> createState() => _CopyableMessageState();
}

class _CopyableMessageState extends State<CopyableMessage> {
  final _selection = _MessageSelectionDelegate();
  final _focus = FocusNode(debugLabel: 'Message');
  _MessageSelectionAreaState? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owner = context.findAncestorStateOfType<_MessageSelectionAreaState>();
  }

  @override
  void didUpdateWidget(CopyableMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _owner?.retire(this);
  }

  void _menu(Offset position, {bool fromKeyboard = false}) =>
      _owner?.showMenu(this, position, fromKeyboard: fromKeyboard);

  void _semanticMenu() {
    final box = context.findRenderObject()! as RenderBox;
    _menu(box.localToGlobal(box.size.center(Offset.zero)));
  }

  VoidCallback? get _semanticLongPress => widget.body.isEmpty &&
          (widget.onDelete != null || widget.onSelect != null)
      ? _semanticMenu
      : null;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
        const SingleActivator(LogicalKeyboardKey.f10, shift: true)
            .accepts(event, HardwareKeyboard.instance)) {
      final box = context.findRenderObject()! as RenderBox;
      _menu(box.localToGlobal(Offset.zero), fromKeyboard: true);
      return KeyEventResult.handled;
    }
    if (widget.body.isEmpty ||
        !_copyShortcut.accepts(event, HardwareKeyboard.instance) ||
        (_owner?.hasSelection ?? false)) {
      return KeyEventResult.ignored;
    }
    unawaited(_owner?.copy(widget.body));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _owner?.retire(this);
    _selection.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _owner?._pressedMessage = this,
        child: Semantics(
          container: true,
          onLongPress: _semanticLongPress,
          customSemanticsActions: {
            if (widget.body.isNotEmpty)
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.messageCopyText,
              ): () => unawaited(_owner?.copy(widget.body)),
            if (widget.onDelete case final callback?)
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.messageDelete,
              ): callback,
            if (widget.onSelect case final callback?)
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.messageSelect,
              ): callback,
          },
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: FocusRing(
              radius: _focusRadius,
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: {
                  TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                      TapGestureRecognizer>(
                    () => TapGestureRecognizer(),
                    (recognizer) => recognizer.onSecondaryTapDown =
                        (details) => _menu(details.globalPosition),
                  ),
                  _NonTextLongPressRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          _NonTextLongPressRecognizer>(
                    () => _NonTextLongPressRecognizer(_selection),
                    (recognizer) => recognizer.onLongPressStart =
                        (details) => _menu(details.globalPosition),
                  ),
                },
                child: SelectionContainer(
                    delegate: _selection, child: widget.child),
              ),
            ),
          ),
        ),
      );
}
