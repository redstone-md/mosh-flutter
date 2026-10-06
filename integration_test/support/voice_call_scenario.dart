import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

import '../../native_test/support/native_peer.dart';
import 'call_audio_observer.dart';
import 'linked_dm_ui.dart';

class VoiceCallScenario {
  VoiceCallScenario(
      this.tester, this.peer, this.session, this.remoteSession, this.audio)
      : ui = LinkedDmUi(tester, session);
  final WidgetTester tester;
  final NativePeer peer;
  final String session;
  final String remoteSession;
  final CallAudioObserver audio;
  final LinkedDmUi ui;
  final BridgeFacade bridge = BridgeFacade();

  Future<Map<String, dynamic>> remote(String action, [String? callId]) async =>
      (await tester.runAsync(() => peer.ask({
            'action': action,
            'argument': remoteSession,
            if (callId != null) 'call_id': callId,
          })))!;

  Future<String> pendingRemote() async {
    String? id;
    await ui.eventually(() async {
      id = ((await remote('dm_poll'))['pending_call'] as Map?)?['call_id']
          as String?;
      return id != null;
    });
    return id!;
  }

  Future<void> outgoingDeclineAndCancel() async {
    await ui.tap(find.byTooltip('Start voice call'));
    final declined = await pendingRemote();
    await ui.visible(find.text('Calling...'));
    await ui.eventually(() async => audio.rings == 1 && audio.windows == 1);
    await remote('call_decline', declined);
    await ui.eventually(() async =>
        find.text('Calling...').evaluate().isEmpty && audio.ringStops == 1);
    await ui.eventually(() async => audio.windows == 0);
    await ui.tap(find.byTooltip('Start voice call'));
    await pendingRemote();
    await ui.visible(find.byTooltip('Cancel call'));
    await ui.tap(find.byTooltip('Cancel call'));
    await ui.eventually(() async => audio.rings == 2 && audio.ringStops == 2);
    await ui.eventually(
        () async => (await remote('dm_poll'))['pending_call'] == null);
  }

  Future<String> incomingAndMedia() async {
    unawaited(appRouter.push<void>(AppRoutes.settings));
    final started = await remote('call_start');
    final id = started['call_id'] as String;
    await ui.visible(find.byTooltip('Accept call'));
    expect(audio.captures, 0);
    await ui.tap(find.byTooltip('Accept call'));
    await ui.eventually(() async =>
        audio.captures == 1 &&
        audio.players == 1 &&
        find.byTooltip('Mute').evaluate().isNotEmpty &&
        tester
                .widget<IconButton>(find
                    .descendant(
                        of: find.byTooltip('Mute'),
                        matching: find.byType(IconButton))
                    .first)
                .onPressed !=
            null);
    await ui.eventually(
        () async => (await remote('dm_poll'))['active_call'] != null);
    await ui.eventually(() async {
      final probe = await remote('call_probe');
      return (probe['received'] as int) > 0 && audio.playedFrames > 0;
    });
    expect(audio.rings, 3);
    expect(audio.ringStops, 3);
    return id;
  }

  Future<void> navigationAndMessaging() async {
    final other = await tester.runAsync(() => bridge.createInvite(
        request:
            const StartSessionRequest(displayName: 'Other DM', listenPort: 0)));
    final channel = await tester.runAsync(() => bridge.joinChannel(
        request: const JoinChannelRequest(
            name: 'voice-navigation', displayName: 'Local', listenPort: 0)));
    final group = await tester.runAsync(() => bridge.createGroup(
        request: const CreateGroupRequest(
            displayName: 'Local', label: 'Call navigation', listenPort: 0)));
    for (final route in [
      AppRoutes.dmFor(other!.sessionId),
      AppRoutes.groupFor(group!.groupId),
      AppRoutes.channelFor(channel!.name),
      AppRoutes.settings
    ]) {
      if (route == AppRoutes.settings) {
        unawaited(appRouter.push<void>(route));
      } else {
        appRouter.go(route);
      }
      await tester.pump(const Duration(milliseconds: 300));
      await ui.visible(find.byTooltip('Mute'));
      await remote('call_probe');
      expect(audio.captures, 1);
      expect(audio.players, 1);
      expect(audio.captureStops, 0);
      expect(audio.playerStops, 0);
    }
    await ui.tap(find.byTooltip('Mute'));
    await ui.visible(find.byTooltip('Unmute'));
    await ui.tap(find.byTooltip('Unmute'));
    appRouter.go(AppRoutes.dmFor(session));
    await tester.pump(const Duration(milliseconds: 300));
    final input = find
        .descendant(
            of: find.byType(ConversationComposer),
            matching: find.byType(TextField))
        .last;
    await ui.visible(input);
    await tester.enterText(input, 'Text during the call');
    await ui.tap(find.byKey(kComposerSendButtonKey));
    await ui.eventually(() async =>
        ((await remote('dm_poll'))['messages'] as List)
            .any((row) => (row as Map)['body'] == 'Text during the call'));
  }

  Future<void> remoteEndAndRepeat(String callId) async {
    await remote('call_end', callId);
    await ui.eventually(() async =>
        find.byTooltip('Mute').evaluate().isEmpty &&
        audio.captureStops == 1 &&
        audio.playerStops == 1);
    await ui.eventually(() async => audio.windows == 0);
    await ui.tap(find.byTooltip('Start voice call'));
    final repeated = await pendingRemote();
    await remote('call_accept', repeated);
    await ui.eventually(() async => audio.captures == 2 && audio.players == 2);
    await ui.visible(find.byTooltip('Hang up'));
    await ui.tap(find.byTooltip('Hang up'));
    await ui.eventually(
        () async => audio.captureStops == 2 && audio.playerStops == 2);
    await ui.eventually(
        () async => (await remote('dm_poll'))['active_call'] == null);
    expect(audio.rings, audio.ringStops);
  }
}
