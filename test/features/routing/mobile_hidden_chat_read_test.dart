import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/conversation_providers.dart';

import '../../support/scriptable_gateway.dart';
import 'shell_harness.dart';

const _alice = DmTarget('alice');

typedef _Chat = ({ScriptableGateway gateway, ProviderContainer container});

Future<_Chat> _openAlice(WidgetTester tester) async {
  final gateway = ScriptableGateway()
    ..seedSessions([shellSession(sessionId: 'alice', peer: 'Alice')]);
  await pumpShellApp(tester, gateway: gateway, physical: const Size(400, 800));
  await tester.tap(find.text('Alice'));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionsScreen, skipOffstage: false)));
  return (gateway: gateway, container: container);
}

Future<void> _refreshAlice(
    WidgetTester tester, ProviderContainer container) async {
  container.invalidate(conversationSnapshotProvider(_alice));
  await container.read(conversationSnapshotProvider(_alice).future);
  await tester.pumpAndSettle();
}

int _marks(_Chat chat) => chat.gateway.countOf(GatewayMethod.markViewed);

void main() {
  testWidgets('a mobile chat left for the list sends no read marks',
      (tester) async {
    final chat = await _openAlice(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final marked = _marks(chat);

    await _refreshAlice(tester, chat.container);

    expect(_marks(chat), marked);
    expect(chat.container.read(activeConversationKeyProvider), isNull);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(_marks(chat), greaterThan(marked));
  });

  testWidgets('an open chat in a hidden app sends no read marks',
      (tester) async {
    final chat = await _openAlice(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final marked = _marks(chat);

    await _refreshAlice(tester, chat.container);

    expect(_marks(chat), marked);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // The foreground poller's resume read.
    await _refreshAlice(tester, chat.container);
    expect(_marks(chat), greaterThan(marked));
  });
}
