import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_window_app.dart';
import 'package:window_manager/window_manager.dart';

import '../../support/call_window_platform.dart';

const _manager = MethodChannel('window_manager');
const _screen = MethodChannel('dev.leanflutter.plugins/screen_retriever');
const _display = {
  'id': 'screen',
  'size': {'width': 1280.0, 'height': 720.0},
  'visiblePosition': {'dx': 0.0, 'dy': 0.0}
};

void _installWindowManager(CallWindowPlatform platform) {
  platform.messenger.setMockMethodCallHandler(_manager, (call) async {
    platform.calls.add(call);
    if (call.method.startsWith('is')) return false;
    if (call.method == 'getBounds') {
      return {'x': 0.0, 'y': 0.0, 'width': 420.0, 'height': 300.0};
    }
    return null;
  });
  platform.messenger.setMockMethodCallHandler(
      _screen,
      (call) async => switch (call.method) {
            'getPrimaryDisplay' => _display,
            'getAllDisplays' => {
                'displays': [_display]
              },
            'getCursorScreenPoint' => {'dx': 0.0, 'dy': 0.0},
            _ => null,
          });
}

Future<void> _osClose(CallWindowPlatform platform) async {
  final reply = Completer<ByteData?>();
  platform.messenger.handlePlatformMessage(
      _manager.name,
      const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {'eventName': 'close'})),
      reply.complete);
  await reply.future;
}

void main() {
  testWidgets(
      'child renders metadata and routes controls and OS close to its parent',
      (tester) async {
    final platform = CallWindowPlatform();
    _installWindowManager(platform);
    final commands = <Map<String, Object?>>[];
    final handle = await startCallWindowView((command) async {
      commands.add(command.toMap());
    });
    await tester.pump();
    const incoming = CallViewState(
        sessionId: 'origin',
        callId: 'incoming',
        peer: 'Alice',
        phase: CallViewPhase.incoming);
    await handle(MethodCall('call-present', incoming.toMap()));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.tap(find.byTooltip('Accept call'));
    await tester.pump();
    await handle(MethodCall(
        'call-present',
        const CallViewState(
                sessionId: 'origin',
                callId: 'incoming',
                peer: 'Alice',
                phase: CallViewPhase.incoming,
                busy: true)
            .toMap()));
    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel call'));
    await tester.pump();
    await _osClose(platform);
    await tester.pump();
    const active = CallViewState(
        sessionId: 'origin',
        callId: 'active',
        peer: 'Alice',
        phase: CallViewPhase.active,
        audioReady: true);
    final oldView = tester.widget<CallView>(find.byType(CallView));
    await handle(MethodCall('call-present', active.toMap()));
    oldView.onAction(CallViewAction.end);
    await tester.pump();
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    await _osClose(platform);
    await tester.pump();
    await handle(const MethodCall('call-show'));
    expect(platform.calls.where((call) => call.method == 'restore'), isEmpty);
    expect(await handle(const MethodCall('call-is-focused')), isFalse);
    expect(commands.map((args) => args['action']), [
      'openConversation',
      'accept',
      'openConversation',
      'end',
      'end',
      'mute',
      'end'
    ]);
    expect(commands.map((args) => args['sessionId']).toSet(), {'origin'});
    expect(commands.map((args) => args['callId']), [
      'incoming',
      'incoming',
      'incoming',
      'incoming',
      'incoming',
      'active',
      'active'
    ]);
    await handle(const MethodCall('call-close'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(
        platform.calls.where((call) => call.method == 'close'), hasLength(1));
    await _osClose(platform);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final listener in windowManager.listeners) {
      windowManager.removeListener(listener);
    }
    platform.messenger.setMockMethodCallHandler(_manager, null);
    platform.messenger.setMockMethodCallHandler(_screen, null);
  });
}
