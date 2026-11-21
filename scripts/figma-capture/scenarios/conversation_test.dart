// Figma scenes for the conversation area: DM, group and channel screens,
// their banners, menus, dialogs, panels and the media viewer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/features/conversation/conversation_text_sends.dart';
import 'package:mosh/src/features/shared/media_player.dart';
import 'package:mosh/src/features/shared/media_viewer.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/features/conversation/conversation_controller.dart';
import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/rust/conversation/read_marks.dart';
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/conversation/recovery.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/state/org_providers.dart';

import '../../../test/support/message_selection.dart';
import '../../../test/support/gateway_snapshots.dart' show fakeSession;
import '../../../test/support/scriptable_gateway.dart';
import 'conversation_fixtures.dart';
import 'harness.dart';

part 'conversation_dm_scenes.dart';
part 'conversation_room_scenes.dart';

const _desktopOnly = [FigmaDevice.desktop];
const _mobileOnly = [FigmaDevice.mobile];

String get _group => AppRoutes.groupFor(groupId);
String get _channel => AppRoutes.channelFor(channelName);

Finder get _composerField => find.descendant(
    of: find.byType(ConversationComposer), matching: find.byType(TextField));

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip).last);
  await _settle(tester);
}

Future<void> _menu(WidgetTester tester, [String? item]) async {
  await _tapTooltip(tester, l10n.chatMoreActions);
  if (item == null) return;
  await tester.tap(find.text(item).last);
  await _settle(tester);
}

/// Closes the docked details panel so the chat takes the full width.
Future<void> _closeDocked(WidgetTester tester, Size size) async {
  if (isDesktop(size)) await _tapTooltip(tester, l10n.dialogClose);
}

Future<void> _dm(WidgetTester tester, Size size, SessionSnapshot dm,
        {List<Override> overrides = const []}) =>
    openShell(tester, size,
        gateway: seededGateway(dm: dm), overrides: overrides);

Future<void> _attachments(WidgetTester tester, Size size,
    {bool onDisk = false}) {
  final data = dmAttachments(onDisk: onDisk);
  return _dm(tester, size,
      dmSession(messages: data.messages, attachments: data.transfers));
}

Future<void> _search(WidgetTester tester, String query) async {
  await _tapTooltip(tester, l10n.chatSearchPlaceholder);
  await tester.enterText(
      find.widgetWithText(TextField, l10n.chatSearchPlaceholder), query);
  await _settle(tester);
}

/// Answers the composer's one native call, the stored microphone choice.
class _MicApi extends Fake implements RustLibApi {
  @override
  String? crateApiAudioDevicesAudioInputDeviceId() => null;
}

bool _micMocked = false;

/// Opens the DM with a fake microphone and starts recording.
Future<void> _record(WidgetTester tester, Size size) async {
  if (!_micMocked) {
    RustLib.initMock(api: _MicApi());
    _micMocked = true;
  }
  // The composer creates its recorder on mount, so the fake goes first.
  fakeRecorder(tester);
  await _dm(tester, size, dmSession());
  await tester.tap(find.byTooltip(l10n.voiceRecordLabel));
  // Capture runs periodic timers: pump frames instead of settling.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A player that has loaded a 3:24 clip and stands at 1:12.
class _ClipPlayback extends PlatformPlayer {
  _ClipPlayback() : super(configuration: const PlayerConfiguration());

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    const duration = Duration(minutes: 3, seconds: 24);
    const position = Duration(minutes: 1, seconds: 12);
    state = state.copyWith(duration: duration, position: position);
    durationController.add(duration);
    positionController.add(position);
  }
}

/// Opens the DM and shows [descriptor] in the media viewer, the way the
/// screen does, with [createPlayer] standing in for the native player.
Future<void> _viewer(WidgetTester tester, Size size,
    AttachmentDescriptor descriptor, MediaPlayerFactory createPlayer) async {
  await _dm(tester, size, dmSession());
  unawaited(showDialog<void>(
    context: tester.element(find.byType(DmScreen)),
    barrierDismissible: true,
    barrierLabel: l10n.closeViewer,
    builder: (context) => MediaViewer(
      descriptor: descriptor,
      src: 'file:///tmp/${descriptor.fileName}',
      onClose: () => Navigator.of(context).pop(),
      createPlayer: createPlayer,
    ),
  ));
  await _settle(tester);
}

void main() => figmaScenes('conversation', [..._dmScenes, ..._roomScenes]);
