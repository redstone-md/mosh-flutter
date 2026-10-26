import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mosh/src/platform/android_waiting_platform.dart';
import 'package:mosh/src/rust/api/background/call_actions.dart';
import 'package:mosh/src/rust/persistence/background_calls/types.dart';
import 'package:mosh/src/rust/persistence/background_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'background_commands.dart';
import '../voice_call/call_selection.dart';

/// Current native calls and user actions share the existing call presentation.
/// Android intents contain only capabilities; no notification action unlocks chats.
class AndroidBackgroundCalls extends ChangeNotifier {
  AndroidBackgroundCalls(this.commands, this.platform);
  final BackgroundCommands commands;
  final AndroidWaitingPlatform platform;
  final _actions = <AndroidCallAction>[];
  final _sessions = <String, SessionSnapshot>{};
  SessionSnapshot? snapshot;
  Future<void> Function(String sessionId, String callId)? onAnswer;
  bool _disposed = false;

  Future<bool> publish(BackgroundNotification entry) async {
    final call = entry.call!;
    final current = await commands.callSnapshot(entry.target.id);
    _updateSnapshot(current);
    if (call.phase != BackgroundCallPhase.ended && !_matches(current, call)) {
      // A cancellation or linked-device answer won during bridge delivery.
      return false;
    }
    return await platform.publishCallNotification({
          'kind': 'call',
          'id': entry.id,
          'revision': entry.revision.toInt(),
          'phase': call.phase.name,
          'expiresAtMs': call.expiresAtMs.toInt(),
          'sender': entry.sender,
          'answerCapability': call.answerCapability,
          'declineCapability': call.declineCapability,
          'hangupCapability': call.hangupCapability,
        }) ==
        'posted';
  }

  Future<void> flushActions() async {
    for (final action in await platform.takeCallActions()) {
      if (_actions.length < 16) _actions.add(action);
    }
    for (final action in List.of(_actions)) {
      if (action.interactiveAnswer &&
          (platform.state?.callInteractive != true || onAnswer == null)) {
        continue;
      }
      final result = await commands.callAction(action.capability);
      if (result.outcome == BackgroundCallActionOutcome.unavailable) continue;
      _actions.remove(action);
      if (result.outcome != BackgroundCallActionOutcome.applied) continue;
      final target = result.target, id = result.callId;
      if (target == null || id == null) continue;
      final current = await commands.callSnapshot(target.id);
      _updateSnapshot(current,
          selected: result.action == BackgroundCallAction.answer);
      if (result.action == BackgroundCallAction.answer &&
          action.interactiveAnswer &&
          platform.state?.callInteractive == true) {
        final answer = onAnswer;
        if (answer != null) {
          unawaited(Future<void>(() => answer(target.id, id)));
        }
      }
    }
  }

  void _updateSnapshot(SessionSnapshot current, {bool selected = false}) {
    if (_hasCall(current)) {
      _sessions[current.sessionId] = current;
    } else {
      _sessions.remove(current.sessionId);
    }
    snapshot = selectCallSession(_sessions.values,
        selectedId: selected ? current.sessionId : snapshot?.sessionId);
    if (!_disposed) notifyListeners();
  }

  bool _hasCall(SessionSnapshot value) =>
      value.pendingCall != null ||
      value.outgoingCall != null ||
      value.activeCall != null;

  bool _matches(SessionSnapshot value, BackgroundCallNotification call) =>
      switch (call.phase) {
        BackgroundCallPhase.incoming =>
          value.pendingCall?.callId == call.callId &&
              value.pendingCall?.answerPending != true,
        BackgroundCallPhase.accepting =>
          value.pendingCall?.callId == call.callId &&
              value.pendingCall?.answerPending == true,
        BackgroundCallPhase.outgoing =>
          value.outgoingCall?.callId == call.callId,
        BackgroundCallPhase.active => value.activeCall?.callId == call.callId,
        BackgroundCallPhase.ended => true,
      };

  @override
  void dispose() {
    _disposed = true;
    _actions.clear();
    _sessions.clear();
    super.dispose();
  }
}
