part of 'message_copy.dart';

/// Keep Flutter's drag/word events; expand a third click to the clicked Text.
class _MessageSelectionDelegate
    extends MultiSelectableSelectionContainerDelegate {
  SelectionEdgeUpdateEvent? _start;
  SelectionEdgeUpdateEvent? _end;

  bool contains(Offset globalPosition) {
    final transform = getTransformTo(null);
    return value.selectionRects.any((rect) =>
        MatrixUtils.transformRect(transform, rect).contains(globalPosition));
  }

  bool containsText(Offset globalPosition) => selectables.any((selectable) {
        final transform = selectable.getTransformTo(null);
        return selectable.boundingBoxes.any((rect) =>
            MatrixUtils.transformRect(transform, rect)
                .contains(globalPosition));
      });

  @override
  SelectionResult dispatchSelectionEventToChild(
          Selectable selectable, SelectionEvent event) =>
      super.dispatchSelectionEventToChild(
        selectable,
        event is SelectParagraphSelectionEvent
            ? const SelectAllSelectionEvent()
            : event,
      );

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    if (event.type == SelectionEventType.startEdgeUpdate) {
      _start = event;
    } else {
      _end = event;
    }
    return super.handleSelectionEdgeUpdate(event);
  }

  @override
  SelectionResult handleClearSelection(ClearSelectionEvent event) {
    _start = null;
    _end = null;
    return super.handleClearSelection(event);
  }

  @override
  void ensureChildUpdated(Selectable selectable) {
    if (_start case final event?) selectable.dispatchSelectionEvent(event);
    if (_end case final event?) selectable.dispatchSelectionEvent(event);
  }
}

/// Let the native selection recognizer own long presses over selectable text.
class _NonTextLongPressRecognizer extends LongPressGestureRecognizer {
  _NonTextLongPressRecognizer(this.selection);
  final _MessageSelectionDelegate selection;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      !selection.containsText(event.position) && super.isPointerAllowed(event);
}
