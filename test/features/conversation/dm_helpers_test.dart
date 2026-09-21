// Unit tests for [avatarInitials]:
//   name.split(/[\s_-]+/).map(p => p[0]).filter(Boolean).join("").slice(0,2).toUpperCase() || "?"
// Each case below pins the expected behavior so a future change surfaces
// as a test failure. Pure function -- no widget harness.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

import 'package:flutter/material.dart';
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
    test('three words capped to 2 initials', () {
      expect(avatarInitials('alpha beta gamma'), 'AB');
    });

    test('lowercase input is uppercased', () {
      expect(avatarInitials('alice bob'), 'AB');
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

  // Widget tests for [DeliveryTicks]. The widget renders the FULL readable
  // label (glyph + word) with a matching semantics label:
  //   delivered -> "✓✓ delivered"
  //   sent      -> "✓ sent"
  //   pending   -> "sending…"
  //   failed/null -> renders nothing.
  // Each case pumps [DeliveryTicks] in a localized `MaterialApp` (en) and
  // asserts BOTH the visible `Text` matches the localized label AND the
  // `Semantics` label is "Delivery: <label>".
  group('DeliveryTicks', () {
    testWidgets(
        'delivered -> "✓✓ delivered" text + "Delivery: ✓✓ delivered" semantics',
        (tester) async {
      await pumpScreen(
          tester,
          Scaffold(
              body: const DeliveryTicks(
                  status: MessageDeliveryStatus.delivered)));
      expect(find.text('✓✓ delivered'), findsOneWidget);
      expect(find.bySemanticsLabel('Delivery: ✓✓ delivered'), findsOneWidget);
    });

    testWidgets('sent -> "✓ sent" text + "Delivery: ✓ sent" semantics',
        (tester) async {
      await pumpScreen(
          tester,
          Scaffold(
              body: const DeliveryTicks(status: MessageDeliveryStatus.sent)));
      expect(find.text('✓ sent'), findsOneWidget);
      expect(find.bySemanticsLabel('Delivery: ✓ sent'), findsOneWidget);
    });

    testWidgets('pending -> "sending…" text + "Delivery: sending…" semantics',
        (tester) async {
      await pumpScreen(
          tester,
          Scaffold(
              body:
                  const DeliveryTicks(status: MessageDeliveryStatus.pending)));
      expect(find.text('sending…'), findsOneWidget);
      expect(find.bySemanticsLabel('Delivery: sending…'), findsOneWidget);
    });

    testWidgets('failed -> renders nothing (no Text)', (tester) async {
      await pumpScreen(
          tester,
          Scaffold(
              body: const DeliveryTicks(status: MessageDeliveryStatus.failed)));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('null status -> renders nothing (no Text)', (tester) async {
      await pumpScreen(
          tester, Scaffold(body: const DeliveryTicks(status: null)));
      expect(find.byType(Text), findsNothing);
    });
  });
}
