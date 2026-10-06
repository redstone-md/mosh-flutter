import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_window_pipe.dart';

/// Process fixture at the inherited stdio boundary; no platform plugin needed.
class CallWindowProcess extends Fake implements Process {
  CallWindowProcess(
      {this.failClose = false,
      this.ignoreTerminate = false,
      bool failInputClose = false}) {
    stdin = _Input(_receive, failInputClose);
    _emit({'id': 1, 'method': 'call-ready'});
  }

  final bool failClose;
  final bool ignoreTerminate;
  final commands = <String>[];
  final _output = StreamController<List<int>>();
  final _exited = Completer<int>();
  int kills = 0;
  ProcessSignal? lastSignal;
  @override
  late final IOSink stdin;
  @override
  Stream<List<int>> get stdout => _output.stream;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => _exited.future;

  void _emit(Map<String, Object?> message) => _output
      .add(utf8.encode('${CallWindowPipe.prefix}${jsonEncode(message)}\n'));

  void _receive(Object? line) {
    final message =
        jsonDecode((line as String).substring(CallWindowPipe.prefix.length))
            as Map;
    final method = message['method'] as String?;
    if (method == null) return;
    commands.add(method);
    _emit({
      'id': message['id'],
      if (method == 'call-close' && failClose) 'error': true
    });
    if (method == 'call-close' && !failClose) _exit();
  }

  void _exit() {
    if (_exited.isCompleted) return;
    _exited.complete(0);
    unawaited(_output.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    lastSignal = signal;
    if (ignoreTerminate && signal != ProcessSignal.sigkill) return false;
    _exit();
    return true;
  }
}

class _Input extends Fake implements IOSink {
  _Input(this.receive, this.failClose);
  final void Function(Object?) receive;
  final bool failClose;
  final _done = Completer<void>();
  @override
  Future<void> get done => _done.future;
  @override
  void writeln([Object? object = '']) => receive(object);
  @override
  Future<void> close() async {
    if (!_done.isCompleted) {
      if (failClose) {
        _done.completeError(StateError('Broken pipe'));
      } else {
        _done.complete();
      }
    }
    await done;
  }
}
