import 'dart:async';

/// Tracks control lifetimes by call ID. A late operation cannot block or
/// release a replacement call, and close can await its own pending operation.
class CallControlGate {
  final _pending = <String, Completer<void>>{};

  bool isBusy(String id) => _pending.containsKey(id);

  Future<void> wait(String id) async => await _pending[id]?.future;

  /// Resolve again after each wait: an authenticated merge can change the ID
  /// while retaining the user's intent; an unrelated replacement resolves null.
  Future<String?> waitForCurrent(String? Function() currentId) async {
    while (true) {
      final id = currentId();
      if (id == null) return null;
      await wait(id);
      if (currentId() == id) return id;
    }
  }

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
