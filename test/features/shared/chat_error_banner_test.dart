// Widget tests for `ChatErrorBanner` (lib/src/features/shared/
// chat_error_banner.dart) -- the inline chat error banner port of
// React's `ChatError` (private-dm-screen.tsx L506-525). Pins the three
// pieces of React's contract: the banner renders the message; the Retry
// button shows ONLY when `onRetry` is non-null (React
// `{onRetry ? <button/> : null}`); tapping Retry fires the callback.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('renders the message text', (tester) async {
    await pumpScreen(
        tester, Scaffold(body: const ChatErrorBanner(message: 'boom')));

    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('shows the Retry button when onRetry is non-null',
      (tester) async {
    await pumpScreen(
        tester,
        Scaffold(
            body: ChatErrorBanner(
          message: 'boom',
          onRetry: () {},
        )));

    final l =
        AppLocalizations.of(tester.element(find.byType(ChatErrorBanner)))!;
    // React: the Retry button text is the literal "Retry"; the Flutter
    // port localizes it via ARB (`chatErrorRetry`).
    expect(find.text(l.chatErrorRetry), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('hides the Retry button when onRetry is null', (tester) async {
    await pumpScreen(
        tester, Scaffold(body: const ChatErrorBanner(message: 'boom')));

    final l =
        AppLocalizations.of(tester.element(find.byType(ChatErrorBanner)))!;
    expect(find.text(l.chatErrorRetry), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('tapping Retry fires the callback', (tester) async {
    var tapped = 0;
    await pumpScreen(
        tester,
        Scaffold(
            body: ChatErrorBanner(
          message: 'boom',
          onRetry: () => tapped++,
        )));

    final l =
        AppLocalizations.of(tester.element(find.byType(ChatErrorBanner)))!;
    await tester.tap(find.text(l.chatErrorRetry));
    await tester.pumpAndSettle();

    expect(tapped, 1);
  });
}
