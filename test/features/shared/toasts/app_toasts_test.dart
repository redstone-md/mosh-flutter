// IVO-30: the app's actions report through the one toast stack. On the
// desktop split, the chat list and the chat are two Scaffolds; a copy
// used to show the same snackbar in both.
import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_notice_preferences.dart';
import 'package:mosh/src/features/conversation/dismissible_conversation_notice.dart';

import '../../../support/conversation_cases.dart';
import '../../../support/message_selection.dart';
import '../../../support/pump.dart';

final BigInt _sentAt = BigInt.from(1700000000000);

void main() {
  testWidgets('one copy shows one toast on the desktop split', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    captureClipboard(tester);
    await pumpConversation(
      tester,
      conversationCases().first,
      messages: [TestMessage(body: 'hello there', sentAtMs: _sentAt)],
      useRouter: true,
    );
    await tester.tap(find.text('hello there'),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy message'));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a notice that fails to hide after its chat closed reports',
      (tester) async {
    final saving = Completer<void>();
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await pumpScreen(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (context, value, _) => value
              ? const DismissibleConversationNotice(
                  kind: ConversationNoticeKind.publicChannel,
                  icon: Icons.public,
                  title: 'Public channel',
                  body: 'Anyone with the link can read it.',
                  accent: Colors.blue,
                )
              : const SizedBox.shrink(),
        ),
        overrides: [
          conversationNoticeStoreProvider
              .overrideWithValue(_HeldNoticeStore(saving.future)),
        ]);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    open.value = false;
    await tester.pumpAndSettle();
    saving.completeError(const FileSystemException('read-only'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Could not hide the notice. Try again.'), findsOneWidget);
  });
}

/// Holds a dismissal until the test settles it.
class _HeldNoticeStore extends ConversationNoticeStore {
  const _HeldNoticeStore(this._saved) : super(null);

  final Future<void> _saved;

  @override
  Set<ConversationNoticeKind> read() => const {};

  @override
  Future<void> dismiss(ConversationNoticeKind kind) => _saved;
}
