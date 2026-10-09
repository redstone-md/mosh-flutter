import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_ringing.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../../support/pump.dart';
import '../../support/voice_call_fakes.dart';

const _pending = IncomingCallDialog(
    pending:
        PendingCall(callId: 'call', fromDevice: 'Alice', answerPending: true),
    peerName: 'Alice');

void main() {
  testWidgets('a conflict keeps call controls usable at a narrow desktop width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final actions = <CallViewAction>[];
    const call = CallViewState(
        sessionId: 'dm',
        callId: 'active',
        peer: 'A contact with a long name',
        phase: CallViewPhase.active,
        audioReady: true,
        occupancyConflict: true);
    await pumpScreen(
        tester,
        Theme(
            data: buildMoshTheme(),
            child: Scaffold(
                body: CallView(
                    compact: true, call: call, onAction: actions.add))));
    expect(
        find.text(
            'Calls are active on different devices. New calls are unavailable until they end.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Hang up'));
    expect(actions, [CallViewAction.mute, CallViewAction.end]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('pending confirmation stops ringing and retains cancel',
      (tester) async {
    final player = RecordingRingtone();
    final timedOut = <String>[];
    final ringing = CallRinging(player, timedOut.add);
    ringing.update(_pending, busy: false);
    final actions = <CallViewAction>[];
    final view = CallViewState.fromDialog('dm', _pending,
        fallback: 'Contact',
        muted: false,
        audioReady: false,
        busy: false,
        language: 'en')!;
    await pumpScreen(
        tester, Scaffold(body: CallView(call: view, onAction: actions.add)));
    expect(find.text('Waiting for confirmation…'), findsOneWidget);
    expect(find.byTooltip('Accept call'), findsNothing);
    await tester.tap(find.byTooltip('Cancel call'));
    expect(actions, [CallViewAction.end]);
    await tester.pump(const Duration(seconds: 31));
    expect(player.starts, 0);
    expect(timedOut, isEmpty);
    ringing.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
