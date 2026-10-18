import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/rust/plus/types.dart';
import '../../support/plus/fakes.dart';

void main() {
  test('a read begun before rebuild cannot overwrite the new provider lifetime',
      () async {
    final native = PausedPlusCommands();
    final container = ProviderContainer(overrides: [
      plusConfigProvider.overrideWithValue(testPlusConfig),
      plusCommandsProvider.overrideWithValue(native),
      plusPollIntervalProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    await container.read(plusProvider.future);
    native.pending = Completer<PlusSnapshot>();
    final oldRefresh = container.read(plusProvider.notifier).refresh();
    native.current = PlusSnapshot(active: false, visible: false, peerBadges: [
      PlusPeerBadge(
          identity: 'new-peer', expiresAtMs: BigInt.from(1800057600000))
    ]);
    container.invalidate(plusProvider);
    await container.read(plusProvider.future);
    native.pending!.complete(emptyPlus);
    await oldRefresh;
    expect(
        container
            .read(plusProvider)
            .requireValue
            .snapshot
            .peerBadges
            .single
            .identity,
        'new-peer');
  });
}

class PausedPlusCommands extends MemoryPlusCommands {
  Completer<PlusSnapshot>? pending;
  @override
  Future<PlusSnapshot> snapshot() => pending?.future ?? super.snapshot();
}
