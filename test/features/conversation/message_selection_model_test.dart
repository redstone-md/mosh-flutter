import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/message_selection.dart';

MessageSelection _selection(
        [List<String> order = const ['a', 'b', 'c', 'd']]) =>
    MessageSelection()..retain(order);

void main() {
  test('toggling enters the mode and the last deselection leaves it', () {
    final selection = _selection();
    selection.toggle('b');
    expect(selection.active, isTrue);
    expect(selection.selectedIds, ['b']);
    selection.toggle('b');
    expect(selection.active, isFalse);
    expect(selection.count, 0);
  });

  test('selected ids follow the conversation order', () {
    final selection = _selection()
      ..toggle('c')
      ..toggle('a');
    expect(selection.selectedIds, ['a', 'c']);
  });

  test('extending selects the range from the last toggled message', () {
    final selection = _selection()
      ..toggle('d')
      ..extendTo('b');
    expect(selection.selectedIds, ['b', 'c', 'd']);
  });

  test('extending without an anchor toggles that message', () {
    final selection = _selection()..extendTo('c');
    expect(selection.selectedIds, ['c']);
  });

  group('dragging', () {
    test('selects from the anchor and restores rows it leaves', () {
      final selection = _selection()
        ..beginDrag('a')
        ..dragTo('c');
      expect(selection.selectedIds, ['a', 'b', 'c']);
      selection.dragTo('b');
      expect(selection.selectedIds, ['a', 'b']);
      selection.endDrag();
      expect(selection.dragging, isFalse);
      expect(selection.active, isTrue);
    });

    test('a selected anchor deselects and keeps rows outside the range', () {
      final selection = _selection()
        ..toggle('a')
        ..toggle('b')
        ..toggle('d')
        ..beginDrag('b')
        ..dragTo('c');
      expect(selection.selectedIds, ['a', 'd']);
    });

    test('moving within one row never toggles it twice', () {
      final selection = _selection()..beginDrag('b');
      for (var i = 0; i < 3; i++) {
        selection.dragTo('b');
      }
      expect(selection.selectedIds, ['b']);
    });

    test('the mode stays during the drag and closes at its empty end', () {
      final selection = _selection()
        ..toggle('a')
        ..beginDrag('a')
        ..dragTo('a');
      expect(selection.active, isTrue);
      selection.endDrag();
      expect(selection.active, isFalse);
    });

    test('a drag starts only on a selectable message', () {
      final selection = _selection()..beginDrag('missing');
      expect(selection.dragging, isFalse);
      selection.dragTo('b');
      expect(selection.count, 0);
    });
  });

  test('retaining narrows the selection to visible messages', () {
    final selection = _selection()
      ..toggle('a')
      ..toggle('c');
    selection.retain(const ['b', 'c']);
    expect(selection.selectedIds, ['c']);
    selection.retain(const ['b']);
    expect(selection.active, isFalse);
  });

  test('a hidden drag anchor ends the drag', () {
    final selection = _selection()
      ..beginDrag('a')
      ..dragTo('b');
    selection.retain(const ['b', 'c']);
    expect(selection.dragging, isFalse);
    expect(selection.selectedIds, ['b']);
  });

  test('resetting clears everything and starts a new generation', () {
    final selection = _selection()
      ..toggle('a')
      ..beginDrag('a')
      ..busy = true;
    final generation = selection.generation;
    selection.reset();
    expect(selection.active, isFalse);
    expect(selection.dragging, isFalse);
    expect(selection.busy, isFalse);
    expect(selection.generation, generation + 1);
  });

  test('busy ignores toggles and drags', () {
    final selection = _selection()
      ..toggle('a')
      ..busy = true
      ..toggle('b')
      ..beginDrag('c')
      ..dragTo('d');
    expect(selection.selectedIds, ['a']);
  });

  test('changes notify listeners once per change', () {
    var notified = 0;
    final selection = _selection()..addListener(() => notified++);
    selection
      ..toggle('a')
      ..retain(const ['a', 'b', 'c', 'd']);
    expect(notified, 1);
  });
}
