import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_renderer.dart';
import 'package:mosh/src/features/voice_call/call_video_stage.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/state/native_call_owner_provider.dart';

import '../../support/native_call_fixture.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

/// The platform plugin: texture ids 7 and 8, exported at two addresses.
void _plugin(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      CallVideoTextures.channel,
      (call) async => {
            'local': [7, 4096],
            'remote': [8, 8192],
          });
  addTearDown(() =>
      messenger.setMockMethodCallHandler(CallVideoTextures.channel, null));
}

native.Snapshot _showing({int local = 0, int remote = 0}) => nativeCallSnapshot(
    camera: true,
    localVideo: native.Surface(width: local, height: local * 9 ~/ 16),
    remoteVideo: native.Surface(width: remote, height: remote * 9 ~/ 16));

void main() {
  testWidgets(
      'a call shown in textures hands Rust their addresses and polls '
      'no frame', (tester) async {
    _plugin(tester);
    final bridge = ScriptableBridge()
      ..seedNativeCallSnapshot(_showing(local: 320, remote: 1280));
    final owner = NativeCallOwner(bridge, () async => true,
        textures: CallVideoTextures());
    addTearDown(owner.dispose);
    await owner.bind('dm', 'call', video: true);
    expect(bridge.callsTo(BridgeMethod.nativeCallShowVideoIn).single.args,
        {'local': 4096, 'remote': 8192});

    await tester.pump(const Duration(seconds: 1));
    expect(bridge.countOf(BridgeMethod.nativeCallFrame), 0);
    expect(owner.textures!.value.local, const TextureVideo(7, 320, 180));
    expect(owner.textures!.value.remote, const TextureVideo(8, 1280, 720));

    owner.unbind('dm', 'call');
    expect(owner.textures!.value.remote, isNull);
  });

  testWidgets('a lane shows only while the snapshot reports a live frame',
      (tester) async {
    _plugin(tester);
    final textures = CallVideoTextures();
    addTearDown(textures.dispose);
    textures.show(_showing(remote: 1280), camera: true);
    expect(textures.value.remote, isNull, reason: 'no texture registered yet');
    await textures.attach(ScriptableBridge());

    textures.show(_showing(local: 320, remote: 1280), camera: true);
    expect(textures.value.local, isNotNull);
    textures.show(_showing(local: 320, remote: 1280), camera: false);
    expect(textures.value.local, isNull,
        reason: 'the preview leaves with the camera switch');
    expect(textures.value.remote, isNotNull);
    textures.show(_showing(), camera: true);
    expect(textures.value.remote, isNull);
  });

  testWidgets('a texture keeps the shape of the frame it shows',
      (tester) async {
    final images =
        ValueNotifier(const CallVideoImages(remote: TextureVideo(8, 400, 400)));
    addTearDown(images.dispose);
    await pumpScreen(
        tester,
        Scaffold(
            body: Center(
                child: SizedBox(
                    width: 640,
                    child: CallVideoStage(
                        images: images, peer: 'Alice', remoteCamera: true)))),
        settle: false);
    final texture = find.byType(Texture);
    expect(tester.widget<Texture>(texture).textureId, 8);
    final size = tester.getSize(texture);
    expect(size.width, size.height, reason: 'a square frame in a 16:9 stage');
  });
}
