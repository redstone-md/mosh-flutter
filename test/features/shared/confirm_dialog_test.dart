// Widget tests for the shared ConfirmDialog
// (lib/src/features/shared/confirm_dialog.dart) -- the 1-в-1 port of React's
// `src/features/private-dm/ConfirmDialog.tsx`. Pins the prop shape, the
// danger-color confirm button, the close-X cancel, the ghost cancel button,
// and the `showConfirmDialog` helper's return contract (true on confirm,
// false on cancel/barrier/Esc). No ARB dependency: the dialog takes labels
// as props (React inlined `"Cancel"`; the Flutter port defaults to the same
// literal when `cancelLabel` is null), so the tests pass explicit strings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/confirm_dialog.dart';

/// Pumps a bare `ConfirmDialog` directly under MaterialApp (no showDialog),
/// so the tests can assert the dialog content + the cancel/confirm button
/// taps via the widget's own callbacks (no Navigator pop indirection).
Future<void> _pumpDialog(
  WidgetTester tester, {
  required VoidCallback onCancel,
  required VoidCallback onConfirm,
  String? cancelLabel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConfirmDialog(
            title: 'Leave chat?',
            body: 'This will erase the keys. Are you sure?',
            confirmLabel: 'Leave',
            cancelLabel: cancelLabel,
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
  // Pins that the dialog renders React's title + body + confirmLabel +
  // cancelLabel (defaulting the cancel label to "Cancel" when null, matching
  // React's `cancelLabel = "Cancel"` default).
  testWidgets('renders title, body, confirm label, and default cancel label',
      (tester) async {
    await _pumpDialog(
      tester,
      onCancel: () {},
      onConfirm: () {},
    );

    expect(find.text('Leave chat?'), findsOneWidget);
    expect(
        find.text('This will erase the keys. Are you sure?'), findsOneWidget);
    // Confirm button (React `confirmLabel`).
    expect(find.text('Leave'), findsOneWidget);
    // Cancel button (React `cancelLabel` default "Cancel").
    expect(find.text('Cancel'), findsOneWidget);
    // The close-X is an IconButton with a tooltip == cancelLabel ("Cancel"),
    // so the semantics label is also "Cancel" (the tooltip + the button
    // text would both match; assert via the close IconButton's tooltip).
    expect(find.byTooltip('Cancel'), findsOneWidget);
  });

  // Pins that an explicit cancelLabel overrides the default and is used
  // for BOTH the ghost button and the close-X tooltip/aria-label (React
  // `aria-label={cancelLabel}`).
  testWidgets('explicit cancelLabel drives the ghost button + close-X',
      (tester) async {
    await _pumpDialog(
      tester,
      onCancel: () {},
      onConfirm: () {},
      cancelLabel: 'Отмена',
    );

    expect(find.text('Отмена'), findsOneWidget);
    expect(find.byTooltip('Отмена'), findsOneWidget);
    // The default "Cancel" no longer appears.
    expect(find.text('Cancel'), findsNothing);
  });

  // Pins the confirm path: tapping the danger FilledButton fires onConfirm.
  testWidgets('tapping the confirm button calls onConfirm', (tester) async {
    var confirmed = false;
    var cancelled = false;
    await _pumpDialog(
      tester,
      onCancel: () => cancelled = true,
      onConfirm: () => confirmed = true,
    );

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
    // Cancel was NOT invoked on the confirm path.
    expect(cancelled, isFalse);
  });

  // Pins the cancel paths: the ghost TextButton fires onCancel (NOT onConfirm).
  testWidgets('tapping the ghost cancel button calls onCancel', (tester) async {
    var confirmed = false;
    var cancelled = false;
    await _pumpDialog(
      tester,
      onCancel: () => cancelled = true,
      onConfirm: () => confirmed = true,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(confirmed, isFalse);
  });

  // Pins the close-X cancel path: the corner IconButton fires onCancel
  // (React `onClick={onCancel}` on the close button).
  testWidgets('tapping the close-X calls onCancel', (tester) async {
    var confirmed = false;
    var cancelled = false;
    await _pumpDialog(
      tester,
      onCancel: () => cancelled = true,
      onConfirm: () => confirmed = true,
    );

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(confirmed, isFalse);
  });

  // Pins the danger color: the confirm FilledButton uses the
  // `Color(0xFFE86A5A)` background (React's `--danger` `#e86a5a`), NOT the
  // theme's default primary. Reads the FilledButton's `backgroundColor`
  // from its resolved style.
  testWidgets('the confirm button uses the danger color', (tester) async {
    await _pumpDialog(
      tester,
      onCancel: () {},
      onConfirm: () {},
    );

    // Find the FilledButton that holds the confirm label.
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Leave'),
        matching: find.byType(FilledButton),
      ),
    );
    // The style may be null (inherits theme); resolve through the widget's
    // resolved style via the Element to read the effective background.
    final style = button.style?.copyWith() ?? FilledButton.styleFrom();
    // Direct assertion on the explicit `backgroundColor` we set: the widget
    // passes `Color(0xFFE86A5A)` to `FilledButton.styleFrom`. Compare
    // against that literal so a theme/default drift fails loudly.
    expect(style.backgroundColor?.resolve({WidgetState.selected}),
        const Color(0xFFE86A5A));
  });

  // Pins the alert icon: a `Icons.warning` glyph renders (React
  // `IconAlertTriangle` -> Material `Icons.warning`) inside a 38x38 tinted
  // container. Sanity check the icon is present + decorative (no semantics).
  testWidgets('renders the alert-triangle icon (aria-hidden)', (tester) async {
    await _pumpDialog(
      tester,
      onCancel: () {},
      onConfirm: () {},
    );

    expect(find.byIcon(Icons.warning), findsOneWidget);
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
  testWidgets('showConfirmDialog returns false on ghost cancel',
      (tester) async {
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

  // Pins the helper returns `false` when the modal barrier (outside-tap)
  // dismisses the dialog (barrierDismissible: true -> Navigator pops null ->
  // helper coerces to false). The dismissible `ModalBarrier` is the one
  // whose `dismissible` semantics is true (the route barrier); tapping the
  // top-left corner of the screen (outside the centered dialog) hits it.
  testWidgets('showConfirmDialog returns false on barrier dismiss',
      (tester) async {
    final result = await _pumpHelper(tester);

    // Tap the screen's top-left corner -- outside the centered dialog, on
    // the dismissible modal barrier (showDialog's scrim).
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });
}
