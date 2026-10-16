import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/message_deletion/origin.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/rust/plus/types.dart';
import '../../support/pump.dart';
import '../../support/plus/fakes.dart';

void main() {
  testWidgets(
      'own badge checks expiry even when the last native read was active',
      (tester) async {
    final native = MemoryPlusCommands()
      ..current = PlusSnapshot(
          active: true,
          visible: true,
          expiresAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch - 1),
          peerBadges: []);
    final container = _container(native);
    addTearDown(container.dispose);
    await pumpScreen(
        tester, const Scaffold(body: Avatar(name: 'Me', ownPlus: true)),
        container: container);
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
  });
  testWidgets('shared badges expire and conversation titles stay ordinary',
      (tester) async {
    final native = MemoryPlusCommands()
      ..current = PlusSnapshot(active: true, visible: false, peerBadges: [
        PlusPeerBadge(
            identity: 'dm:test',
            expiresAtMs: BigInt.from(DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch))
      ]);
    final container = _container(native);
    addTearDown(container.dispose);
    await pumpScreen(
        tester,
        const Scaffold(
            body: Column(children: [
          Avatar(name: 'Me', ownPlus: true),
          ConversationKindAvatar(
              kind: ConversationKind.dm, name: 'Peer', plusIdentity: 'dm:test'),
          ConversationKindAvatar(
              kind: ConversationKind.group,
              name: 'Group',
              plusIdentity: 'dm:test'),
          ConversationKindAvatar(
              kind: ConversationKind.channel,
              name: 'Channel',
              plusIdentity: 'dm:test'),
        ])),
        container: container);
    expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
    native.current =
        const PlusSnapshot(active: false, visible: false, peerBadges: []);
    await container.read(plusProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
  });

  testWidgets('a claimed legacy channel author cannot borrow a verified badge',
      (tester) async {
    final native = MemoryPlusCommands()
      ..current = PlusSnapshot(active: false, visible: false, peerBadges: [
        PlusPeerBadge(
            identity: 'channel:test:paid-peer',
            expiresAtMs: BigInt.from(DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch))
      ]);
    final container = _container(native);
    addTearDown(container.dispose);
    await pumpScreen(tester, Scaffold(body: _messageRow(false)),
        container: container);
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
    await pumpScreen(tester, Scaffold(body: _messageRow(true)),
        container: container);
    expect(find.byIcon(Icons.workspace_premium), findsNWidgets(2));
  });
}

ProviderContainer _container(MemoryPlusCommands native) =>
    ProviderContainer(overrides: [
      plusConfigProvider
          .overrideWithValue(const PlusConfig(issuerKey: 'pinned-test-key')),
      plusCommandsProvider.overrideWithValue(native),
      plusPollIntervalProvider.overrideWithValue(null),
    ]);

Widget _messageRow(bool authenticated) => ConversationMessageRow(
      message: ConversationMessage(
          fromDevice: 'Peer',
          fromFingerprint: 'paid-peer',
          body: 'hello',
          own: false,
          metadata: authenticated
              ? const MessageMetadata(
                  canDeleteForEveryone: true,
                  localOnly: false,
                  origin: MessageOrigin(
                      conversation: 'channel:test',
                      id: 'message',
                      contentHash: 'hash',
                      author: 'signer',
                      signature: 'verified-by-native'))
              : null),
      conversationKey: 'channel:test',
      kind: ConversationKind.channel,
      grouped: false,
      busy: false,
      onAttachmentDownload: (_) {},
      onAttachmentCancel: (_) {},
      onAttachmentOpen: (_) {},
      onRetry: (_) {},
      l: lookupAppLocalizations(const Locale('en')),
    );
