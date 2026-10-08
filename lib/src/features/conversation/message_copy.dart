import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/message_selection.dart';
import 'message_context_menu.dart';

part 'message_drag_selection.dart';
part 'message_selection_area.dart';
part 'message_selection_delegate.dart';

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
    this.selectionId,
    this.selecting = false,
    this.selected,
  });
  final String body;
  final Widget child;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  /// The message a drag across rows picks here; null when it cannot be.
  final String? selectionId;

  /// Whether rows are being picked; the row menu and copy step aside.
  final bool selecting;

  /// The picked state reported to assistive technology, while picking.
  final bool? selected;

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
    final owner = context.findAncestorStateOfType<_MessageSelectionAreaState>();
    if (owner != _owner) _owner?._unregister(this);
    _owner = owner?.._register(widget.selectionId, this);
  }

  @override
  void didUpdateWidget(CopyableMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _owner?.retire(this);
    if (oldWidget.selectionId != widget.selectionId) {
      _owner?._register(widget.selectionId, this);
    }
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

  // Match the menu: row-level actions drop any text selection first.
  VoidCallback _clearingSelection(VoidCallback callback) => () {
        _owner?._clear();
        callback();
      };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.selecting) {
      return KeyEventResult.ignored;
    }
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
    _owner?._unregister(this);
    _selection.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _owner?._pressedMessage = this,
        child: Semantics(
          container: true,
          selected: widget.selected,
          onLongPress: widget.selecting ? null : _semanticLongPress,
          customSemanticsActions: {
            // Picking offers only the pick, like the resting row menu.
            if (widget.body.isNotEmpty && !widget.selecting)
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.messageCopyText,
              ): () => unawaited(_owner?.copy(widget.body)),
            if (widget.onDelete case final callback? when !widget.selecting)
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.messageDelete,
              ): _clearingSelection(callback),
            if (widget.onSelect case final callback?)
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.messageSelect,
              ): _clearingSelection(callback),
          },
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              gestures: {
                if (!widget.selecting) ...{
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
              },
              child:
                  SelectionContainer(delegate: _selection, child: widget.child),
            ),
          ),
        ),
      );
}
