// Target identity: two targets are the same conversation only when they are
// the same kind with the same id. The screens rely on this to decide whether
// a recorded failed send belongs to the conversation on screen, so a channel
// and a group that happen to share an id must not compare equal.
//
// Replaces the `sameChatTarget` cases that lived in chat_actions_test.dart
// before the target moved into the Gateway seam (ADR 0017).
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';

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
      expect(
          const ChannelTarget('general').toString(), contains('ChannelTarget'));
      expect(const ChannelTarget('general').toString(), contains('general'));
    });
  });

  // Pin that a target builds its key through a ConversationRef.
  group('key', () {
    test('a target builds its key through a ConversationRef', () {
      expect(const DmTarget('s1').key, const DmTarget('s1').ref.key);
      expect(
          const DmTarget('s1').ref,
          const ConversationRef(
            kind: ConversationKind.dm,
            id: 's1',
          ));
    });

    const cases = <(AnyConversationTarget, String, ConversationKind)>[
      (DmTarget('s1'), 'dm:s1', ConversationKind.dm),
      (ChannelTarget('general'), 'channel:general', ConversationKind.channel),
      (GroupTarget('g1'), 'group:g1', ConversationKind.group),
    ];

    for (final (target, expected, kind) in cases) {
      test('${target.kind.name} builds and parses back', () {
        expect(target.key, expected);
        final parsed = ActiveConversation.parse(target.key);
        expect(parsed?.kind, kind);
        expect(parsed?.arg, target.id);
      });
    }

    test('an id with a colon in it survives the round trip', () {
      const target = ChannelTarget('a:b');
      expect(ActiveConversation.parse(target.key)?.arg, 'a:b');
    });
  });

  // ConversationRef owns the `kind:id` grammar. It is the type tickets 07-09
  // migrate the state layer onto, so it carries its own identity and parsing
  // contract rather than borrowing the target's.
  group('ConversationRef', () {
    group('identity', () {
      test('same kind and same id are equal and hash the same', () {
        const a = ConversationRef(kind: ConversationKind.dm, id: 's1');
        const b = ConversationRef(kind: ConversationKind.dm, id: 's1');
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('the same id under another kind is a different conversation', () {
        const dm = ConversationRef(kind: ConversationKind.dm, id: 'x');
        const group = ConversationRef(kind: ConversationKind.group, id: 'x');
        expect(dm, isNot(group));
      });

      test('a set keeps one ref per conversation', () {
        final seen = <ConversationRef>{}
          ..add(const ConversationRef(kind: ConversationKind.group, id: 'g1'))
          ..add(const ConversationRef(kind: ConversationKind.group, id: 'g1'))
          ..add(
            const ConversationRef(kind: ConversationKind.channel, id: 'g1'),
          );
        expect(seen, hasLength(2));
      });

      test('toString names the kind and the id', () {
        expect(
          const ConversationRef(kind: ConversationKind.channel, id: 'general')
              .toString(),
          'ConversationRef(channel:general)',
        );
      });
    });

    group('key round trip', () {
      const cases = <(ConversationRef, String)>[
        (ConversationRef(kind: ConversationKind.dm, id: 's1'), 'dm:s1'),
        (
          ConversationRef(kind: ConversationKind.channel, id: 'general'),
          'channel:general'
        ),
        (ConversationRef(kind: ConversationKind.group, id: 'g1'), 'group:g1'),
      ];

      for (final (ref, expected) in cases) {
        test('${ref.kind.name} renders and parses back', () {
          expect(ref.key, expected);
          expect(ConversationRef.tryParse(ref.key), ref);
        });
      }

      test('every kind renders and parses back', () {
        for (final kind in ConversationKind.values) {
          final ref = ConversationRef(kind: kind, id: 'x');
          expect(ConversationRef.tryParse(ref.key), ref);
        }
      });

      test('an id with colons in it survives the round trip', () {
        const ref =
            ConversationRef(kind: ConversationKind.channel, id: 'a:b:c');
        expect(ref.key, 'channel:a:b:c');
        expect(ConversationRef.tryParse(ref.key)?.id, 'a:b:c');
      });
    });

    group('malformed keys parse to null', () {
      const malformed = <(String, String)>[
        ('', 'no kind and no id'),
        (':', 'separator only'),
        (':s1', 'kind missing'),
        ('dm', 'separator missing'),
        ('dm:', 'id empty'),
        ('unknown:s1', 'kind unknown'),
        ('DM:s1', 'kind is case sensitive'),
      ];

      for (final (key, why) in malformed) {
        test('$why (`$key`)', () {
          expect(ConversationRef.tryParse(key), isNull);
        });
      }

      test('a null key is null', () {
        expect(ConversationRef.tryParse(null), isNull);
      });

      // The provider holds `String?`, so this is the shape the state layer
      // actually hands over.
      test('the active-conversation parser agrees on malformed keys', () {
        for (final entry in malformed) {
          expect(ActiveConversation.parse(entry.$1), isNull, reason: entry.$2);
        }
        expect(ActiveConversation.parse(null), isNull);
      });
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
