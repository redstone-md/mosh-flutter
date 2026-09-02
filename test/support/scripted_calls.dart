// The recording/scripting engine the two test doubles share.
//
// Both `ScriptableGateway` (the conversation seam) and `ScriptableBridge`
// (the bridge facade) need the same three things -- record every call, fail
// a call on script, hold a call open -- so the machinery lives here once and
// each double mixes it in over its own method enum. The doubles stay flat:
// one method per call, no nesting.
import 'dart:async';

import 'package:mosh/src/gateway/conversation_target.dart';

/// One recorded call: which method, and the named arguments it got.
class ScriptedCall<M extends Enum> {
  ScriptedCall(this.method, this.args);

  final M method;
  final Map<String, Object?> args;

  /// Read one argument. Throws if the argument is not there or has another
  /// type, so a renamed or retyped argument fails the test loudly instead of
  /// reading as null.
  T arg<T>(String name) {
    if (!args.containsKey(name)) {
      throw ArgumentError('${method.name} has no argument named "$name"');
    }
    return args[name] as T;
  }

  /// The conversation a call was for. Only the conversation methods carry a
  /// target -- reading it on any other call throws.
  AnyConversationTarget get target => arg<AnyConversationTarget>('target');

  @override
  String toString() => '${method.name}($args)';
}

/// A scripted failure: throw [error] for the next [remaining] calls
/// (`null` remaining means every call).
class _ScriptedFailure {
  _ScriptedFailure(this.error, this.remaining);

  final Object error;
  int? remaining;

  bool consume() {
    final left = remaining;
    if (left == null) return true;
    if (left <= 0) return false;
    remaining = left - 1;
    return true;
  }
}

/// The record/fail/hold engine, keyed by the double's own method enum [M].
///
/// See the double file headers for the full contract: tests configure the
/// double through this engine; they never subclass a double.
mixin ScriptedEngine<M extends Enum> {
  /// Every call the code under test made, in order.
  final List<ScriptedCall<M>> calls = [];

  final Map<M, _ScriptedFailure> _failures = {};
  final Map<M, Completer<void>> _held = {};

  // ---------------------------------------------------------------- asserts

  /// Every recorded call to [method].
  List<ScriptedCall<M>> callsTo(M method) =>
      calls.where((call) => call.method == method).toList();

  /// How many times [method] was called.
  int countOf(M method) => callsTo(method).length;

  /// The last call to [method], or null if it was never called.
  ScriptedCall<M>? lastCall(M method) {
    final matching = callsTo(method);
    return matching.isEmpty ? null : matching.last;
  }

  /// One named argument from every call to [method], in call order.
  List<T> argValues<T>(M method, String name) =>
      callsTo(method).map((call) => call.arg<T>(name)).toList();

  // -------------------------------------------------------------- scripting

  /// Make the next [times] calls to [method] throw. [error] defaults to an
  /// [Exception]; pass a bare String where the screen renders the raw value.
  void failNext(M method, {Object? error, int times = 1}) {
    _failures[method] = _ScriptedFailure(error ?? _defaultError(method), times);
  }

  /// Make every call to [method] throw.
  void failAlways(M method, {Object? error}) {
    _failures[method] = _ScriptedFailure(error ?? _defaultError(method), null);
  }

  /// Hold calls to [method] open so a test can observe the pending UI.
  /// [release] lets them finish; without it they stay pending.
  void hold(M method) => _held.putIfAbsent(method, () => Completer<void>());

  /// Let held calls to [method] finish and return their normal result.
  void release(M method) {
    final gate = _held.remove(method);
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Object _defaultError(M method) =>
      Exception('the scripted double: scripted failure of ${method.name}');

  // ----------------------------------------------------------------- engine

  /// Record the call, apply any script, then produce the result.
  Future<T> runScripted<T>(
    M method,
    Map<String, Object?> args,
    FutureOr<T> Function() result,
  ) async {
    calls.add(ScriptedCall<M>(method, args));
    final failure = _failures[method];
    if (failure != null && failure.consume()) throw failure.error;
    final gate = _held[method];
    if (gate != null) await gate.future;
    return result();
  }
}
