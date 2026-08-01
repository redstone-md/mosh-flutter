// JitterBuffer -- 1-to-1 port of React `src/features/private-dm/voice-call/
// jitter-buffer.ts`. A small in-memory reorder buffer for received
// voice-call frames: it drains frames in seq order, pauses on a gap, and
// once the buffered backlog exceeds `gapCap` frames it force-skips the
// missing seq and resumes (cheap PLC). Pure, no I/O, unit-testable.
//
// Mirrors the React class field-for-field:
//   - `pending: Map<bigint, Uint8Array>`  -> `_pending: Map<BigInt, Uint8List>`
//   - `cursor: bigint | null`             -> `_cursor: BigInt?`
//   - `gapCap: number`                    -> `gapCap: int`
// `push` drops frames at or below the cursor; `drainReady` walks the
// pending set in seq order, advances the cursor one drained frame at a
// time, and -- when the backlog exceeds `gapCap` -- jumps the expected
// seq forward to the lowest remaining pending key (it does NOT delete a
// gap, since the gap was never in `pending`).

library;

import 'dart:typed_data';

/// An immutable received frame held by [JitterBuffer] -- 1-to-1 with
/// React's `BufferedFrame` interface (`seq: bigint`, `payload: Uint8Array`).
class BufferedFrame {
  const BufferedFrame({required this.seq, required this.payload});

  /// The frame sequence number (React `seq: bigint`).
  final BigInt seq;

  /// The frame bytes (React `payload: Uint8Array`).
  final Uint8List payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BufferedFrame && seq == other.seq && _payloadEq(payload, other.payload);

  @override
  int get hashCode => Object.hash(seq, Object.hashAll(payload));

  static bool _payloadEq(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A small in-memory reorder buffer for received voice-call frames --
/// 1-to-1 with React's `JitterBuffer`. Drains in seq order, pauses on a
/// gap, and force-skips the missing seq once the backlog exceeds
/// [gapCap] frames (cheap PLC).
class JitterBuffer {
  JitterBuffer([this.gapCap = 8]);

  /// The backlog threshold (in frames) above which a gap is force-skipped
  /// -- React `gapCap: number` (default 8).
  final int gapCap;

  final Map<BigInt, Uint8List> _pending = {};
  BigInt? _cursor;

  /// Pushes a received frame into the buffer -- 1-to-1 with React `push`.
  /// Drops the frame if it is at or below the cursor (already drained).
  void push(BufferedFrame frame) {
    final cursor = _cursor;
    if (cursor != null && frame.seq <= cursor) return;
    _pending[frame.seq] = frame.payload;
  }

  /// Drains every contiguous-in-order frame the buffer can release right
  /// now -- 1-to-1 with React `drainReady`. Pauses on a gap; once the
  /// backlog exceeds [gapCap] it jumps the expected seq to the lowest
  /// remaining pending key and resumes.
  List<BufferedFrame> drainReady() {
    final out = <BufferedFrame>[];
    if (_pending.isEmpty) return out;
    final seqs = _pending.keys.toList()
      ..sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
    // React: `next = this.cursor === null ? seqs[0] : this.cursor + 1n` --
    // an unset cursor starts at the lowest pending seq; a set cursor
    // resumes one past the last drained frame.
    var next = _cursor == null ? seqs.first : _cursor! + BigInt.one;
    for (;;) {
      final payload = _pending[next];
      if (payload != null) {
        out.add(BufferedFrame(seq: next, payload: payload));
        _pending.remove(next);
        _cursor = next;
        next = next + BigInt.one;
        continue;
      }
      if (_pending.length > gapCap) {
        final remaining = _pending.keys.toList()
          ..sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
        next = remaining.first;
        continue;
      }
      break;
    }
    return out;
  }
}
