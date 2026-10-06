import 'package:flutter/widgets.dart';

import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

/// Which messages the user picked for a bulk action. The screen owns one per
/// conversation; rows, the drag gesture and the header bar read it.
///
/// A drag works from its anchor: the anchor's state decides whether the drag
/// selects or deselects, and rows the range leaves return to how they were.
class MessageSelection extends ChangeNotifier {
  List<String> _order = const [];
  final _selected = <String>{};
  bool _active = false;
  bool _busy = false;
  int _generation = 0;
  String? _anchor;
  _Drag? _drag;

  /// Whether the selection mode is on.
  bool get active => _active;

  /// True while a deletion of the selection is in flight.
  bool get busy => _busy;
  set busy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  /// Bumped by [reset], so late results for another chat can be ignored.
  int get generation => _generation;

  bool get dragging => _drag != null;
  int get count => _selected.length;
  bool isSelected(String id) => _selected.contains(id);

  /// The selected ids, oldest first.
  List<String> get selectedIds => [
        for (final id in _order)
          if (_selected.contains(id)) id
      ];

  /// Selects or deselects one message and remembers it for [extendTo].
  void toggle(String id) {
    if (_busy || !_order.contains(id)) return;
    if (!_selected.remove(id)) _selected.add(id);
    _anchor = id;
    _active = true;
    _closeIfEmpty();
    notifyListeners();
  }

  /// Selects every message between the last toggled one and [id].
  void extendTo(String id) {
    final anchor = _anchor;
    if (anchor == null || !_order.contains(anchor)) return toggle(id);
    if (_busy || !_order.contains(id)) return;
    _selected.addAll(_range(anchor, id));
    _active = true;
    notifyListeners();
  }

  void beginDrag(String anchor) {
    if (_busy || !_order.contains(anchor)) return;
    _drag = _Drag(anchor, !_selected.contains(anchor), Set.of(_selected));
  }

  /// Applies the anchor's action to the range ending at [id].
  void dragTo(String id) {
    final drag = _drag;
    if (drag == null || drag.last == id || !_order.contains(id)) return;
    drag.last = id;
    _selected
      ..clear()
      ..addAll(drag.before);
    final range = _range(drag.anchor, id);
    drag.select ? _selected.addAll(range) : _selected.removeAll(range);
    _anchor = id;
    _active = true;
    notifyListeners();
  }

  void endDrag() {
    if (_drag == null) return;
    _drag = null;
    _closeIfEmpty();
    notifyListeners();
  }

  /// Leaves the mode and forgets the selection.
  void exit() {
    if (_busy) return;
    _clear();
    notifyListeners();
  }

  /// Starts over for another conversation.
  void reset() {
    _generation++;
    _busy = false;
    _clear();
    notifyListeners();
  }

  /// Keeps only the [visible] messages selectable, oldest first. Hidden
  /// messages are never acted on, so they leave the selection.
  void retain(List<String> visible, {bool notify = true}) {
    final before = selectedIds;
    _order = List.unmodifiable(visible);
    final shown = visible.toSet();
    _selected.retainWhere(shown.contains);
    if (_drag case final drag? when !shown.contains(drag.anchor)) {
      _drag = null;
    }
    final wasActive = _active;
    _closeIfEmpty();
    final changed = wasActive != _active || before.length != _selected.length;
    if (notify && changed) notifyListeners();
  }

  void _clear() {
    _selected.clear();
    _active = false;
    _anchor = null;
    _drag = null;
  }

  void _closeIfEmpty() {
    if (_selected.isEmpty && _drag == null) _clear();
  }

  Iterable<String> _range(String from, String to) {
    final a = _order.indexOf(from);
    final b = _order.indexOf(to);
    return _order.sublist(a < b ? a : b, (a < b ? b : a) + 1);
  }
}

class _Drag {
  _Drag(this.anchor, this.select, this.before);
  final String anchor;
  final bool select;
  final Set<String> before;
  String? last;
}

/// Gives rows and the list the screen's [MessageSelection].
class MessageSelectionScope extends InheritedNotifier<MessageSelection> {
  const MessageSelectionScope({
    super.key,
    required MessageSelection selection,
    required this.onDelete,
    required this.selectedText,
    required super.child,
  }) : super(notifier: selection);

  /// Asks how to delete one message, outside the bulk selection.
  final ValueChanged<ConversationMessage> onDelete;

  /// The selected messages' text, oldest first, for the copy shortcut.
  final String Function() selectedText;

  MessageSelection get selection => notifier!;

  static MessageSelectionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageSelectionScope>();
}
