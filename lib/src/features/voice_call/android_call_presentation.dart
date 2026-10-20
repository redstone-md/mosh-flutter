import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_view_state.dart';

final androidCallPresentationProvider =
    Provider<AndroidCallPresentation?>((ref) => null);

/// Activity presentation only. Media and signaling retain their existing owner.
class AndroidCallPresentation extends ChangeNotifier {
  AndroidCallPresentation() {
    channel.setMethodCallHandler(_receive);
  }
  static const channel = MethodChannel('app.mosh/call-presentation');
  String? _key;
  bool _video = false;
  bool inPip = false;
  bool _disposed = false;
  void Function(String sessionId, String callId)? onClose;
  CallViewState? _call;

  void update(CallViewState? call) {
    final key = call == null ? null : '${call.sessionId}/${call.callId}';
    final same = key == _key;
    final video = call?.phase == CallViewPhase.active &&
        ((same && _video) ||
            call?.media?.cameraRequested == true ||
            call?.media?.remoteCamera == true);
    _call = call;
    if (same && video == _video) return;
    _key = key;
    _video = video;
    unawaited(_configure(key, video));
  }

  Future<void> _configure(String? key, bool video) async {
    try {
      await channel
          .invokeMethod<void>('configure', {'call': key, 'video': video});
    } catch (error) {
      debugPrint('Android PiP unavailable: ${error.runtimeType}');
    }
  }

  Future<void> _receive(MethodCall event) async {
    if (_disposed) return;
    final args = event.arguments as Map;
    if (args['call'] != _key || _key == null) return;
    if (event.method == 'closed') {
      final call = _call;
      if (call != null) onClose?.call(call.sessionId, call.callId);
    } else if (event.method == 'mode') {
      inPip = args['pip'] == true;
      notifyListeners();
      if (inPip) {
        final key = _key;
        unawaited(_ready(key));
      }
    }
  }

  Future<void> _ready(String? key) async {
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed || key != _key || !inPip) return;
    try {
      await channel.invokeMethod<void>('ready', {'call': key});
    } catch (_) {
      // A closed Activity needs no presentation acknowledgement.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    unawaited(_configure(null, false));
    super.dispose();
  }
}
