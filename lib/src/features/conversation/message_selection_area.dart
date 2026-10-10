part of 'message_copy.dart';

/// The list retains one native selection owner, including mobile handles.
class MessageSelectionArea extends StatefulWidget {
  const MessageSelectionArea({super.key, required this.child});
  final Widget child;

  @override
  State<MessageSelectionArea> createState() => _MessageSelectionAreaState();
}

class _MessageSelectionAreaState extends State<MessageSelectionArea>
    with _MessageDragSelection {
  final _selectionKey = GlobalKey<SelectionAreaState>();
  final _menuKey = GlobalKey<MessageContextMenuState>();
  final _focus = FocusNode(debugLabel: 'Message selection');
  // Row listeners run first; null identifies a press between messages.
  _CopyableMessageState? _pressedMessage;
  _CopyableMessageState? _pointedMessage;
  Offset? _pointerPosition;
  String _selectedText = '';
  int _selectionRequest = 0;

  bool get hasSelection => _selectedText.isNotEmpty;
  SelectableRegionState? get _region =>
      _selectionKey.currentState?.selectableRegion;

  @override
  void _clear() {
    _selectionRequest++;
    _region?.clearSelection();
  }

  void retire(_CopyableMessageState message) {
    if (_pointedMessage != message) return;
    _pointedMessage = null;
    _selectionRequest++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pointedMessage == null) _menuKey.currentState?.dismiss();
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointedMessage = _pressedMessage;
    _pressedMessage = null;
    _pointerPosition = event.position;
    if (event.buttons != kSecondaryMouseButton) {
      _menuKey.currentState?.dismiss();
    }
  }

  Future<void> copy(String text) => copyMessageText(context, text);

  void showMenu(_CopyableMessageState message, Offset position,
      {bool fromTextSelection = false, bool fromKeyboard = false}) {
    if (!message.mounted) return;
    if (!fromTextSelection &&
        !fromKeyboard &&
        !message._selection.contains(position)) {
      _clear();
    }
    _pointedMessage = message;
    _region?.hideToolbar(false);
    final l = AppLocalizations.of(context)!;
    final selected = _selectedText;
    _menuKey.currentState?.show([
      if (selected.isNotEmpty)
        MessageMenuAction(l.messageCopySelectedText, Icons.content_copy, () {
          if (message.mounted) unawaited(copy(selected));
        }),
      if (message.widget.body.isNotEmpty)
        MessageMenuAction(l.messageCopyText, Icons.copy_all_outlined, () {
          if (message.mounted) unawaited(copy(message.widget.body));
        }),
      if (message.widget.body.isNotEmpty) ..._nativeActions(),
      if (message.widget.onSelect != null)
        MessageMenuAction(l.messageSelect, Icons.check_circle_outline, () {
          if (!message.mounted) return;
          _clear();
          message.widget.onSelect?.call();
        }),
      if (message.widget.onDelete != null)
        MessageMenuAction(l.messageDelete, Icons.delete_outline, () {
          if (!message.mounted) return;
          _clear();
          message.widget.onDelete?.call();
        }, danger: true),
    ], position, message._focus, fromKeyboard: fromKeyboard);
  }

  Widget _textMenu(BuildContext context, SelectableRegionState region) {
    final message = _pointedMessage;
    final position = _pointerPosition;
    final request = _selectionRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          request == _selectionRequest &&
          message != null &&
          position != null &&
          hasSelection) {
        showMenu(message, position, fromTextSelection: true);
      }
    });
    return const SizedBox.shrink();
  }

  List<MessageMenuAction> _nativeActions() => [
        for (final item in _region?.contextMenuButtonItems ??
            const <ContextMenuButtonItem>[])
          if (item.type != ContextMenuButtonType.copy && item.onPressed != null)
            MessageMenuAction(
              AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
              switch (item.type) {
                ContextMenuButtonType.selectAll => Icons.select_all,
                ContextMenuButtonType.share => Icons.share_outlined,
                _ => Icons.text_fields,
              },
              item.onPressed!,
            ),
      ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final scope = MessageSelectionScope.maybeOf(context);
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clear();
      _menuKey.currentState?.dismiss();
      scope?.selection.exit();
      return KeyEventResult.handled;
    }
    if (scope != null &&
        scope.selection.active &&
        messageCopyShortcut.accepts(event, HardwareKeyboard.instance)) {
      scope.onCopySelected();
      return KeyEventResult.handled;
    }
    final message = _pointedMessage;
    if (hasSelection &&
        (_menuKey.currentState?.isOpen ?? false) &&
        messageCopyShortcut.accepts(event, HardwareKeyboard.instance) &&
        message != null &&
        message.mounted) {
      // Overlay focus has no widget ancestor containing the native action.
      Actions.invoke(message.context, CopySelectionTextIntent.copy);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MessageContextMenu(
        key: _menuKey,
        selectionFocus: _focus,
        onDismiss: _clear,
        child: TapRegion(
          groupId: SelectableRegion,
          onTapOutside: (_) {
            _clear();
            _menuKey.currentState?.dismiss();
          },
          child: Listener(
            onPointerDown: _onPointerDown,
            child: Focus(
              onKeyEvent: _onKey,
              child: SelectionArea(
                key: _selectionKey,
                focusNode: _focus,
                onSelectionChanged: (content) =>
                    _selectedText = content?.plainText ?? '',
                contextMenuBuilder: _textMenu,
                child: NotificationListener<ScrollStartNotification>(
                  onNotification: (_) {
                    _menuKey.currentState?.close();
                    return false;
                  },
                  child: _dragSelection(widget.child),
                ),
              ),
            ),
          ),
        ),
      );
}
