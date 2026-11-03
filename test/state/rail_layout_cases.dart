import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';

void main() {
  Future<Directory> directory() async {
    final dir = await Directory.systemTemp.createTemp('mosh-rail-layout-');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  ProviderContainer containerFor(RailLayoutStore store) {
    final container = ProviderContainer(
        overrides: [railLayoutStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    return container;
  }

  test('missing or malformed data falls back to the default layout', () async {
    expect(RailLayoutStore(null).read(), const RailLayout());
    final dir = await directory();
    final store = RailLayoutStore(dir);
    final file = File('${dir.path}/chat-list-layout');
    expect(store.read(), const RailLayout());
    for (final junk in ['[1]', '{"width": "wide"}', 'not json']) {
      await file.writeAsString(junk);
      expect(store.read(), const RailLayout(), reason: junk);
    }
    await file.writeAsBytes([0xff]);
    expect(store.read(), const RailLayout());
  });

  test('the chosen layout survives a fresh store', () async {
    final dir = await directory();
    final container = containerFor(RailLayoutStore(dir));
    final notifier = container.read(railLayoutProvider.notifier);
    notifier.preview(const RailLayout(width: 300));
    expect(RailLayoutStore(dir).read(), const RailLayout(),
        reason: 'a drag step is not saved');
    await notifier.set(const RailLayout(width: 312));
    await notifier.toggle();
    expect(RailLayoutStore(dir).read(),
        const RailLayout(width: 312, collapsed: true));
    expect(containerFor(RailLayoutStore(dir)).read(railLayoutProvider),
        const RailLayout(width: 312, collapsed: true));
  });

  test('a failed save keeps the layout for this run', () async {
    final container = containerFor(RailLayoutStore(null));
    await container
        .read(railLayoutProvider.notifier)
        .set(const RailLayout(collapsed: true));
    expect(container.read(railLayoutProvider).collapsed, isTrue);
  });
}
