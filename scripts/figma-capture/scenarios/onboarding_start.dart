// Start menu, its four steps, the /join paste screen and the startup lock
// screen, for the onboarding area.
import 'dart:async';

import 'package:flutter/material.dart' hide LockState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/lock/mosh_lock_app.dart';
import 'package:mosh/src/features/lock/mosh_lock_screen.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';

import '../../../test/features/routing/shell_harness.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import 'harness.dart';

const _dmUri = 'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0';
const _groupUri = 'mosh://group?mesh=k2p8&group=weekend-hikers'
    '&name=Weekend%20hikers#fp=91A4D2C877B091A4D2C877B091A4D2C8';
const _orgUri = 'mosh://org?mesh=7x9v&name=Riverside%20Studio#org='
    '91a4d2c877b091a4d2c877b091a4d2c877b091a4d2c877b091a4d2c877b091a4';
const _unavailable = ConversationBridgeError(
    kind: ConversationBridgeErrorKind.unavailable, message: 'node down');

InviteCreated _invite(String session, String fp) => InviteCreated(
    inviteUri: 'mosh://invite?mesh=7x9v&session=$session#fp=$fp',
    sessionId: session,
    meshId: '7x9v',
    fingerprint: fp,
    listenAddress: '192.168.1.24:8765');

/// Accepts clipboard writes so copy actions complete without a platform.
void _stubClipboard() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      SystemChannels.platform, (_) async => null);
  addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

/// The real shell at [location] over [bridge] (an empty install by default).
/// Storage is healthy unless a [warning] is given.
Future<void> _shell(WidgetTester tester, Size size,
    {String location = AppRoutes.chat,
    ScriptableBridge? bridge,
    PersistenceWarning? warning}) async {
  final gateway = ScriptableGateway();
  final scripted =
      bridge ?? ScriptableBridge(conversations: gateway.conversations);
  _stubClipboard();
  await pumpShellApp(tester,
      gateway: gateway,
      bridge: scripted,
      physical: size,
      location: location,
      overrides: [
        ...figmaLocale,
        persistenceWarningProvider.overrideWith((ref) async => warning),
      ]);
}

/// Opens the start menu card titled [card] and waits for the slide to end.
Future<void> _step(WidgetTester tester, Size size, String card,
    {ScriptableBridge? bridge}) async {
  await _shell(tester, size, bridge: bridge);
  await _tap(tester, find.text(card));
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pumpAndSettle();
}

ScriptableBridge _groupBridge() => ScriptableBridge()
  ..respondNext(
      BridgeMethod.createGroup,
      Future.value(const GroupCreated(
          groupId: 'weekend-hikers',
          meshId: 'k2p8',
          inviteUri: _groupUri,
          fingerprint: '91A4D2C877B091A4D2C877B091A4D2C8',
          label: 'Weekend hikers')));

Future<void> _paste(WidgetTester tester, Size size, String text,
    {ScriptableBridge? bridge}) async {
  await _shell(tester, size, location: AppRoutes.join, bridge: bridge);
  await _type(tester, text);
}

final List<FigmaScene> startScenes = [
  FigmaScene('start-menu', 'Onboarding / Start menu / Default',
      (tester, size) async {
    await _shell(tester, size);
  }),
  FigmaScene(
      'start-menu-storage-warning', 'Onboarding / Start menu / Storage warning',
      (tester, size) async {
    await _shell(tester, size,
        warning: const PersistenceWarning(
            kind: PersistenceWarningKind.unavailable,
            reason: 'the system keychain is locked'));
  }),
  FigmaScene('chat-create', 'Onboarding / Private chat / Create invite',
      (tester, size) async {
    await _step(tester, size, 'Start a private chat');
  }),
  FigmaScene('chat-saved', 'Onboarding / Private chat / Saved invitations',
      (tester, size) async {
    final bridge = ScriptableBridge()
      ..seedPendingInvites(
          [_invite('drift-41', '91A4D2C8'), _invite('harbor-07', '3C5E77B0')]);
    await _step(tester, size, 'Start a private chat', bridge: bridge);
  }),
  FigmaScene('chat-copied', 'Onboarding / Private chat / Link copied',
      (tester, size) async {
    final bridge = ScriptableBridge()
      ..seedPendingInvites([_invite('drift-41', '91A4D2C8')]);
    await _step(tester, size, 'Start a private chat', bridge: bridge);
    await tester.ensureVisible(find.text('Copy link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }),
  FigmaScene('chat-error', 'Onboarding / Private chat / Create failed',
      (tester, size) async {
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.createPendingInvite, error: _unavailable);
    await _step(tester, size, 'Start a private chat', bridge: bridge);
    await _tap(tester, find.text('Create invite link'));
  }),
  FigmaScene('group-create', 'Onboarding / Group / Name', (tester, size) async {
    await _step(tester, size, 'Create a group');
    await _type(tester, 'Weekend hikers');
  }),
  FigmaScene('group-created', 'Onboarding / Group / Invite ready',
      (tester, size) async {
    await _step(tester, size, 'Create a group', bridge: _groupBridge());
    await _type(tester, 'Weekend hikers');
    await _tap(tester, find.text('Create group'));
  }),
  FigmaScene('group-error', 'Onboarding / Group / Create failed',
      (tester, size) async {
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.createGroup, error: _unavailable);
    await _step(tester, size, 'Create a group', bridge: bridge);
    await _type(tester, 'Weekend hikers');
    await _tap(tester, find.text('Create group'));
  }),
  FigmaScene('join-step', 'Onboarding / Join with a link / Inline step',
      (tester, size) async {
    await _step(tester, size, 'Join with a link');
  }),
  FigmaScene('channel-join', 'Onboarding / Public channel / Empty',
      (tester, size) async {
    await _step(tester, size, 'Join a public channel');
  }),
  FigmaScene('channel-filled', 'Onboarding / Public channel / Name picked',
      (tester, size) async {
    await _step(tester, size, 'Join a public channel');
    await _tap(tester, find.widgetWithText(ActionChip, 'community'));
  }),
  FigmaScene('channel-error', 'Onboarding / Public channel / Join failed',
      (tester, size) async {
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.joinChannel, error: _unavailable);
    await _step(tester, size, 'Join a public channel', bridge: bridge);
    await _type(tester, 'community');
    await _tap(tester, find.text('Join channel'));
  }),
];

final List<FigmaScene> joinScenes = [
  FigmaScene('paste-empty', 'Onboarding / Invite paste / Empty',
      (tester, size) async {
    await _shell(tester, size, location: AppRoutes.join);
  }),
  FigmaScene('paste-dm', 'Onboarding / Invite paste / Private chat link',
      (tester, size) async {
    await _paste(tester, size, _dmUri);
  }),
  FigmaScene('paste-group', 'Onboarding / Invite paste / Group link',
      (tester, size) async {
    await _paste(tester, size, _groupUri);
  }),
  FigmaScene('paste-org', 'Onboarding / Invite paste / Organization link',
      (tester, size) async {
    await _paste(tester, size, _orgUri);
  }),
  FigmaScene('paste-invalid', 'Onboarding / Invite paste / Invalid link',
      (tester, size) async {
    await _paste(tester, size, 'https://example.com/invite/drift');
  }),
  FigmaScene('paste-connecting', 'Onboarding / Invite paste / Connecting',
      (tester, size) async {
    final bridge = ScriptableBridge()..hold(BridgeMethod.acceptInvite);
    await _paste(tester, size, _dmUri, bridge: bridge);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }),
  FigmaScene('paste-error', 'Onboarding / Invite paste / Join failed',
      (tester, size) async {
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.acceptInvite, error: _unavailable);
    await _paste(tester, size, _dmUri, bridge: bridge);
    await _tap(tester, find.byType(FilledButton));
  }),
];

/// The startup lock screen in [state], under the app theme.
Future<void> _lock(WidgetTester tester, LockState state,
    {bool authenticating = false}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: figmaLocale,
      child: MoshLockApp(
          screen: MoshLockScreen(
              retry: () => Completer<void>().future,
              swapTo: (_) {},
              nextApp: const SizedBox(),
              initialState: state,
              automaticallyAuthenticate: authenticating))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const _phone = [FigmaDevice.mobile];
final List<FigmaScene> lockScenes = [
  FigmaScene('lock-canceled', 'Onboarding / Lock / Canceled',
      (tester, size) => _lock(tester, LockState.canceled),
      devices: _phone),
  FigmaScene('lock-unlocking', 'Onboarding / Lock / Unlocking',
      (tester, size) => _lock(tester, LockState.canceled, authenticating: true),
      devices: _phone),
  FigmaScene('lock-failed', 'Onboarding / Lock / Failed',
      (tester, size) => _lock(tester, LockState.failed),
      devices: _phone),
  FigmaScene('lock-insecure', 'Onboarding / Lock / No device credential',
      (tester, size) => _lock(tester, LockState.insecureDevice),
      devices: _phone),
];
