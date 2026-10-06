import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'voice_call_scenario.dart';

/// Optional Linux window-manager checks. Requires X11, a WM and xdotool.
class DesktopWindowActions {
  DesktopWindowActions(this.tester);
  final WidgetTester tester;
  static bool get enabled =>
      Platform.isLinux &&
      Platform.environment['MOSH_TEST_WINDOW_ACTIONS'] == '1';

  Future<String> callWindow() async {
    // The process becomes ready before the parent presents its peer metadata.
    for (var attempt = 0; attempt < 30; attempt++) {
      final result = await tester.runAsync(
          () => Process.run('xdotool', ['search', '--name', '^Mosh ·']));
      if (result!.exitCode == 0) {
        final ids = (result.stdout as String).trim().split('\n');
        expect(ids, hasLength(1), reason: 'Exactly one native call window');
        return ids.single;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    throw TestFailure('Native call window did not become visible');
  }

  Future<void> minimize(String id) async {
    await _run(['windowminimize', id]);
  }

  Future<bool> minimized(String id) async {
    final result = await tester
        .runAsync(() => Process.run('xprop', ['-id', id, '_NET_WM_STATE']));
    expect(result!.exitCode, 0);
    return (result.stdout as String).contains('_NET_WM_STATE_HIDDEN');
  }

  Future<void> close(String id) async {
    await _run(['windowactivate', '--sync', id, 'key', 'alt+F4']);
  }

  Future<String> _run(List<String> args) async {
    final result = await tester.runAsync(() => Process.run('xdotool', args));
    expect(result!.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }
}

class DesktopCallWindowScenario {
  DesktopCallWindowScenario(this.flow);
  final VoiceCallScenario flow;

  Future<void> run() async {
    if (!DesktopWindowActions.enabled) return;
    final windows = DesktopWindowActions(flow.tester);
    final ui = flow.ui;
    // OS close must cancel or decline the displayed call, without a modal.
    await ui.tap(find.byTooltip('Start voice call'));
    await flow.pendingRemote();
    await ui.eventually(() async => flow.audio.windows == 1);
    await windows.close(await windows.callWindow());
    await ui.eventually(
        () async => (await flow.remote('dm_poll'))['pending_call'] == null);
    await ui.eventually(() async => flow.audio.windows == 0);
    await flow.remote('call_start');
    await ui.visible(find.byTooltip('Accept call'));
    await ui.eventually(() async => flow.audio.windows == 1);
    await windows.close(await windows.callWindow());
    await ui.eventually(
        () async => (await flow.remote('dm_poll'))['outgoing_call'] == null);
    await ui.eventually(() async => flow.audio.windows == 0);
    await _minimizeAndHangUp(windows);
  }

  Future<void> _minimizeAndHangUp(DesktopWindowActions windows) async {
    final ui = flow.ui;
    final audio = flow.audio;
    await ui.tap(find.byTooltip('Start voice call'));
    await flow.remote('call_accept', await flow.pendingRemote());
    await ui.eventually(() async => audio.captures == 3 && audio.players == 3);
    await ui.eventually(() async => flow.audio.windows == 1);
    final id = await windows.callWindow();
    await windows.minimize(id);
    await ui.eventually(() => windows.minimized(id));
    final before = audio.playedFrames;
    await ui.eventually(() async {
      await flow.remote('call_probe');
      return audio.playedFrames > before;
    });
    expect(audio.captureStops, 2);
    expect(audio.playerStops, 2);
    await ui.tap(find.byTooltip('Show call window'));
    await ui.eventually(() async => !await windows.minimized(id));
    await windows.close(id);
    await ui.eventually(
        () async => audio.captureStops == 3 && audio.playerStops == 3);
    await ui.eventually(() async => flow.audio.windows == 0);
    expect(audio.rings, audio.ringStops);
  }
}
