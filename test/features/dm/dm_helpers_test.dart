// Unit tests for [avatarInitials] -- the Flutter port of React's `Avatar`
// initials algorithm (src/features/private-dm/Avatar.tsx):
//   name.split(/[\s_-]+/).map(p => p[0]).filter(Boolean).join("").slice(0,2).toUpperCase() || "?"
// Each case below mirrors the React behavior 1-в-1 so a future change to
// either side surfaces as a test failure. Pure function -- no widget harness.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/dm_helpers.dart';

void main() {
  group('avatarInitials', () {
    // --- Parity cases (React Avatar.tsx behavior) ---
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
}
