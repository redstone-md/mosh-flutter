import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'call_view_state.dart';
import 'call_window_coordinator.dart';
import 'call_window_pipe.dart';
import 'call_window_frame_channel.dart';
import 'call_video_frame.dart';

const callWindowProcessArgument = '--mosh-call-window';
const _callWindowEnvironment = 'MOSH_CALL_WINDOW';

bool get isCallWindowProcess =>
    Platform.environment[_callWindowEnvironment] == '1';

/// Each desktop keeps renderer ownership in a separate process. Audio and
/// signaling stay in the main process, behind the same call-window boundary.
class ProcessCallWindow
    implements CallWindowHandle, CallWindowFrameSink, CallWindowLifecycle {
  ProcessCallWindow._(this._process, this._pipe, this._frames);
  final Process _process;
  final CallWindowPipe _pipe;
  final CallWindowFrameChannel _frames;
  bool _closed = false;
  bool _frameLost = false;
  CallViewState? _presented;
  ({String session, String call, int sequence, bool local})? _frame;
  Timer? _frameDeadline;
  Stopwatch? _frameElapsed;

  @override
  Future<void> get closed => _process.exitCode.then((_) {});

  static Future<CallWindowHandle> open(
      Future<void> Function(CallViewCommand) onCommand,
      {Future<Process> Function()? startProcess}) async {
    final frames = await CallWindowFrameChannel.bind();
    Process? process;
    ProcessCallWindow? window;
    try {
      process = await (startProcess?.call() ??
          Process.start(
              Platform.resolvedExecutable, [callWindowProcessArgument],
              environment: {_callWindowEnvironment: '1'}));
      final attached = _attach(process, frames, onCommand);
      window = attached.$1;
      await attached.$2.timeout(const Duration(seconds: 10));
      await window._pipe.invoke('call-frame-channel', frames.descriptor);
      await frames.ready.timeout(const Duration(seconds: 5));
      return window;
    } catch (_) {
      if (window != null) {
        await window.close();
      } else {
        process?.kill();
        await frames.dispose();
      }
      rethrow;
    }
  }

  static (ProcessCallWindow, Future<void>) _attach(
      Process process,
      CallWindowFrameChannel frames,
      Future<void> Function(CallViewCommand) onCommand) {
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    final ready = Completer<void>();
    late final ProcessCallWindow window;
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
      } else if (call.method == 'call-frame-ack') {
        window._ackFrame(call.arguments as Map<Object?, Object?>);
      } else {
        throw StateError('Unknown call window method');
      }
      return null;
    };
    pipe.onClosed = () {
      window._frameLost = true;
      window._frameDeadline?.cancel();
      if (!ready.isCompleted) {
        ready.completeError(StateError('Call window exited'));
      }
    };
    window = ProcessCallWindow._(process, pipe, frames);
    frames.onClosed = () => window._frameLost = true;
    return (window, ready.future);
  }

  @override
  Future<void> present(CallViewState state) async {
    if (_closed) return;
    await _pipe.invoke('call-present', state.toMap());
    _presented = state;
  }

  @override
  bool presentFrame(CallVideoFrame frame) {
    if (_closed ||
        _frameLost ||
        _frame != null ||
        frame.callId != _presented?.callId ||
        frame.sessionId != _presented?.sessionId) {
      return false;
    }
    final packet = frame.encode();
    _frame = (
      session: frame.sessionId,
      call: frame.callId,
      sequence: frame.sequence,
      local: frame.local
    );
    try {
      if (Platform.environment['MOSH_CALL_FRAME_PROFILE'] == '1') {
        _frameElapsed = Stopwatch()..start();
      }
      if (!_frames.send(packet)) {
        _frameLost = true;
        return false;
      }
      _frameDeadline = Timer(const Duration(seconds: 5), () {
        // A stalled renderer cannot accumulate more frame data or own the call.
        _frameLost = true;
        _process.kill();
      });
      return true;
    } catch (_) {
      _frameLost = true;
      return false;
    }
  }

  void _ackFrame(Map<Object?, Object?> ack) {
    final frame = _frame;
    if (frame == null ||
        ack['sessionId'] != frame.session ||
        ack['callId'] != frame.call ||
        ack['sequence'] != frame.sequence ||
        ack['local'] != frame.local) {
      return;
    }
    _frameDeadline?.cancel();
    if (_frameElapsed != null) {
      stdout.writeln('perf.profile.frame ${jsonEncode({
            'roundTripMs': _frameElapsed!.elapsedMilliseconds,
            'child': ack['profile']
          })}');
      _frameElapsed = null;
    }
    _frame = null;
  }

  @override
  Future<void> show() async {
    if (_frameLost) throw StateError('Call frame stream lost');
    if (!_closed) await _pipe.invoke('call-show');
  }

  @override
  Future<bool> isFocused() async =>
      !_closed && await _pipe.invoke('call-is-focused') == true;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _frameDeadline?.cancel();
    _frame = null;
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
      await _frames.dispose();
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
