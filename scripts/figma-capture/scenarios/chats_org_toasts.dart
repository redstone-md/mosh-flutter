// Chats area scenes for organisations and the toast stack.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/toasts/toast_card.dart';
import 'package:mosh/src/features/shared/toasts/toast_host.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;

import '../../../test/support/message_builders.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import 'chats_fixtures.dart';
import 'harness.dart';

/// Shows [toasts] through the app's own toaster, oldest first.
Future<void> _toast(WidgetTester tester,
    List<(String Function(AppLocalizations), ToastKind)> toasts) async {
  final host = find.byType(ToastHost);
  final l = AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
  final toaster =
      ProviderScope.containerOf(tester.element(host)).read(toasterProvider);
  for (final (message, kind) in toasts) {
    toaster.show(message(l), kind: kind);
    await tester.pumpAndSettle();
  }
}

final _stack = <(String Function(AppLocalizations), ToastKind)>[
  ((l) => l.chatActionErrorUnavailable, ToastKind.error),
  ((l) => l.messageCopied, ToastKind.info),
  ((l) => l.messageCopied, ToastKind.success),
];

final orgAndToastScenes = <FigmaScene>[
  FigmaScene('org-roster', 'Chats / Organisation / Roster',
      (tester, size) async {
    await mountChats(tester, size,
        gateway: shortGateway(), script: (_, b) => b.seedOrgs([northwind()]));
  },
      note: 'We are an admin: offers, the new group form and the roster. '
          'Jonas Weber left the roster, so his chat shows the revoked badge.'),
  FigmaScene('org-pending', 'Chats / Organisation / Waiting for roster',
      (tester, size) async {
    await mountChats(tester, size,
        gateway: shortGateway(), script: (_, b) => b.seedOrgs([riverside()]));
  }),
  FigmaScene('org-busy', 'Chats / Organisation / Busy', (tester, size) async {
    final bridge = await mountChats(tester, size,
        gateway: shortGateway(),
        script: (_, b) => b
          ..seedOrgs([northwind(offers: false)])
          ..hold(BridgeMethod.leaveOrg));
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
    await tester.tap(find.byTooltip(l.orgLeave));
    await tester.pumpAndSettle();
    expect(bridge.countOf(BridgeMethod.leaveOrg), 1);
  }, note: 'Leaving is in flight, so the section controls are disabled.'),
  FigmaScene('org-add-missing', 'Chats / Organisation / Add missing members',
      (tester, size) async {
    final group = TestSnapshots.group(
        groupId: 'northwind-design',
        label: 'Northwind design',
        deviceFingerprint: selfFp,
        orgPubkey: orgKey,
        memberPeerIds: const [
          'peer-alex-7f3a92',
          'peer-maya-1c08de'
        ],
        messages: [
          TestMessages.group(
              fromDevice: 'Maya Chen',
              fromFingerprint: 'maya',
              body: 'Moodboard is up, have a look when you can.'),
        ]);
    await mountChats(tester, size,
        location: AppRoutes.groupFor(group.groupId),
        gateway: shortGateway(groups: [group]),
        script: (_, b) => b.seedOrgs([northwind(offers: false)]));
  }),

  // Toasts.
  FigmaScene('toast-success', 'Chats / Toast / Success', (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
    await _toast(tester, [_stack.last]);
  }),
  FigmaScene('toast-error', 'Chats / Toast / Error', (tester, size) async {
    await mountChats(tester, size,
        gateway: invitationsGateway(),
        script: (g, _) => g.failAlways(GatewayMethod.dismissDmOffer,
            error: const ConversationBridgeError(
                kind: ConversationBridgeErrorKind.unavailable,
                message: 'dm runtime unavailable: node down')));
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
    await tester.tap(find.byTooltip(l.railOfferDismiss).first);
    await tester.pumpAndSettle();
  }, note: 'Dismissing an invitation failed while offline.'),
  FigmaScene('toast-stack', 'Chats / Toast / Stack', (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
    await _toast(tester, _stack);
  }),
  FigmaScene('toast-stack-open', 'Chats / Toast / Stack on hover',
      (tester, size) async {
    await mountChats(tester, size, unread: chatsUnread);
    await _toast(tester, _stack);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ToastCard).first));
    await tester.pumpAndSettle();
  }, devices: const [FigmaDevice.desktop]),
];
