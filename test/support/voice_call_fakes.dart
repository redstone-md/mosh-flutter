import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';

class RecordingRingtone implements RingtonePlayer {
  int starts = 0;
  int stops = 0;
  final kinds = <RingtoneKind>[];
  @override
  RingtoneHandle start(RingtoneKind kind) {
    starts++;
    kinds.add(kind);
    return _Ring(() => stops++);
  }
}

class _Ring implements RingtoneHandle {
  _Ring(this.onStop);
  final void Function() onStop;
  @override
  void stop() => onStop();
}

class RecordingCallWindow implements CallWindowHandle {
  final views = <CallViewState>[];
  final presentation = ValueNotifier<CallViewState?>(null);
  Future<void>? presentWait;
  Object? presentFailure;
  int shows = 0;
  int closes = 0;
  @override
  Future<void> present(CallViewState state) async {
    await presentWait;
    final failure = presentFailure;
    if (failure != null) throw failure;
    views.add(state);
    presentation.value = state;
  }

  @override
  Future<void> show() async => shows++;
  @override
  Future<bool> isFocused() async => false;
  @override
  Future<void> close() async => closes++;
}
