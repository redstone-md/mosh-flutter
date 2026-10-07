// IVO-30: one stack of toasts for the whole app. A burst keeps every
// message, a repeat folds into the toast already shown, and timers hold
// while the pointer reads the stack.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';

List<String> _messages(Toaster toaster) =>
    [for (final toast in toaster.toasts) toast.message];

void main() {
  testWidgets('a burst queues past the stack instead of dropping messages',
      (tester) async {
    final toaster = Toaster();
    for (final message in ['one', 'two', 'three', 'four']) {
      toaster.show(message);
    }
    expect(_messages(toaster), ['three', 'two', 'one']);
    await tester.pump(const Duration(milliseconds: 1499));
    expect(_messages(toaster), ['three', 'two', 'one']);
    await tester.pump(const Duration(milliseconds: 1));
    // The oldest has been readable; the waiting one pushes it out.
    expect(_messages(toaster), ['four', 'three', 'two']);
    toaster.dispose();
  });

  testWidgets('a repeat comes back to the front instead of stacking a copy',
      (tester) async {
    final toaster = Toaster()
      ..show('Copied', kind: ToastKind.success)
      ..show('Saved');
    await tester.pump(const Duration(seconds: 3));
    toaster.show('Copied', kind: ToastKind.success);
    expect(_messages(toaster), ['Copied', 'Saved']);
    expect(toaster.toasts.first.bumps, 1);
    // Its lifetime restarted with the repeat.
    await tester.pump(const Duration(seconds: 2));
    expect(_messages(toaster), ['Copied']);
    await tester.pump(const Duration(seconds: 2));
    expect(toaster.toasts, isEmpty);
    toaster.dispose();
  });

  testWidgets('errors stay longer than confirmations', (tester) async {
    final toaster = Toaster()
      ..show('Copied', kind: ToastKind.success)
      ..show('Failed', kind: ToastKind.error);
    await tester.pump(const Duration(seconds: 4));
    expect(_messages(toaster), ['Failed']);
    await tester.pump(const Duration(seconds: 2));
    expect(toaster.toasts, isEmpty);
    toaster.dispose();
  });

  testWidgets(
      'a paused stack holds its toasts and grants a full lifetime after',
      (tester) async {
    final toaster = Toaster()..show('Copied');
    await tester.pump(const Duration(seconds: 3));
    toaster.paused = true;
    await tester.pump(const Duration(seconds: 30));
    expect(_messages(toaster), ['Copied']);
    toaster.paused = false;
    await tester.pump(const Duration(milliseconds: 3999));
    expect(_messages(toaster), ['Copied']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(toaster.toasts, isEmpty);
    toaster.dispose();
  });

  testWidgets('dismissing frees a slot for the waiting toast at once',
      (tester) async {
    final toaster = Toaster();
    for (final message in ['one', 'two', 'three', 'four']) {
      toaster.show(message);
    }
    toaster.dismiss(toaster.toasts.first.id);
    expect(_messages(toaster), ['four', 'two', 'one']);
    toaster.dispose();
  });
}
