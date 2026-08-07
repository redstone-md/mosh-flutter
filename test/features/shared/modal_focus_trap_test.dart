// Shared ModalFocusTrap test suite.
// Verifies Tab and Shift+Tab focus cycling and wrap-around behavior.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';

void main() {
  testWidgets('ModalFocusTrap cycles focus on Tab and Shift+Tab',
      (WidgetTester tester) async {
    final focusNode1 = FocusNode();
    final focusNode2 = FocusNode();
    final focusNode3 = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModalFocusTrap(
            child: Column(
              children: [
                TextButton(
                  focusNode: focusNode1,
                  onPressed: () {},
                  child: const Text('Button 1'),
                ),
                TextButton(
                  focusNode: focusNode2,
                  onPressed: () {},
                  child: const Text('Button 2'),
                ),
                TextButton(
                  focusNode: focusNode3,
                  onPressed: () {},
                  child: const Text('Button 3'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Initial focus on the third button (last)
    focusNode3.requestFocus();
    await tester.pump();
    expect(focusNode3.hasFocus, isTrue);

    // Press Tab -> focus should wrap to the first button
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusNode1.hasFocus, isTrue);

    // Press Tab again -> focus should move to the second button (normal traversal)
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusNode2.hasFocus, isTrue);

    // Request focus on the first button
    focusNode1.requestFocus();
    await tester.pump();
    expect(focusNode1.hasFocus, isTrue);

    // Press Shift+Tab -> focus should wrap to the third button (last)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(focusNode3.hasFocus, isTrue);

    // Dispose nodes
    focusNode1.dispose();
    focusNode2.dispose();
    focusNode3.dispose();
  });
}
