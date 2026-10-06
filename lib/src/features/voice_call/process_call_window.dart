import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'call_view_state.dart';
import 'call_window_coordinator.dart';
import 'call_window_pipe.dart';

const callWindowProcessArgument = '--mosh-call-window';
const _callWindowEnvironment = 'MOSH_CALL_WINDOW';

bool get isCallWindowProcess =>
    Platform.environment[_callWindowEnvironment] == '1';

/// Each desktop keeps renderer ownership in a separate process. Audio and
/// signaling stay in the main process, behind the same call-window boundary.
class ProcessCallWindow implements CallWindowHandle {
  ProcessCallWindow._(this._process, this._pipe);
  final Process _process;
  final CallWindowPipe _pipe;
  bool _closed = false;

  static Future<CallWindowHandle> open(
      Future<void> Function(CallViewCommand) onCommand,
      {Future<Process> Function()? startProcess}) async {
    final process = await (startProcess?.call() ??
        Process.start(Platform.resolvedExecutable, [callWindowProcessArgument],
            environment: {_callWindowEnvironment: '1'}));
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    final ready = Completer<void>();
    final pipe = CallWindowPipe(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
        process.stdin.writeln,
        outputDone: process.stdin.done);
    pipe.onMethod = (call) async {
      if (call.method == 'call-ready') {
        if (!ready.isCompleted) ready.complete();
      } else if (call.method == 'call-command') {
        await onCommand(
            CallViewCommand.fromMap(call.arguments as Map<Object?, Object?>));
      } else {
        throw StateError('Unknown call window method');
      }
      return null;
    };
    pipe.onClosed = () {
      if (!ready.isCompleted) {
        ready.completeError(StateError('Call window exited'));
      }
    };
    final window = ProcessCallWindow._(process, pipe);
    try {
      await ready.future.timeout(const Duration(seconds: 10));
      return window;
    } catch (_) {
      await window.close();
      rethrow;
    }
  }

  @override
  Future<void> present(CallViewState state) async {
    if (!_closed) await _pipe.invoke('call-present', state.toMap());
  }

  @override
  Future<void> show() async {
    if (!_closed) await _pipe.invoke('call-show');
  }

  @override
  Future<bool> isFocused() async =>
      !_closed && await _pipe.invoke('call-is-focused') == true;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _pipe.invoke('call-close').timeout(const Duration(seconds: 2));
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      _process.kill();
      try {
        await _process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        _process.kill(ProcessSignal.sigkill);
        await _process.exitCode.timeout(const Duration(seconds: 2));
      }
    } finally {
      // A terminated child can leave a broken input pipe. Release both handles
      // without replacing the process exit result with a cleanup error.
      try {
        await _pipe.dispose();
      } catch (_) {}
      try {
        await _process.stdin.close();
      } catch (_) {}
    }
  }
}
