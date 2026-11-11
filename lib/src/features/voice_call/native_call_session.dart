import 'dart:async';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;

/// Commands and call state. Rust owns capture, playback and keys, and shows
/// the video itself in the main window's textures.
class NativeCallSession {
  NativeCallSession(
      {required this.sessionId,
      required this.callId,
      required this.bridge,
      required this.requestMicrophone,
      this.requestCamera = _allowCamera,
      this.authorizeMedia,
      required this.onState,
      this.pollInterval = const Duration(milliseconds: 100)});

  final String sessionId;
  String callId;
  final BridgeFacade bridge;
  final Future<bool> Function() requestMicrophone;
  final Future<bool> Function() requestCamera;
  final Future<bool> Function(bool microphone, bool camera)? authorizeMedia;
  static Future<bool> _allowCamera() async => true;
  final void Function() onState;

  /// How often the snapshot is read: often enough to follow the sizes of
  /// the frames it reports.
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
  Future<void> _commands = Future.value();
  Future<void>? _starting;

  bool get muted => !_microphone;
  bool get cameraRequested => _camera;
  Future<void> start({bool camera = false}) => _starting ??= _start(camera);
  Future<void> _start(bool camera) async {
    _camera = camera && await requestCamera();
    if (_closed) return;
    if (_camera) await _authorize(false, true);
    if (_closed) return;
    await bridge.nativeCallPrepare(
        sessionId: sessionId,
        callId: callId,
        microphone: true,
        camera: _camera);
    if (_closed) return;
    await _readState();
    if (_closed) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  void rebind(String canonical) {
    if (canonical == callId) return;
    callId = canonical;
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
        _camera = !_camera && await requestCamera();
      });
  Future<void> enableCamera() => _change(() async {
        _camera = await requestCamera();
      });
  Future<void> selectInput(String? id) => _change(() async {
        _input = id;
      });
  Future<void> selectOutput(String? id) => _change(() async {
        _output = id;
      });
  Future<void> selectCamera(String? id) => _change(() async {
        _cameraId = id;
      }, cameraSelection: true);

  Future<void> _change(Future<void> Function() change,
      {bool cameraSelection = false}) {
    return _commands = _commands.catchError((Object _) {}).then((_) async {
      await _starting;
      if (_closed) return;
      busy = true;
      onState();
      try {
        await change();
        if (_closed) return;
        // The button shows the press now; native media applies it afterwards.
        onState();
        await _authorize(_active && _microphone && _microphoneAllowed, _camera);
        if (_closed) return;
        await bridge.nativeCallChoices(
            sessionId: sessionId,
            callId: callId,
            microphone: _microphone,
            microphoneAllowed: _microphoneAllowed,
            camera: _camera,
            input: _input,
            output: _output,
            cameraId: _cameraId,
            cameraSelection: cameraSelection);
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

  Future<void> _authorize(bool microphone, bool camera) async {
    final authorize = authorizeMedia;
    if (authorize != null && !await authorize(microphone, camera)) {
      throw StateError('Android call service is unavailable');
    }
  }

  Future<void> _poll() async {
    if (_closed || _polling || busy) return;
    _polling = true;
    try {
      await _readState();
    } catch (_) {
      /* Rust still owns the call while state polling retries. */
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
    _timer?.cancel();
    _timer = null;
    // Rust releases media when the authenticated call ends; a renderer does not.
  }
}
