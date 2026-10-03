// A failed snapshot read in a conversation's peer-status drawer is worded
// for people from the error's kind, never with the runtime's raw message.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_peer_status.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';

import '../../support/pump.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

void main() {
  testWidgets('a bridge error shows its kind sentence, not the runtime text',
      (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: ConversationPeerStatus(
          target: const DmTarget('test'),
          onOpenAttachment: (_, view, own) {},
          async: AsyncValue.error(
            const ConversationBridgeError(
              kind: ConversationBridgeErrorKind.unavailable,
              message: 'moss: transport socket closed (os error 104)',
            ),
            StackTrace.empty,
          ),
          onRefresh: () {},
          onClose: () {},
        ),
      ),
    );

    expect(find.textContaining('os error 104'), findsNothing);
    expect(find.textContaining('could not reach the network'), findsOneWidget);
  });
}
