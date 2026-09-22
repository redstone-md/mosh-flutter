/// Pure (non-crypto) byte-manipulation helpers for AES-GCM voice-call frames.
///
/// The wire frame is `[seq:u64 BE][ciphertext-with-tag]`; the AES-GCM nonce
/// is `[nonce_prefix (4)][seq (8)]`. The high bit of `seq` distinguishes
/// caller vs callee so the two participants never collide nonces while
/// sharing one key. The AES-GCM seal/open + key import live elsewhere;
/// only the synchronous, dependency-free helpers live here.
library;
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:convert';
import 'dart:typed_data';

/// Caller direction bit. Seq uses BigInt because Dart `int` is signed
/// 64-bit and the direction bit sets bit 63 (out of positive-int range).
/// Not `const` because [BigInt.zero] is not a const expression in Dart.
final BigInt CALLER_DIRECTION_BIT = BigInt.zero;

/// Callee direction bit.
final BigInt CALLEE_DIRECTION_BIT = BigInt.one << 63;

/// Mask for the 63-bit seq value space.
final BigInt SEQ_VALUE_MASK = (BigInt.one << 63) - BigInt.one;

Uint8List bytesFromBase64(String value) => base64Decode(value);

String bytesToBase64(Uint8List value) => base64Encode(value);

/// 8-byte big-endian encoding of `seq`. Manual extraction instead of
/// `ByteData.setUint64` because Dart's `int` is signed 64-bit and values with
/// bit 63 set (e.g. [CALLEE_DIRECTION_BIT]) misbehave under setUint64.
Uint8List seqToBytes(BigInt seq) {
  final out = Uint8List(8);
  final u = seq.toUnsigned(64);
  for (var i = 0; i < 8; i += 1) {
    out[7 - i] = ((u >> (8 * i)) & BigInt.from(0xff)).toInt();
  }
  return out;
}

/// Reads 8 bytes big-endian starting at [offset].
BigInt bytesToSeq(Uint8List bytes, int offset) {
  var result = BigInt.zero;
  for (var i = 0; i < 8; i += 1) {
    result = (result << 8) | BigInt.from(bytes[offset + i]);
  }
  return result;
}

/// 12-byte nonce = `[prefix (4)][seq (8)]`. Throws if `prefixBase64` does not
/// decode to exactly 4 bytes.
Uint8List buildNonce(String prefixBase64, BigInt seq) {
  final prefix = bytesFromBase64(prefixBase64);
  if (prefix.length != 4) {
    throw ArgumentError('nonce prefix must be 4 bytes');
  }
  final nonce = Uint8List(12);
  nonce.setRange(0, 4, prefix);
  nonce.setRange(4, 12, seqToBytes(seq));
  return nonce;
}

/// Concatenates `[seqToBytes(seq)][ciphertext]`.
Uint8List buildFrame(BigInt seq, Uint8List ciphertext) {
  final header = seqToBytes(seq);
  final out = Uint8List(header.length + ciphertext.length);
  out.setRange(0, header.length, header);
  out.setRange(header.length, out.length, ciphertext);
  return out;
}

/// Parses a wire frame. Returns `null` when fewer than 9 bytes (a frame needs
/// at least 1 ciphertext byte on top of the 8-byte seq header).
({BigInt seq, Uint8List ciphertext})? parseFrame(Uint8List bytes) {
  if (bytes.length < 9) return null;
  return (
    seq: bytesToSeq(bytes, 0),
    ciphertext: Uint8List.fromList(bytes.sublist(8)),
  );
}
