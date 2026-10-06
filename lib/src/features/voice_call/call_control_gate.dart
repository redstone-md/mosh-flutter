import 'dart:async';

/// Tracks control lifetimes by call ID. A late operation cannot block or
/// release a replacement call, and close can await its own pending operation.
class CallControlGate {
  final _pending = <String, Completer<void>>{};

  bool isBusy(String id) => _pending.containsKey(id);

  Future<void> wait(String id) async => await _pending[id]?.future;

  Future<void> run(String id, Future<void> Function() operation) async {
    if (isBusy(id)) return;
    final done = Completer<void>();
    _pending[id] = done;
    try {
      await operation();
    } finally {
      _pending.remove(id);
      done.complete();
    }
  }
}
