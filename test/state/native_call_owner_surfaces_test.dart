import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_surfaces.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/state/native_call_owner_provider.dart';

import '../support/scriptable_bridge.dart';

CallVideoSurfaces _surfaces(int width) => CallVideoSurfaces(
    local: native.Surface(width: width ~/ 4, height: width * 9 ~/ 16),
    remote: native.Surface(width: width, height: width * 9 ~/ 16));

void main() {
  test('rapid surface reports reach Rust in order, the latest last', () async {
    final bridge = ScriptableBridge();
    final first = Completer<void>();
    bridge.respondNext(BridgeMethod.nativeCallShowVideoAt, first.future);
    final owner = NativeCallOwner(bridge, () async => true);
    addTearDown(owner.dispose);
    owner.showVideoAt(_surfaces(1280));
    owner.showVideoAt(_surfaces(960));
    owner.showVideoAt(_surfaces(640));
    await pumpEventQueue();
    expect(bridge.countOf(BridgeMethod.nativeCallShowVideoAt), 1,
        reason: 'one report in flight at a time');
    first.completeError(StateError('native call is not prepared'));
    await pumpEventQueue();
    expect(
        bridge
            .callsTo(BridgeMethod.nativeCallShowVideoAt)
            .map((call) => call.args['remote']),
        [
          [1280, 720],
          [640, 360],
        ]);
  });
}
