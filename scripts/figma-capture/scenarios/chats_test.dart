// Figma capture of the Chats area: the desktop shell and its welcome pane,
// the title bar, the chat list in each state, organisations and toasts.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;

import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import 'chats_fixtures.dart';
import 'chats_org_toasts.dart';
import 'harness.dart';

const _offline = ConversationBridgeError(
    kind: ConversationBridgeErrorKind.unavailable,
    message: 'dm runtime unavailable: node down');

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SessionsScreen).first))!;

/// The list with [chip] selected.
FigmaScene _filter(
        String id, String title, String Function(AppLocalizations) chip) =>
    FigmaScene(id, title, (tester, size) async {
      await mountChats(tester, size, unread: chatsUnread);
      await tester
          .tap(inRail(find.widgetWithText(ChoiceChip, chip(_l(tester)))));
      await tester.pumpAndSettle();
    });

/// Opens Leo Park's row menu with a secondary click. A long press on a
/// phone row lands on its tooltips instead, so it cannot open the menu here.
Future<void> _openRowMenu(WidgetTester tester) async {
  await tester.tap(inRail(find.text('Leo Park')),
      buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

/// A desktop chat open on [location], showing the title bar's status.
FigmaScene _status(String id, String title, String location,
        {void Function(ScriptableGateway, ScriptableBridge)? script}) =>
    FigmaScene(id, title, (tester, size) async {
      await mountChats(tester, size,
          location: location, unread: chatsUnread, script: script);
    }, devices: const [FigmaDevice.desktop]);

final _scenes = <FigmaScene>[
  // Shell and welcome pane.
  FigmaScene('welcome', 'Chats / Shell / Welcome', (tester, size) async {
    await mountChats(tester, size,
        location: AppRoutes.chat, unread: chatsUnread);
  }),

  // Title bar.
  _status('titlebar-connected', 'Chats / Title bar / Connected chat',
      AppRoutes.dmFor('maya')),
  _status('titlebar-waiting', 'Chats / Title bar / Waiting for contact',
      AppRoutes.dmFor('sofia')),
  _status('titlebar-channel', 'Chats / Title bar / Public channel',
      AppRoutes.channelFor('photography')),
  _status('titlebar-unknown', 'Chats / Title bar / Status unknown',
      AppRoutes.dmFor('maya'),
      script: (g, _) => g.failAlways(GatewayMethod.poll, error: _offline)),
  FigmaScene('titlebar-status-drawer', 'Chats / Title bar / Connection status',
      (tester, size) async {
    await mountChats(tester, size,
        location: AppRoutes.dmFor('maya'), unread: chatsUnread);
    await tester.tap(find.byTooltip('Connection status').first);
    await tester.pumpAndSettle();
  }, devices: const [FigmaDevice.desktop]),
  FigmaScene('window-frame', 'Chats / Title bar / Windows window frame',
      (tester, size) async {
    await mountChats(tester, size,
        location: AppRoutes.dmFor('maya'),
        unread: chatsUnread,
        window: await windowsFrame());
  }, devices: const [FigmaDevice.desktop]),
  FigmaScene('window-frame-narrow', 'Chats / Title bar / Narrow window',
      (tester, size) async {
    await mountChats(tester, size,
        location: AppRoutes.dmFor('maya'), window: await windowsFrame());
  },
      devices: const [FigmaDevice.mobile],
      note: 'A desktop window 390px wide: the bar keeps the list button and '
          'shrinks the status to its dot.'),

  // Chat list.
  FigmaScene('list-empty', 'Chats / List / Empty', (tester, size) async {
    await mountChats(tester, size, gateway: ScriptableGateway());
  }),
  FigmaScene('list-loading', 'Chats / List / Loading', (tester, size) async {
    await mountChats(tester, size,
        gateway: ScriptableGateway(),
        settle: false,
        script: (_, b) => b.hold(BridgeMethod.listSessions));
  }),
  FigmaScene('list-error', 'Chats / List / Could not load',
      (tester, size) async {
    await mountChats(tester, size,
        gateway: ScriptableGateway(),
        script: (_, b) =>
            b.failAlways(BridgeMethod.listSessions, error: _offline));
  }),
  FigmaScene('list', 'Chats / List / Chats', (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
  }),
  _filter('filter-personal', 'Chats / List / Filter: Personal',
      (l) => l.chatListPersonal),
  _filter('filter-groups', 'Chats / List / Filter: Groups',
      (l) => l.chatListGroups),
  _filter('filter-channels', 'Chats / List / Filter: Channels',
      (l) => l.chatListChannels),
  FigmaScene('search', 'Chats / List / Search results', (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
    await searchRail(tester, 'leo');
  }),
  FigmaScene('search-empty', 'Chats / List / Search without results',
      (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
    await searchRail(tester, 'harbor');
  }),
  FigmaScene('invitations', 'Chats / List / Invitations', (tester, size) async {
    await mountChats(tester, size, gateway: invitationsGateway());
  }),
  FigmaScene('row-menu', 'Chats / List / Row menu', (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
    await _openRowMenu(tester);
  }),
  FigmaScene('rename', 'Chats / List / Rename chat', (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
    await _openRowMenu(tester);
    await tester.tap(find.text(_l(tester).chatRename));
    await tester.pumpAndSettle();
  }),
  FigmaScene('compact', 'Chats / List / Collapsed', (tester, size) async {
    await mountChats(tester, size,
        location: AppRoutes.dmFor('maya'),
        unread: chatsUnread,
        gateway: invitationsGateway(),
        collapsed: true,
        script: (_, b) => b.seedOrgs([northwind()]));
  }, devices: const [FigmaDevice.desktop]),
  FigmaScene('compact-error', 'Chats / List / Collapsed, could not load',
      (tester, size) async {
    await mountChats(tester, size,
        location: AppRoutes.chat,
        collapsed: true,
        script: (_, b) =>
            b.failAlways(BridgeMethod.listSessions, error: _offline));
  }, devices: const [FigmaDevice.desktop]),

  ...orgAndToastScenes,
];

void main() => figmaScenes('chats', _scenes);
