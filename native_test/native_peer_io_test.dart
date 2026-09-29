import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/native_peer.dart';

void main() {
  late Directory dir;
  late String executable;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('mosh-peer-stdout-');
    executable = '${dir.path}/stdout_flood${Platform.isWindows ? '.exe' : ''}';
    final compile = await Process.run('rustc', [
      'native_test/support/stdout_flood.rs',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: compile.stderr.toString());
  });
  tearDownAll(() => dir.delete(recursive: true));

  test('native peer drains background output between replies', () async {
    final peer = await NativePeer.start(executable: executable);
    addTearDown(peer.close);
    final reply = await peer.ask({'action': 'prepare'});
    final marker = File(reply['marker'] as String);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!await marker.exists() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(await marker.exists(), isTrue,
        reason: 'Peer must finish stdout while no reply is being requested');
    expect((await peer.ask({'action': 'snapshot'}))['phase'], 'Idle');
  });

  test('native peer reports EOF before the first reply', () async {
    await expectLater(
        NativePeer.start(api: true, executable: executable),
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            'Independent native peer exited')));
  });
}
