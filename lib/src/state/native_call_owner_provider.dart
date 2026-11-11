import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:mosh/src/features/voice_call/native_call_session.dart';
import 'package:mosh/src/features/voice_call/call_video_surfaces.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';

/// Production supplies the presentation client for compatible native platforms.
final nativeCallOwnerProvider = Provider<NativeCallOwner?>((ref) => null);

class NativeCallOwner extends ChangeNotifier {
  NativeCallOwner(this.bridge, this.requestMicrophone,
      {this.requestCamera, this.authorizeMedia});
  final BridgeFacade bridge;
  final Future<bool> Function() requestMicrophone;
  final Future<bool> Function()? requestCamera;
  final Future<bool> Function(bool microphone, bool camera)? authorizeMedia;

  /// The main window's video textures, which Rust shows the video in.
  final textures = CallVideoTextures();
  NativeCallSession? _retained;
  CallVideoSurfaces? _surfaces, _unsent;
  bool _showing = false;
  NativeCallSession? session;

  Future<void> bind(String sessionId, String callId,
      {String? superseded, bool active = false, bool video = false}) async {
    var current = session;
    if (current?.sessionId != sessionId ||
        current?.callId != callId && current?.callId != superseded) {
      current = NativeCallSession(
          sessionId: sessionId,
          callId: callId,
          bridge: bridge,
          requestMicrophone: requestMicrophone,
          requestCamera: requestCamera ?? () async => true,
          authorizeMedia: authorizeMedia,
          onState: _changed);
      session = current;
      try {
        await current.start(camera: video);
        await _attachTextures();
        final surfaces = _surfaces;
        if (surfaces != null) showVideoAt(surfaces);
        if (identical(session, current)) {
          _retained?.stop();
          _retained = current;
        } else {
          current.stop();
        }
      } catch (_) {
        current.stop();
        if (identical(session, current)) session = _retained;
        rethrow;
      }
    } else {
      current!.rebind(callId);
      if (video && !current.cameraRequested) {
        await current.enableCamera();
      }
    }
    if (identical(current, session) && active) await current.confirm();
  }

  /// Frames of every call leave Rust at most at these sizes. Rust refuses
  /// a report before the first call is prepared, so a new session sends the
  /// latest one again. One report is in flight at a time, so a slower older
  /// one never lands after the latest.
  void showVideoAt(CallVideoSurfaces surfaces) {
    _surfaces = _unsent = surfaces;
    if (!_showing) unawaited(_show());
  }

  Future<void> _show() async {
    _showing = true;
    for (var next = _unsent; next != null; next = _unsent) {
      _unsent = null;
      try {
        await bridge.nativeCallShowVideoAt(
            local: next.local, remote: next.remote);
      } catch (_) {/* Resent once a session starts. */}
    }
    _showing = false;
  }

  /// A call keeps its media when its video cannot be shown.
  Future<void> _attachTextures() async {
    try {
      await textures.attach(bridge);
    } catch (error) {
      debugPrint('Call video textures unavailable: ${error.runtimeType}');
    }
  }

  void _changed() {
    final current = session;
    textures.show(current?.snapshot, camera: current?.cameraRequested == true);
    notifyListeners();
  }

  void unbind(String sessionId, String callId) {
    if (session?.sessionId != sessionId || session?.callId != callId) return;
    _stop();
  }

  void _stop() {
    session?.stop();
    _retained?.stop();
    session = null;
    _retained = null;
    textures.show(null, camera: false);
  }

  @override
  void dispose() {
    _stop();
    textures.dispose();
    super.dispose();
  }
}
