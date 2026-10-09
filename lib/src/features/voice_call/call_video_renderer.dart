import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'call_video_frame.dart';
import 'call_view_state.dart';

class CallVideoImages {
  const CallVideoImages({this.local, this.remote});
  final ui.Image? local;
  final ui.Image? remote;

  CallVideoImages replace(bool preview, ui.Image? image) => preview
      ? CallVideoImages(local: image, remote: remote)
      : CallVideoImages(local: local, remote: image);
}

/// One image per lane and one decode in flight. Renderer loss affects no media.
class CallVideoRenderer extends ValueNotifier<CallVideoImages> {
  CallVideoRenderer({this.decode = decodeRgba})
      : super(const CallVideoImages());
  final Future<ui.Image> Function(CallVideoFrame) decode;
  CallViewState? _call;
  final _sequence = [0, 0];
  final _expiry = <Timer?>[null, null];
  int _generation = 0;
  bool _decoding = false;
  bool _disposed = false;

  void update(CallViewState? call) {
    final old = _call;
    _call = call;
    if (old?.sessionId == call?.sessionId && old?.callId == call?.callId) {
      if (call?.phase != CallViewPhase.active ||
          call?.media?.remoteCamera == false) {
        _clear(false);
      }
      if (call?.media?.cameraRequested == false) _clear(true);
      return;
    }
    ++_generation;
    _sequence.fillRange(0, 2, 0);
    final merged = old != null &&
        call != null &&
        old.sessionId == call.sessionId &&
        call.supersededCallId == old.callId;
    if (!merged) {
      _clear(true);
      _clear(false);
    }
  }

  bool _matches(CallVideoFrame frame) {
    final call = _call;
    return !_disposed &&
        call != null &&
        frame.sessionId == call.sessionId &&
        frame.callId == call.callId &&
        (frame.local || call.phase == CallViewPhase.active) &&
        (call.media == null ||
            (frame.local
                ? call.media!.cameraRequested
                : call.media!.remoteCamera));
  }

  Future<bool> receive(CallVideoFrame frame) async {
    final lane = frame.local ? 0 : 1;
    if (_decoding || !_matches(frame) || frame.sequence <= _sequence[lane]) {
      return false;
    }
    frame.validate();
    if (frame.sourceAgeMs >= 1000) return false;
    final elapsed = Stopwatch()..start();
    _decoding = true;
    final generation = _generation;
    try {
      final image = await decode(frame);
      final age = frame.sourceAgeMs + elapsed.elapsedMilliseconds;
      if (generation != _generation || !_matches(frame) || age >= 1000) {
        image.dispose();
        return false;
      }
      final old = frame.local ? value.local : value.remote;
      value = value.replace(frame.local, image);
      old?.dispose(); // RawImage keeps its own clone until its next update.
      _sequence[lane] = frame.sequence;
      _expiry[lane]?.cancel();
      _expiry[lane] =
          Timer(Duration(milliseconds: 1000 - age), () => _clear(frame.local));
      return true;
    } finally {
      _decoding = false;
    }
  }

  void _clear(bool local) {
    final lane = local ? 0 : 1;
    _expiry[lane]?.cancel();
    final image = local ? value.local : value.remote;
    if (image == null) return;
    value = value.replace(local, null);
    image.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _clear(true);
    _clear(false);
    super.dispose();
  }

  static Future<ui.Image> decodeRgba(CallVideoFrame frame) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(frame.pixels);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = ui.ImageDescriptor.raw(buffer,
          width: frame.width,
          height: frame.height,
          pixelFormat: ui.PixelFormat.rgba8888);
      codec = await descriptor.instantiateCodec();
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
