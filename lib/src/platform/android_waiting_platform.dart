import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_waiting_state.dart';
export 'android_waiting_state.dart';

/// One application-owned channel; native Android owns eligibility and privacy.
class AndroidWaitingPlatform extends ChangeNotifier {
  AndroidWaitingPlatform() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'waitingStateChanged') _accept(call.arguments);
      if (const {
        'callActionsChanged',
        'transferActionsChanged',
        'transferExecutionChanged'
      }.contains(call.method)) {
        notifyListeners();
      }
    });
  }

  static const channel = MethodChannel('app.mosh.mosh/waiting');
  AndroidWaitingState? _state;
  bool _disposed = false;
  AndroidWaitingState? get state => _state;

  Future<void> refresh() => _read('status');
  Future<void> enable() => _read('enable');
  Future<void> stop() => _read('stop');
  Future<void> requestBatteryExemption() => _read('requestBatteryExemption');

  Future<void> startupFailed(String reason) => _read('startupFailed', {
        'reason': reason,
        'intentRevision': _state?.intentRevision,
      });

  Future<List<AndroidCallAction>> takeCallActions() async {
    final values = await channel.invokeListMethod<Object?>('takeCallActions');
    return (values ?? []).take(16).map(AndroidCallAction.fromMap).toList();
  }

  Future<bool> beginTransfer(String id, String direction, BigInt size,
          {bool deferred = false}) async =>
      await channel.invokeMethod<bool>(
          deferred ? 'beginDeferredTransfer' : 'beginUserTransfer', {
        'id': id,
        'direction': direction,
        'estimatedBytes': size.toInt(),
      }) ??
      false;

  Future<List<AndroidTransferAction>> takeTransferActions() async {
    final values =
        await channel.invokeListMethod<Object?>('takeTransferActions');
    return (values ?? []).take(64).map(AndroidTransferAction.fromMap).toList();
  }

  Future<void> acknowledgeTransferActions(
          List<AndroidTransferAction> actions) =>
      channel.invokeMethod<void>('acknowledgeTransferActions', [
        for (final action in actions)
          {'id': action.id, 'revision': action.revision},
      ]);

  Future<String> publishCallNotification(Map<String, Object?> value) async =>
      await channel.invokeMethod<String>('publishNotification', value) ??
      'failed';

  Future<bool> setMediaTypes(bool microphone, bool camera) async =>
      await channel.invokeMethod<bool>('setMediaTypes', {
        'microphone': microphone,
        'camera': camera,
      }) ??
      false;

  Future<void> setUserWork(Map<String, Object?> facts) =>
      _read('setUserWork', facts);

  Future<void> setNotificationPolicy({
    required bool showNamesWhenLocked,
    required bool showTextWhenLocked,
  }) =>
      _read('setNotificationPolicy', {
        'showNamesWhenLocked': showNamesWhenLocked,
        'showTextWhenLocked': showTextWhenLocked,
      });

  Future<String> publishNotification({
    required String id,
    required int revision,
    required int messageCount,
    String? sender,
    String? text,
  }) async =>
      await channel.invokeMethod<String>('publishNotification', {
        'kind': 'message',
        'id': id,
        'revision': revision,
        'messageCount': messageCount,
        'sender': sender,
        'text': text,
      }) ??
      'failed';

  Future<void> _read(String method, [Map<String, Object?>? arguments]) async {
    _accept(await channel.invokeMethod<Object?>(method, arguments));
  }

  void _accept(Object? value) {
    if (_disposed) return;
    final next = AndroidWaitingState.fromMap(value);
    if (next.revision <= (_state?.revision ?? -1)) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}

class AndroidCallAction {
  const AndroidCallAction(this.capability, this.interactiveAnswer);
  final String capability;
  final bool interactiveAnswer;
  factory AndroidCallAction.fromMap(Object? value) {
    final map = value as Map<Object?, Object?>;
    final capability = map['capability'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(capability)) {
      throw const FormatException('Invalid call action');
    }
    return AndroidCallAction(capability, map['interactiveAnswer'] as bool);
  }
}

class AndroidTransferAction {
  const AndroidTransferAction(this.id, this.action, this.revision);
  final String id, action;
  final int revision;
  factory AndroidTransferAction.fromMap(Object? value) {
    final map = value as Map<Object?, Object?>;
    final id = map['id'] as String;
    final action = map['action'] as String;
    final revision = map['revision'] as int;
    if (!RegExp(r'^transfer-[0-9a-f]{32}$').hasMatch(id) ||
        !const {'cancel', 'resume'}.contains(action) ||
        revision < 1) {
      throw const FormatException('Invalid transfer action');
    }
    return AndroidTransferAction(id, action, revision);
  }
}
