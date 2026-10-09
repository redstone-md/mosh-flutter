import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:mosh/src/features/voice_call/native_call_session.dart';
import 'package:mosh/src/features/voice_call/call_video_frame.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';

/// Production supplies the native presentation client only on desktop.
final nativeCallOwnerProvider = Provider<NativeCallOwner?>((ref) => null);

class NativeCallOwner extends ChangeNotifier {
  NativeCallOwner(this.bridge, this.requestMicrophone);
  final BridgeFacade bridge;
  final Future<bool> Function() requestMicrophone;
  final _frames = StreamController<CallVideoFrame>.broadcast(sync: true);
  NativeCallSession? _retained;
  NativeCallSession? session;
  Stream<CallVideoFrame> get frames => _frames.stream;

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
          onState: notifyListeners,
          onFrame: (frame) {
            if (session?.sessionId == frame.sessionId &&
                session?.callId == frame.callId) {
              _frames.add(frame);
            }
          });
      session = current;
      try {
        await current.start(camera: video);
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

  void unbind(String sessionId, String callId) {
    if (session?.sessionId != sessionId || session?.callId != callId) return;
    _stop();
  }

  void _stop() {
    session?.stop();
    _retained?.stop();
    session = null;
    _retained = null;
  }

  @override
  void dispose() {
    _stop();
    unawaited(_frames.close());
    super.dispose();
  }
}
