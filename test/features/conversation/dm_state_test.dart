// The words a DM's proven state gets, in both locales, and the header that
// shows them. One state means one sentence everywhere: the header, the rail
// badge, the title-bar pill and the diagnostics card all go through
// `dm_state.dart`, so this is where the wording is pinned.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/dm_state.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

SessionSnapshot _snapshot({
  required DmSessionState state,
  PeerTransport transport = PeerTransport.none,
}) =>
    SessionSnapshot(
      sessionId: 'dm-state-1',
      meshId: 'testmesh',
      role: 'alice',
      displayName: 'me',
      peerDisplayName: 'juno',
      state: state,
      transport: transport,
      fingerprint: 'fp-peer-1234',
      messages: const [],
      attachments: const [],
      events: const [],
    );

Future<void> _pumpHeader(WidgetTester tester, SessionSnapshot snapshot) =>
    pumpRoute(tester, AppRoutes.dmFor(snapshot.sessionId), overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
      activeSessionProvider(snapshot.sessionId)
          .overrideWith((ref) async => snapshot),
    ]);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ru = lookupAppLocalizations(const Locale('ru'));

  group('dmStateSentence', () {
    test('pending waits for the contact', () {
      expect(
        dmStateSentence(en, DmSessionState.pending, PeerTransport.none),
        'Waiting for your contact',
      );
      expect(
        dmStateSentence(ru, DmSessionState.pending, PeerTransport.none),
        'Ожидание собеседника',
      );
    });

    test('handshaking says the contact is offline and messages will wait', () {
      expect(
        dmStateSentence(en, DmSessionState.handshaking, PeerTransport.none),
        'Contact is offline. Messages will be delivered when you are both '
        'online',
      );
      expect(
        dmStateSentence(ru, DmSessionState.handshaking, PeerTransport.none),
        'Собеседник не в сети. Сообщения будут доставлены, когда вы оба '
        'будете онлайн',
      );
    });

    test('connected names the transport next to it', () {
      expect(
        dmStateSentence(en, DmSessionState.connected, PeerTransport.direct),
        'Connected · direct',
      );
      expect(
        dmStateSentence(en, DmSessionState.connected, PeerTransport.relayed),
        'Connected · relayed by the network',
      );
      expect(
        dmStateSentence(ru, DmSessionState.connected, PeerTransport.relayed),
        'Подключено · через ретранслятор сети',
      );
    });
  });

  group('dmStateLabel', () {
    test('one short word per state, both locales', () {
      expect(
          dmStateLabel(en, DmSessionState.pending), 'Waiting for your contact');
      expect(
          dmStateLabel(en, DmSessionState.handshaking), 'Contact is offline');
      expect(dmStateLabel(en, DmSessionState.connected), 'Connected');
      expect(
          dmStateLabel(ru, DmSessionState.handshaking), 'Собеседник не в сети');
    });
  });

  group('dmPillState', () {
    test('only a proven connection reads as ready', () {
      expect(dmPillState(DmSessionState.connected), 'ready');
      expect(dmPillState(DmSessionState.handshaking), 'waiting');
      expect(dmPillState(DmSessionState.pending), 'waiting');
    });
  });

  group('DM header subtitle', () {
    testWidgets('waiting for the contact', (tester) async {
      await _pumpHeader(tester, _snapshot(state: DmSessionState.pending));
      expect(
        find.text('Waiting for your contact · fingerprint unverified'),
        findsOneWidget,
      );
    });

    testWidgets('contact is offline', (tester) async {
      await _pumpHeader(tester, _snapshot(state: DmSessionState.handshaking));
      expect(
        find.text('Contact is offline. Messages will be delivered when you '
            'are both online · fingerprint unverified'),
        findsOneWidget,
      );
    });

    testWidgets('connected over the network relay', (tester) async {
      await _pumpHeader(
        tester,
        _snapshot(
          state: DmSessionState.connected,
          transport: PeerTransport.relayed,
        ),
      );
      expect(
        find.text(
            'Connected · relayed by the network · fingerprint unverified'),
        findsOneWidget,
      );
      expect(find.byType(DmScreen), findsOneWidget);
    });
  });
}
