import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/rust/chat_names/types.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../support/scriptable_bridge.dart';

void main() {
  test('an old refresh cannot overwrite names after invalidation', () async {
    final bridge = ScriptableBridge();
    bridge.conversations.names['dm:session'] = 'Old';
    final container = ProviderContainer(
        overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
    addTearDown(container.dispose);
    final subscription = container.listen(chatNamesProvider, (_, __) {});
    addTearDown(subscription.close);
    await container.read(chatNamesProvider.future);
    final stale = Completer<ChatNameSnapshot>();
    bridge.respondNext(BridgeMethod.personalNames, stale.future);
    final refreshing = container.read(chatNamesProvider.notifier).refresh();
    bridge.conversations.names['dm:session'] = 'New';
    container.invalidate(chatNamesProvider);
    await container.read(chatNamesProvider.future);
    stale.complete(const ChatNameSnapshot(
        entries: [ChatNameEntry(conversationKey: 'dm:session', name: 'Old')],
        pending: false));
    await refreshing;
    expect(container.read(chatNamesProvider).requireValue.entries.single.name,
        'New');
  });
}
