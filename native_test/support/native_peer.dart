import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Another installation using the same real runtime harness as the Rust tests.
class NativePeer {
  NativePeer(this._process, this._dir, this._lines);
  final Process _process;
  final Directory _dir;
  final StreamIterator<String> _lines;
  static const _prefix = 'MOSH_TEST_JSON ';

  static Future<NativePeer> start() async {
    final dir = await Directory.systemTemp.createTemp('mosh-native-peer-');
    final random = Random.secure();
    await File('${dir.path}/storage-key.bin')
        .writeAsBytes(List.generate(32, (_) => random.nextInt(256)));
    final executables = Directory('mosh-core/target/debug/deps')
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.uri.pathSegments.last.startsWith('device_link_flow-') &&
            (Platform.isWindows
                ? f.path.endsWith('.exe')
                : !f.uri.pathSegments.last.contains('.')));
    final process = await Process.start(
        executables.first.absolute.path,
        [
          '--exact',
          'independent_installation_process',
          '--ignored',
          '--nocapture'
        ],
        workingDirectory: Directory.current.path,
        environment: {
          'MOSH_LINK_TEST_DIR': dir.path,
          'MOSH_LINK_TEST_PORT': '0'
        });
    process.stderr.drain<void>();
    final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    final peer = NativePeer(process, dir, lines);
    await peer.ask({'action': 'snapshot'});
    return peer;
  }

  Future<Map<String, dynamic>> ask(Map<String, Object?> command) async {
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

  Future<void> close() async {
    _process.stdin.writeln(jsonEncode({'action': 'shutdown'}));
    await _process.stdin.close();
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process.kill();
      return -1;
    });
    await _lines.cancel();
    await _dir.delete(recursive: true);
  }
}
