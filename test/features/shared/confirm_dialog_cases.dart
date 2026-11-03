// Confirm/cancel route results and repeated/modifier Escape handling.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/confirm_dialog.dart';

/// Pumps a bare `ConfirmDialog` directly under MaterialApp (no showDialog),
/// so the tests can assert the dialog content + the cancel/confirm button
/// taps via the widget's own callbacks (no Navigator pop indirection).
Future<void> _pumpDialog(
  WidgetTester tester, {
  required VoidCallback onCancel,
  required VoidCallback onConfirm,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConfirmDialog(
            title: 'Leave chat?',
            body: 'This will erase the keys. Are you sure?',
            confirmLabel: 'Leave',
            onCancel: onCancel,
            onConfirm: onConfirm,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A tiny host that calls [showConfirmDialog] on the first post-frame
/// callback (so the dialog opens AFTER the Navigator is mounted, not
/// during build -- `showDialog` asserts if invoked synchronously in build).
/// The completed `Future<bool>` is exposed via [HelperHost.result].
class HelperHost extends StatefulWidget {
  const HelperHost({super.key});

  @override
  State<HelperHost> createState() => HelperHostState();
}

class HelperHostState extends State<HelperHost> {
  Future<bool>? _result;

  /// The pending helper result. Null until the post-frame callback fires;
  /// `_pumpHelper` asserts it is set after the first frame settles.
  Future<bool>? get result => _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _result = showConfirmDialog(
          context: context,
          title: 'Delete chat?',
          body: 'Erase the keys permanently?',
          confirmLabel: 'Delete',
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Pumps [HelperHost], settles the post-frame callback that opens the
/// dialog, and returns the helper's pending `Future<bool>`.
Future<Future<bool>> _pumpHelper(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HelperHost()));
  await tester.pumpAndSettle();
  final result = tester.state<HelperHostState>(find.byType(HelperHost)).result;
  // The post-frame callback fired during pumpAndSettle, so the dialog is
  // open + the result future is set. Assert to surface a clear failure if
  // the post-frame timing ever changes.
  expect(result, isNotNull, reason: 'showConfirmDialog was not invoked');
  return result!;
}

void main() {
  testWidgets('Escape cancels once per press with or without modifiers', (
    tester,
  ) async {
    var cancellations = 0;
    var confirmations = 0;
    await _pumpDialog(
      tester,
      onCancel: () => cancellations++,
      onConfirm: () => confirmations++,
    );

    var presses = 0;
    for (final modifier in <LogicalKeyboardKey?>[
      null,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      if (modifier != null) await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      presses++;
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      if (modifier != null) await tester.sendKeyUpEvent(modifier);
      expect(cancellations, presses);
    }
    expect(confirmations, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancellations, presses + 1);
  });

  // === showConfirmDialog helper contract ===

  // Pins the helper returns `true` when the confirm button is tapped.
  testWidgets('showConfirmDialog returns true on confirm', (tester) async {
    final result = await _pumpHelper(tester);

    expect(find.text('Delete chat?'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });

  // Pins the helper returns `false` when the ghost cancel button is tapped
  // (the helper's `onCancel` pops `false`; `?? false` is a safety net).
  testWidgets('showConfirmDialog returns false on ghost cancel', (
    tester,
  ) async {
    final result = await _pumpHelper(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  // Pins the helper returns `false` when the close-X is tapped.
  testWidgets('showConfirmDialog returns false on close-X', (tester) async {
    final result = await _pumpHelper(tester);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('showConfirmDialog returns false on backdrop tap', (
    tester,
  ) async {
    final result = await _pumpHelper(tester);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(find.text('Delete chat?'), findsNothing);
  });

  // Pins that Esc (via the `KeyboardListener`) resolves the helper with
  // `false` -- the same path the call modals + `PeerStatusDrawer` use for
  // the Esc-trap.
  testWidgets('showConfirmDialog returns false on Esc', (tester) async {
    final result = await _pumpHelper(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  // Android system back uses the same cancellation path as Escape.
  testWidgets('showConfirmDialog returns false on Android system-back', (
    tester,
  ) async {
    final result = await _pumpHelper(tester);

    // Dispatch a system-back: the route's `PopScope` (canPop: false)
    // intercepts it, fires `onCancel` -> Navigator.pop(false).
    final binding = tester.binding;
    await binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });
}
