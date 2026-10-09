import 'dart:async';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'call_video_frame.dart';

/// Commands and latest-frame presentation. Rust owns capture, playback and keys.
class NativeCallSession {
  NativeCallSession(
      {required this.sessionId,
      required this.callId,
      required this.bridge,
      required this.requestMicrophone,
      required this.onState,
      required this.onFrame,
      this.pollInterval = const Duration(milliseconds: 16)});

  final String sessionId;
  String callId;
  final BridgeFacade bridge;
  final Future<bool> Function() requestMicrophone;
  final void Function() onState;
  final void Function(CallVideoFrame) onFrame;
  final Duration pollInterval;
  native.Snapshot? snapshot;
  bool busy = false;
  bool _closed = false;
  bool _active = false;
  bool _microphoneAllowed = false;
  bool _microphone = true;
  bool _camera = false;
  String? _input;
  String? _output;
  String? _cameraId;
  Timer? _timer;
  bool _polling = false;
  int _lane = 0;
  DateTime _nextState = DateTime.fromMillisecondsSinceEpoch(0);
  final _sequence = [BigInt.zero, BigInt.zero];
  Future<void> _commands = Future.value();
  Future<void>? _starting;
  int _generation = 0;

  bool get muted => !_microphone;
  bool get cameraRequested => _camera;
  Future<void> start({bool camera = false}) => _starting ??= _start(camera);
  Future<void> _start(bool camera) async {
    _camera = camera;
    await bridge.nativeCallPrepare(
        sessionId: sessionId, callId: callId, microphone: true, camera: camera);
    if (_closed) return;
    await _readState();
    if (_closed) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  void rebind(String canonical) {
    if (canonical == callId) return;
    callId = canonical;
    ++_generation;
    _sequence.fillRange(0, 2, BigInt.zero);
    snapshot = null;
  }

  Future<void> confirm() async {
    if (_closed || _active) return;
    _active = true;
    await _starting;
    if (!_closed && _microphone) {
      await _change(() async {
        _microphoneAllowed = await requestMicrophone();
        if (!_microphoneAllowed) _microphone = false;
      });
    }
  }

  Future<void> toggleMicrophone() => _change(() async {
        if (!_microphone && _active) {
          _microphoneAllowed = await requestMicrophone();
        }
        _microphone = !_microphone && (!_active || _microphoneAllowed);
      });
  Future<void> toggleCamera() => _change(() async {
        _camera = !_camera;
      });
  Future<void> enableCamera() => _change(() async {
        _camera = true;
      });
  Future<void> selectInput(String? id) => _change(() async {
        _input = id;
      });
  Future<void> selectOutput(String? id) => _change(() async {
        _output = id;
      });
  Future<void> selectCamera(String? id) => _change(() async {
        _cameraId = id;
      });

  Future<void> _change(Future<void> Function() change) {
    return _commands = _commands.catchError((Object _) {}).then((_) async {
      await _starting;
      if (_closed) return;
      busy = true;
      onState();
      try {
        await change();
        if (_closed) return;
        await bridge.nativeCallChoices(
            sessionId: sessionId,
            callId: callId,
            microphone: _microphone,
            microphoneAllowed: _microphoneAllowed,
            camera: _camera,
            input: _input,
            output: _output,
            cameraId: _cameraId);
        if (!_closed) await _readState();
      } finally {
        busy = false;
        if (!_closed) {
          _reconcile();
          onState();
        }
      }
    });
  }

  Future<void> _poll() async {
    if (_closed || _polling) return;
    _polling = true;
    try {
      if (!busy && DateTime.now().isAfter(_nextState)) {
        _nextState = DateTime.now().add(const Duration(milliseconds: 250));
        await _readState();
      }
      if (_closed) return;
      // Remote gets two slots for each preview slot. No queued frames.
      final local = _lane++ % 3 == 2;
      final lane = local ? 0 : 1;
      final generation = _generation;
      final id = callId;
      final transfer = Stopwatch()..start();
      final frame = await bridge.nativeCallFrame(
          sessionId: sessionId,
          callId: id,
          local: local,
          after: _sequence[lane]);
      if (_closed ||
          generation != _generation ||
          frame == null ||
          frame.local != local ||
          frame.sessionId != sessionId ||
          frame.callId != callId ||
          frame.sequence <= _sequence[lane]) {
        return;
      }
      final age = frame.sourceAgeMs + transfer.elapsedMilliseconds;
      if (age >= 1000) return;
      _sequence[lane] = frame.sequence;
      onFrame(CallVideoFrame(
          sessionId: frame.sessionId,
          callId: frame.callId,
          sequence: frame.sequence.toInt(),
          width: frame.width,
          height: frame.height,
          local: frame.local,
          sourceAgeMs: age,
          pixels: frame.pixels));
    } catch (_) {
      /* Rust still owns the call while presentation polling retries. */
    } finally {
      _polling = false;
    }
  }

  Future<void> _readState() async {
    final id = callId;
    final next =
        await bridge.nativeCallSnapshot(sessionId: sessionId, callId: id);
    if (_closed ||
        id != callId ||
        next == null ||
        next.sessionId != sessionId ||
        next.callId != callId) {
      return;
    }
    snapshot = next;
    if (!busy) _reconcile();
    onState();
  }

  void _reconcile() {
    final next = snapshot;
    if (next == null) return;
    _microphone = next.microphoneRequested;
    _camera = next.cameraRequested;
    _input = next.input;
    _output = next.output;
    _cameraId = next.cameraId;
  }

  void stop() {
    _closed = true;
    ++_generation;
    _timer?.cancel();
    _timer = null;
    // Rust releases media when the authenticated call ends; a renderer does not.
  }
}
