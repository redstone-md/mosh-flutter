import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_banners.dart';
import 'package:mosh/src/features/conversation/conversation_details_model.dart';
import 'package:mosh/src/features/conversation/conversation_details_panel.dart';
import 'package:mosh/src/features/conversation/conversation_diagnostics_content.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/message_builders.dart';
import '../../support/conversation_cases.dart'
    show testAttachment, testAttachmentView;
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

final l = lookupAppLocalizations(const Locale('en'));

void main() {
  test('DM details use runtime name, state and participants', () {
    final snapshot = DmConversation(
        const DmTarget('dm'),
        TestSnapshots.dm(
          sessionId: 'dm',
          peerDisplayName: 'Alice',
          state: DmSessionState.pending,
          deviceRevocation: DmDeviceRevocationState.revoked,
        ));
    final model = ConversationDetailsModel(snapshot, l);
    expect(model.title, 'Alice');
    expect(model.subtitle, contains('Waiting'));
    expect(model.participants.map((p) => p.name), ['me', 'Alice']);
    expect(model.knownAuthorsOnly, isFalse);
  });

  test('public channel lists known authors without claiming a roster or MLS',
      () {
    final snapshot = ChannelConversation(
        const ChannelTarget('general'),
        TestSnapshots.channel(
            name: 'general',
            deviceFingerprint: 'self',
            messages: [
              TestMessages.channel(
                  fromDevice: 'Alice', fromFingerprint: 'alice', body: 'hi'),
              TestMessages.channel(
                  fromDevice: 'Alice', fromFingerprint: 'alice', body: 'again'),
              TestMessages.channel(
                  fromDevice: 'Bob', fromFingerprint: 'bob', body: 'hello'),
            ]));
    final model = ConversationDetailsModel(snapshot, l);
    expect(model.title, '#general');
    expect(model.knownAuthorsOnly, isTrue);
    expect(model.participants.map((p) => p.name), ['Alice', 'Bob']);
  });

  test(
      'group uses actual roster identities and labels unknown identities honestly',
      () {
    final snapshot = GroupConversation(
        const GroupTarget('group'),
        TestSnapshots.group(
          groupId: 'group',
          label: 'Crew',
          deviceFingerprint: 'self',
          needsRejoin: true,
          memberPeerIds: ['alice', 'unidentified-member'],
          messages: [
            TestMessages.group(
                fromDevice: 'Alice', fromFingerprint: 'alice', body: 'hi'),
            TestMessages.group(
                fromDevice: 'Outside roster',
                fromFingerprint: 'other',
                body: 'old'),
          ],
        ));
    final model = ConversationDetailsModel(snapshot, l);
    expect(model.title, 'Crew');
    expect(model.knownAuthorsOnly, isFalse);
    expect(model.participants.map((p) => p.identity),
        ['alice', 'unidentified-member']);
    expect(model.participants.first.name, 'Alice');
  });

  testWidgets('files reuse download actions; diagnostics expand on demand',
      (tester) async {
    final file = testAttachment(attachmentId: 'file-1');
    final source =
        TestSnapshots.dm(sessionId: 'dm', peerDisplayName: 'Alice', messages: [
      TestMessages.dm(fromDevice: 'Alice', body: '', attachment: file),
      TestMessages.dm(fromDevice: 'Alice', body: '', attachment: file),
    ]);
    final snapshot = DmConversation(const DmTarget('dm'), source);
    final model = ConversationDetailsModel(snapshot, l);
    expect(model.files, hasLength(1));
    final gateway = ScriptableGateway()..seedSessions([source]);
    var closed = false;
    await pumpScreen(
        tester,
        Scaffold(
            body: SizedBox(
          width: 320,
          child: ConversationDetailsPanel(
              target: snapshot.target,
              async: AsyncData(snapshot),
              onClose: () => closed = true,
              onOpenAttachment: (_, view, own) {}),
        )),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations)),
        ]);
    final download = find.byTooltip(l.attachmentDownload);
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(gateway.countOf(GatewayMethod.downloadAttachment), 1);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byType(ConversationDiagnosticsContent), findsNothing);
    final diagnostics = find.text(l.chatDetailsDiagnostics);
    await tester.ensureVisible(diagnostics);
    await tester.tap(diagnostics);
    await tester.pumpAndSettle();
    expect(find.byType(ConversationDiagnosticsContent), findsOneWidget);
    await tester.tap(find.byTooltip(l.dialogClose));
    await tester.pump();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });
  for (final own in [true, false]) {
    testWidgets(
        'an own=$own available shared file opens with its row ownership',
        (tester) async {
      final file = testAttachment(attachmentId: 'downloaded');
      final view = testAttachmentView(
          attachmentId: 'downloaded',
          state: AttachmentState.available,
          localPath: '/tmp/report.pdf');
      final source = TestSnapshots.dm(sessionId: 'dm', messages: [
        TestMessages.dm(
            fromDevice: own ? 'me' : 'Alice', body: '', attachment: file),
      ], attachments: [
        view
      ]);
      final snapshot = DmConversation(const DmTarget('dm'), source);
      AttachmentView? opened;
      bool? openedOwn;
      final gateway = ScriptableGateway()..seedSessions([source]);
      await pumpScreen(
          tester,
          Scaffold(
              body: SizedBox(
            width: 320,
            child: ConversationDetailsPanel(
                target: snapshot.target,
                async: AsyncData(snapshot),
                onClose: () {},
                onOpenAttachment: (_, transfer, own) {
                  opened = transfer;
                  openedOwn = own;
                }),
          )),
          overrides: [
            gatewayProvider.overrideWithValue(gateway),
            bridgeFacadeProvider.overrideWithValue(
                ScriptableBridge(conversations: gateway.conversations)),
          ]);
      await tester.ensureVisible(find.text(file.fileName));
      await tester.tap(find.text(file.fileName));
      expect(opened, view);
      expect(openedOwn, own);
    });
  }
  testWidgets('conversation banners warn about revocation and group rejoin',
      (tester) async {
    final cases = <(ConversationSnapshot, String, String)>[
      (
        DmConversation(
            const DmTarget('revoked'),
            TestSnapshots.dm(
              sessionId: 'revoked',
              deviceRevocation: DmDeviceRevocationState.revoked,
            )),
        l.dmDeviceRevokedTitle,
        l.dmDeviceRevokedBody
      ),
      (
        GroupConversation(
            const GroupTarget('rejoin'),
            TestSnapshots.group(
              groupId: 'rejoin',
              deviceFingerprint: 'self',
              needsRejoin: true,
              messages: [],
            )),
        l.orgRejoinNeededTitle,
        l.orgRejoinNeededBody
      ),
    ];
    for (final (snapshot, warning, body) in cases) {
      final gateway = ScriptableGateway();
      await pumpScreen(
        tester,
        Scaffold(
          body:
              ConversationBanners(target: snapshot.target, snapshot: snapshot),
        ),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations)),
        ],
      );
      expect(find.textContaining(warning), findsOneWidget);
      expect(find.textContaining(body), findsOneWidget);
    }
  });
}
