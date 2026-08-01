// Parity tests for `JitterBuffer` (lib/src/features/dm/jitter_buffer.dart)
// -- the 1-to-1 port of React's `jitter-buffer.ts`. Mirrors the React
// suite: in-order drain, cursor drop, gap pause, force-skip past the cap,
// and the #14 strictly-increasing-seqs regression guard.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/jitter_buffer.dart';

BufferedFrame _frame(int seq, int byte) =>
    BufferedFrame(seq: BigInt.from(seq), payload: Uint8List.fromList([byte]));

List<int> _seqs(List<BufferedFrame> drained) =>
    drained.map((f) => f.seq.toInt()).toList();

void main() {
  test('drains frames in seq order', () {
    final buf = JitterBuffer();
    buf.push(_frame(2, 2));
    buf.push(_frame(1, 1));
    buf.push(_frame(3, 3));
    expect(_seqs(buf.drainReady()), [1, 2, 3]);
  });

  test('drops frames at or below the cursor', () {
    final buf = JitterBuffer();
    buf.push(_frame(1, 1));
    buf.drainReady();
    buf.push(_frame(1, 1));
    expect(buf.drainReady(), isEmpty);
  });

  test('does not drain a gap until the missing frame arrives', () {
    final buf = JitterBuffer();
    buf.push(_frame(1, 1));
    buf.push(_frame(3, 3));
    expect(_seqs(buf.drainReady()), [1]);
    buf.push(_frame(2, 2));
    expect(_seqs(buf.drainReady()), [2, 3]);
  });

  test('force-skips a gap after the cap and resumes', () {
    final buf = JitterBuffer(8);
    for (var i = 2; i <= 12; i += 1) {
      buf.push(_frame(i, i));
    }
    final drained = _seqs(buf.drainReady());
    expect(drained.first, 2);
    expect(drained.last, 12);
  });

  test('emits strictly increasing seqs across a forced skip (#14)', () {
    final buf = JitterBuffer(3);
    buf.push(_frame(1, 1));
    for (var i = 4; i <= 9; i += 1) {
      buf.push(_frame(i, i));
    }
    final drained = _seqs(buf.drainReady());
    for (var i = 1; i < drained.length; i += 1) {
      expect(drained[i], greaterThan(drained[i - 1]));
    }
  });
}
