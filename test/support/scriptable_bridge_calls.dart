part of 'scriptable_bridge.dart';

mixin _BridgeCalls on _ScriptableBridgeState {
  @override
  Future<CallStarted> callStart({required String sessionId}) => runScripted(
      BridgeMethod.callStart,
      {'sessionId': sessionId},
      () => cannedCallStarted(sessionId));

  @override
  Future<void> callAccept({
    required String sessionId,
    required String callId,
  }) =>
      runScripted(BridgeMethod.callAccept,
          {'sessionId': sessionId, 'callId': callId}, () {});

  @override
  Future<void> callDecline({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      runScripted(BridgeMethod.callDecline,
          {'sessionId': sessionId, 'callId': callId, 'reason': reason}, () {});

  @override
  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      runScripted(BridgeMethod.callEnd,
          {'sessionId': sessionId, 'callId': callId, 'reason': reason}, () {});
}
