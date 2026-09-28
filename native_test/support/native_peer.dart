import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Another installation using the same real runtime harness as the Rust tests.
class NativePeer {
  NativePeer(
      this._process, this._dir, this._lines, this._api, this._executable);
  Process _process;
  final Directory _dir;
  StreamIterator<String> _lines;
  final bool _api;
  final String _executable;
  bool _stopped = false;
  static const _prefix = 'MOSH_TEST_JSON ';

  static Future<NativePeer> start(
      {bool api = false, String? executable}) async {
    final dir = await Directory.systemTemp.createTemp('mosh-native-peer-');
    try {
      final random = Random.secure();
      await File('${dir.path}/storage-key.bin')
          .writeAsBytes(List.generate(32, (_) => random.nextInt(256)));
      return await _spawn(dir, api, executable);
    } catch (_) {
      await dir.delete(recursive: true).catchError((Object _) => dir);
      rethrow;
    }
  }

  static Future<NativePeer> _spawn(
      Directory dir, bool api, String? executable) async {
    final worker = executable ??
        Directory('mosh-core/target/debug/deps')
            .listSync()
            .whereType<File>()
            .firstWhere((f) =>
                f.uri.pathSegments.last.startsWith('device_link_flow-') &&
                (Platform.isWindows
                    ? f.path.endsWith('.exe')
                    : !f.uri.pathSegments.last.contains('.')))
            .absolute
            .path;
    final process = await Process.start(
        worker,
        [
          '--exact',
          'independent_installation_process',
          '--ignored',
          '--nocapture'
        ],
        workingDirectory: Directory.current.path,
        environment: {
          'MOSH_LINK_TEST_DIR': dir.path,
          'MOSH_LINK_TEST_PORT': '0',
          'MOSH_LINK_TEST_API': api ? '1' : '0',
        });
    process.stderr.drain<void>();
    final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    final peer = NativePeer(process, dir, lines, api, worker);
    try {
      await peer.ask({'action': 'snapshot'});
      return peer;
    } catch (_) {
      await peer.stop().catchError((Object _) {});
      rethrow;
    }
  }

  Future<Map<String, dynamic>> ask(Map<String, Object?> command) async {
    if (_stopped) throw StateError('Independent native peer is stopped');
    _process.stdin.writeln(jsonEncode(command));
    await _process.stdin.flush();
    while (await _lines.moveNext().timeout(const Duration(seconds: 40))) {
      if (_lines.current.startsWith(_prefix)) {
        return jsonDecode(_lines.current.substring(_prefix.length))
            as Map<String, dynamic>;
      }
    }
    throw StateError('Independent native peer exited');
  }

  Future<Map<String, dynamic>> waitPhase(String phase) async {
    final until = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(until)) {
      final snapshot = await ask({'action': 'snapshot'});
      if (snapshot['phase'] == phase) return snapshot;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Independent peer did not reach $phase');
  }

  Future<void> restart() async {
    await stop();
    final peer = await _spawn(_dir, _api, _executable);
    _process = peer._process;
    _lines = peer._lines;
    _stopped = false;
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      _process.stdin.writeln(jsonEncode({'action': 'shutdown'}));
      await _process.stdin.close();
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } finally {
      _process.kill();
      await _lines.cancel();
    }
  }

  Future<void> close() async {
    try {
      await stop();
    } finally {
      await _dir.delete(recursive: true);
    }
  }
}
