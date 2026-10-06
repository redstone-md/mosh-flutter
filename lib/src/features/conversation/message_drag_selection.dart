part of 'message_copy.dart';

/// Picks messages by dragging across them.
///
/// A mouse drag that stays inside one message selects its text. Once it
/// crosses into another message it selects messages instead, from the one
/// it started on; the native text selection keeps running underneath, hidden,
/// so its edge auto-scroll carries the drag past the visible rows. On touch,
/// a long press starts the same drag while the selection mode is on, leaving
/// plain swipes to scroll.
mixin _MessageDragSelection on State<MessageSelectionArea> {
  static const double _edgeZone = 48;
  final _rows = <String, _CopyableMessageState>{};
  String? _pressedRow;
  Offset? _dragPoint;
  EdgeDraggingAutoScroller? _scroller;

  void _clear();

  MessageSelection? get _model =>
      context.getInheritedWidgetOfExactType<MessageSelectionScope>()?.selection;

  void _register(String? id, _CopyableMessageState row) {
    _rows.removeWhere((_, state) => state == row);
    if (id != null) _rows[id] = row;
  }

  void _unregister(_CopyableMessageState row) =>
      _rows.removeWhere((_, state) => state == row);

  /// The message whose row spans [global] vertically, so margins count.
  String? _rowAt(Offset global) {
    for (final MapEntry(:key, :value) in _rows.entries) {
      final box = value.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (global.dy >= top && global.dy < top + box.size.height) return key;
    }
    return null;
  }

  void _onDragDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _pressedRow = _rowAt(event.position);
  }

  void _onDragMove(PointerMoveEvent event) {
    final anchor = _pressedRow;
    final selection = _model;
    if (anchor == null || selection == null) return;
    _dragPoint = event.position;
    final row = _rowAt(event.position);
    if (!selection.dragging) {
      if (row == null || row == anchor) return;
      selection.beginDrag(anchor);
    }
    if (row != null) selection.dragTo(row);
  }

  void _onDragUp(PointerEvent event) {
    if (_pressedRow == null) return;
    _pressedRow = null;
    _finishDrag();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final row = _rowAt(details.globalPosition);
    final selection = _model;
    if (row == null || selection == null) return;
    _dragPoint = details.globalPosition;
    selection
      ..beginDrag(row)
      ..dragTo(row);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    _dragPoint = details.globalPosition;
    _scroller ??= _autoScroller();
    _followPoint();
  }

  void _onLongPressEnd(LongPressEndDetails details) => _finishDrag();

  EdgeDraggingAutoScroller? _autoScroller() {
    final row = _rows.values.firstOrNull;
    final scrollable = row == null ? null : Scrollable.maybeOf(row.context);
    return scrollable == null
        ? null
        : EdgeDraggingAutoScroller(scrollable,
            velocityScalar: 20, onScrollViewScrolled: _followPoint);
  }

  /// A drag over a scrolling list keeps selecting under the still pointer.
  /// The auto-scroller measures its target once per step, so each step
  /// hands it the pointer again.
  void _followPoint() {
    if (!mounted) return;
    final point = _dragPoint;
    final selection = _model;
    if (point == null || selection == null || !selection.dragging) return;
    if (_rowAt(point) case final row?) selection.dragTo(row);
    _scroller?.startAutoScrollIfNecessary(Rect.fromCenter(
        center: point, width: _edgeZone * 2, height: _edgeZone * 2));
  }

  @override
  void dispose() {
    _scroller?.stopAutoScroll();
    _scroller = null;
    super.dispose();
  }

  void _finishDrag() {
    _scroller?.stopAutoScroll();
    _scroller = null;
    _dragPoint = null;
    final selection = _model;
    if (selection == null || !(selection.dragging || selection.active)) return;
    selection.endDrag();
    // The hidden text selection only served the drag.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _clear();
    });
  }

  /// Wraps the list: pointer tracking for the mouse, a long press for touch,
  /// and the text highlight hidden while messages are being picked.
  Widget _dragSelection(Widget child) {
    final selection = MessageSelectionScope.maybeOf(context)?.selection;
    if (selection != null && !selection.dragging && _scroller != null) {
      _scroller!.stopAutoScroll();
      _scroller = null;
    }
    final picking =
        selection != null && (selection.active || selection.dragging);
    return Listener(
      onPointerDown: _onDragDown,
      onPointerMove: _onDragMove,
      onPointerUp: _onDragUp,
      onPointerCancel: _onDragUp,
      child: RawGestureDetector(
        gestures: {
          if (selection?.active ?? false)
            LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
              }),
              (recognizer) => recognizer
                ..onLongPressStart = _onLongPressStart
                ..onLongPressMoveUpdate = _onLongPressMove
                ..onLongPressEnd = _onLongPressEnd
                ..onLongPressCancel = _finishDrag,
            ),
        },
        child: DefaultSelectionStyle.merge(
          selectionColor: picking ? Colors.transparent : null,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (_) {
              _followPoint();
              return false;
            },
            child: child,
          ),
        ),
      ),
    );
  }
}
