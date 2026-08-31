/// AES-GCM frame seal / open for a 1:1 voice call. 1:1 port of the crypto
/// surface from React `mosh/src/features/private-dm/voice-call/frame-crypto.ts`.
/// The wire frame is `[seq:u64 BE][ciphertext-with-16-byte-tag]`; the AES-GCM
/// nonce is `[nonce_prefix (4)][seq (8)]`. The high bit of `seq` distinguishes
/// caller vs callee so the two participants never collide nonces while sharing
/// one key. The pure byte helpers (buildNonce / buildFrame / parseFrame /
/// direction-bit constants) are reused from `frame_codec.dart` (DRY).
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'frame_codec.dart';

/// Imports a base64-encoded 32-byte AES-GCM key. `SecretKeyData` is the only
/// concrete `SecretKey` impl in `package:cryptography` (the abstract `SecretKey`
/// cannot be instantiated directly); it implements `SecretKey`.
Future<SecretKey> importCallKey(String keyBase64) async {
  final raw = bytesFromBase64(keyBase64);
  return SecretKeyData(raw);
}

/// Seals `payload` under `key` + `noncePrefixBase64` / `seqValue` /
/// `directionBit`. Throws `ArgumentError` if `seqValue` is outside
/// `[0, SEQ_VALUE_MASK]` (React: `Error("call frame seq out of range")`).
/// Returns the wire frame `[seq][ciphertext+tag]` (cryptography's `SecretBox`
/// keeps the tag separate from `cipherText`; React Web Crypto returns them
/// already concatenated, so we re-concatenate to match).
Future<Uint8List> sealFrame(
  SecretKey key,
  String noncePrefixBase64,
  BigInt seqValue,
  BigInt directionBit,
  Uint8List payload,
) async {
  if (seqValue < BigInt.zero || seqValue > SEQ_VALUE_MASK) {
    throw ArgumentError('call frame seq out of range');
  }
  final seq = seqValue | directionBit;
  final nonce = buildNonce(noncePrefixBase64, seq);
  final algo = AesGcm.with256bits();
  final secretBox = await algo.encrypt(payload, secretKey: key, nonce: nonce);
  final wire = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
  return buildFrame(seq, wire);
}

/// Opens a sealed wire frame. Returns `null` on any failure (too-short frame,
/// missing tag, GCM auth mismatch) to mirror React's `catch { return null }`.
/// `parsed.ciphertext` is `[ciphertext][16-byte tag]`; the tag is always the
/// last 16 bytes, so we split, rebuild a `SecretBox`, and decrypt.
Future<({BigInt seq, Uint8List payload})?> openFrame(
  SecretKey key,
  String noncePrefixBase64,
  Uint8List frame,
) async {
  final parsed = parseFrame(frame);
  if (parsed == null) return null;
  if (parsed.ciphertext.length < 16) return null;
  final nonce = buildNonce(noncePrefixBase64, parsed.seq);
  final tagOffset = parsed.ciphertext.length - 16;
  final ct = Uint8List.sublistView(parsed.ciphertext, 0, tagOffset);
  final macBytes = Uint8List.sublistView(parsed.ciphertext, tagOffset);
  // SecretBox(cipherText, {required nonce, required mac}) -- positional first.
  final secretBox = SecretBox(ct, nonce: nonce, mac: Mac(macBytes));
  final algo = AesGcm.with256bits();
  try {
    final clear = await algo.decrypt(secretBox, secretKey: key);
    return (seq: parsed.seq, payload: Uint8List.fromList(clear));
  } catch (_) {
    return null;
  }
}
