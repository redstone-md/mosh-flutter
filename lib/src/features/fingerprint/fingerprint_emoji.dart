/// Maps a fingerprint string to its emoji form -- 4 emoji from the
/// Telegram pool, deterministic for the same input.
///
/// A DM shows the creator's fingerprint and so does every group member
/// (`creator_fingerprint`), so both sides read the same string and
/// derive the same emoji: comparing them over a call catches a swapped
/// invite, the same idea as Telegram's call emoji fingerprint. Nothing
/// here touches the runtime -- it is a pure client-side view of a
/// value the runtime already gives us.
library;

import 'package:mosh/src/features/fingerprint/fingerprint_emoji_pool.dart';

/// How many emoji a fingerprint renders as. Telegram shows 4.
const int _emojiCount = 4;

/// The two bytes (one group) that pick one emoji.
const int _bytesPerEmoji = 2;

/// Hex fingerprints, lower or upper case. The real fingerprints are the
/// hex of 8 key bytes (16 chars); anything else (test seeds like
/// "fp-peer-1234") falls back to code units below.
final RegExp _hexDigits = RegExp(r'^[0-9a-fA-F]+$');

/// The emoji form of [fingerprint]: 4 pool entries, or none when the
/// fingerprint is empty.
///
/// The same string always maps to the same emoji. Each emoji comes from
/// one byte pair read as a 16-bit value, modulo the pool size -- a
/// human comparison surface, not a cryptographic digest, so the slight
/// modulo bias is fine (Telegram's own mapping is a plain `%` too).
List<String> fingerprintEmoji(String fingerprint) {
  if (fingerprint.isEmpty) return const [];
  final bytes = _fingerprintBytes(fingerprint);
  return [
    for (var i = 0; i < _emojiCount; i++)
      fingerprintEmojiPool[_poolIndex(bytes, i)],
  ];
}

/// The fingerprint's own bytes when it is hex; its code units masked
/// to a byte otherwise. Either way the input decides the output alone.
List<int> _fingerprintBytes(String fingerprint) {
  final isHex = fingerprint.length.isEven && _hexDigits.hasMatch(fingerprint);
  if (isHex) {
    return [
      for (var i = 0; i < fingerprint.length; i += _bytesPerEmoji)
        int.parse(fingerprint.substring(i, i + _bytesPerEmoji), radix: 16),
    ];
  }
  return [for (final unit in fingerprint.codeUnits) unit & 0xff];
}

/// Byte pair [position] of the emoji reading, wrapping when the byte
/// list is shorter than 8 (a degenerate fingerprint still gets its 4).
int _poolIndex(List<int> bytes, int position) {
  final high = bytes[(position * _bytesPerEmoji) % bytes.length];
  final low = bytes[(position * _bytesPerEmoji + 1) % bytes.length];
  return ((high << 8) | low) % fingerprintEmojiPool.length;
}
