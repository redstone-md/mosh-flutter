import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/desktop_call_window.dart';

import '../../support/call_window_platform.dart';

const _call = CallViewState(
    sessionId: 's',
    callId: 'c',
    peer: 'Alice',
    phase: CallViewPhase.active,
    audioReady: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('handshake precedes presentation and wrong tokens cannot send commands',
      () async {
    final platform = CallWindowPlatform()..install();
    addTearDown(platform.uninstall);
    final commands = <CallViewCommand>[];
    final window =
        await DesktopCallWindow.open((command) async => commands.add(command));
    await window.present(_call);
    await window.show();
    await platform.deliver('parent', 'call-command', {
      ..._call.command(CallViewAction.end).toMap(),
      'token': 'wrong',
    });
    expect(commands, isEmpty);
    await platform.deliver('parent', 'call-command', {
      ..._call.command(CallViewAction.mute).toMap(),
      'token': platform.token,
    });
    expect(commands.single.callId, 'c');
    expect(commands.single.action, CallViewAction.mute);
    await window.close();
    final count = platform.calls.length;
    await window.close();
    await window.present(_call);
    await window.show();
    expect(platform.calls, hasLength(count));
    final methods = platform.calls
        .where((c) => c.method == 'invokeMethod')
        .map((c) => (c.arguments as Map)['method']);
    expect(methods, ['call-present', 'call-show', 'call-close']);
    expect(platform.calls.where((c) => c.method == 'unregisterMethodHandler'),
        hasLength(1));
  });

  test('failed native creation unregisters the parent route', () async {
    final platform = CallWindowPlatform()..failCreate = true;
    platform.install();
    addTearDown(platform.uninstall);
    await expectLater(DesktopCallWindow.open((_) async {}), throwsException);
    expect(platform.calls.where((c) => c.method == 'unregisterMethodHandler'),
        hasLength(1));
  });
}
