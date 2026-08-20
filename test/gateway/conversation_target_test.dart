// Target identity: two targets are the same conversation only when they are
// the same kind with the same id. The screens rely on this to decide whether
// a recorded failed send belongs to the conversation on screen, so a channel
// and a group that happen to share an id must not compare equal.
//
// Replaces the `sameChatTarget` cases that lived in chat_actions_test.dart
// before the target moved into the Gateway seam (ADR 0017).
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

void main() {
  group('ConversationTarget identity', () {
    test('same kind and same id are equal', () {
      expect(const DmTarget('s1'), const DmTarget('s1'));
      expect(const ChannelTarget('general'), const ChannelTarget('general'));
      expect(const GroupTarget('g1'), const GroupTarget('g1'));
    });

    test('same kind and different id are not equal', () {
      expect(const DmTarget('s1'), isNot(const DmTarget('s2')));
      expect(const ChannelTarget('general'), isNot(const ChannelTarget('ops')));
      expect(const GroupTarget('g1'), isNot(const GroupTarget('g2')));
    });

    test('different kinds sharing an id are not equal', () {
      expect(const DmTarget('x'), isNot(const ChannelTarget('x')));
      expect(const ChannelTarget('x'), isNot(const GroupTarget('x')));
      expect(const GroupTarget('x'), isNot(const DmTarget('x')));
    });

    test('equal targets hash the same, so a set keeps one of them', () {
      expect(const DmTarget('s1').hashCode, const DmTarget('s1').hashCode);
      final seen = <AnyConversationTarget>{}
        ..add(const DmTarget('s1'))
        ..add(const DmTarget('s1'))
        ..add(const ChannelTarget('s1'));
      expect(seen, hasLength(2));
    });

    test('toString names the kind and the id', () {
      expect(const ChannelTarget('general').toString(),
          contains('ChannelTarget'));
      expect(const ChannelTarget('general').toString(), contains('general'));
    });
  });

  group('DmOfferHost', () {
    // A DM holds no offer list, so `Gateway.dismissDmOffer` takes the narrower
    // type. This is a compile-time guarantee; the test pins the hierarchy so a
    // later change cannot quietly widen it.
    test('a channel and a group are offer hosts', () {
      expect(const ChannelTarget('general'), isA<DmOfferHost<Object?>>());
      expect(const GroupTarget('g1'), isA<DmOfferHost<Object?>>());
    });

    test('a DM is not an offer host', () {
      expect(const DmTarget('s1'), isNot(isA<DmOfferHost<Object?>>()));
    });
  });
}
