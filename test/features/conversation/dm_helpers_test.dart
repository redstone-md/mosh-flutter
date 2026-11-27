// Unit tests for [avatarInitials]:
//   name.split(/[\s_-]+/).map(p => p[0]).filter(Boolean).join("").slice(0,2).toUpperCase() || "?"
// Each case below pins the expected behavior so a future change surfaces
// as a test failure. Pure function -- no widget harness.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/message_tone.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import '../../support/pump.dart';

void main() {
  group('avatarInitials', () {
    // --- Behavior cases ---
    test('compound dash name -> two initials', () {
      expect(avatarInitials('juno-phone'), 'JP');
    });

    test('two whitespace-separated words -> two initials', () {
      expect(avatarInitials('alice bob'), 'AB');
    });

    test('underscore separator -> two initials', () {
      expect(avatarInitials('juno_phone'), 'JP');
    });

    test('single word -> single initial', () {
      expect(avatarInitials('x'), 'X');
    });

    test('empty string -> "?" fallback', () {
      expect(avatarInitials(''), '?');
    });

    test('whitespace-only string -> "?" fallback', () {
      expect(avatarInitials('   '), '?');
    });

    test('leading/trailing separators produce empty parts, dropped -> AB', () {
      // "-a_b" splits to ["", "a", "b"]; the empty is dropped, leaving "ab".
      expect(avatarInitials('-a_b'), 'AB');
    });

    // --- Edge cases ---
    test('an emoji initial is a whole character, never half of one', () {
      expect(avatarInitials('👨‍👩‍👧‍👦 family'), '👨‍👩‍👧‍👦F');
      expect(avatarInitials('😀😀'), '😀');
    });

    test('three words capped to 2 initials', () {
      expect(avatarInitials('alpha beta gamma'), 'AB');
    });

    test('mixed case collapses to uppercase initials', () {
      expect(avatarInitials('Alice bob'), 'AB');
    });

    test('single uppercase char passes through', () {
      expect(avatarInitials('Z'), 'Z');
    });

    test('only-separator string -> "?" fallback', () {
      expect(avatarInitials('---'), '?');
    });

    test('multiple adjacent separators collapse, drop empties', () {
      // "a   b" splits to ["a", "", "", "b"] -> empties dropped -> "ab".
      expect(avatarInitials('a   b'), 'AB');
    });

    test('name with all three separators', () {
      // "a b-c_d" -> ["a","b","c","d"] -> "abcd" capped to "AB".
      expect(avatarInitials('a b-c_d'), 'AB');
    });

    test('long single word capped to 1 initial (no separator)', () {
      expect(avatarInitials('juno'), 'J');
    });

    test('two-word name with extra spacing -> two initials', () {
      expect(avatarInitials('  alice  bob  '), 'AB');
    });
  });

  // The Delivery ticks card: one glyph per state, named for a screen reader
  // by the state's label. A message on its way shows the clock of a queued
  // one; a failed one has no tick at all.
  group('DeliveryTicks', () {
    final tone = MessageTone.from(MoshColors.dark, own: true);
    for (final (status, icon, label) in [
      (MessageDeliveryStatus.delivered, MoshIcons.doneAll, '✓✓ delivered'),
      (MessageDeliveryStatus.sent, MoshIcons.check, '✓ sent'),
      (MessageDeliveryStatus.pending, MoshIcons.schedule, 'sending…'),
      (MessageDeliveryStatus.queued, MoshIcons.schedule, 'queued'),
    ]) {
      testWidgets('${status.name} draws its glyph and says "$label"',
          (tester) async {
        await pumpScreen(
            tester, Scaffold(body: DeliveryTicks(status: status, tone: tone)));
        expect(find.byIcon(icon), findsOneWidget);
        expect(find.bySemanticsLabel(label), findsOneWidget);
      });
    }

    for (final status in [MessageDeliveryStatus.failed, null]) {
      testWidgets('${status?.name} renders no tick', (tester) async {
        await pumpScreen(
            tester, Scaffold(body: DeliveryTicks(status: status, tone: tone)));
        expect(find.byType(Icon), findsNothing);
      });
    }
  });
}
