import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Duplex requests over inherited stdio. Only presentation and call commands
/// cross this pipe; no listening port or runtime credentials are needed.
class CallWindowPipe {
  CallWindowPipe(Stream<String> lines, this.write, {Future<void>? outputDone}) {
    _input =
        lines.listen(_receive, onDone: _lost, onError: (Object _) => _lost());
    if (outputDone != null) {
      unawaited(outputDone.then<void>((_) => _lost(),
          onError: (Object _) => _lost()));
    }
  }

  static const prefix = 'mosh-call-window:';
  final void Function(String) write;
  late final StreamSubscription<String> _input;
  final _pending = <int, Completer<Object?>>{};
  Future<Object?> Function(MethodCall)? onMethod;
  void Function()? onClosed;
  int _nextId = 0;
  bool _closed = false;

  Future<Object?> invoke(String method, [Object? arguments]) async {
    if (_closed) throw StateError('Call window pipe closed');
    final id = ++_nextId;
    final result = Completer<Object?>();
    _pending[id] = result;
    try {
      _send({'id': id, 'method': method, 'arguments': arguments});
      return await result.future.timeout(const Duration(seconds: 10));
    } finally {
      _pending.remove(id);
    }
  }

  void _send(Map<String, Object?> message) {
    if (_closed) return;
    try {
      write('$prefix${jsonEncode(message)}');
    } catch (_) {
      _lost();
    }
  }

  void _receive(String line) {
    if (!line.startsWith(prefix) || _closed) return;
    try {
      final map =
          jsonDecode(line.substring(prefix.length)) as Map<String, Object?>;
      final id = map['id'] as int;
      final method = map['method'] as String?;
      if (method != null) {
        unawaited(_dispatch(id, MethodCall(method, map['arguments'])));
      } else {
        final result = _pending.remove(id);
        if (result == null) return;
        if (map['error'] != null) {
          result.completeError(StateError('Call window request failed'));
        } else {
          result.complete(map['result']);
        }
      }
    } catch (_) {
      _lost();
    }
  }

  Future<void> _dispatch(int id, MethodCall call) async {
    try {
      final handler = onMethod;
      if (handler == null) throw MissingPluginException();
      _send({'id': id, 'result': await handler(call)});
    } catch (_) {
      _send({'id': id, 'error': true});
    }
  }

  void _lost() {
    if (_closed) return;
    _closed = true;
    for (final result in _pending.values) {
      result.completeError(StateError('Call window pipe closed'));
    }
    _pending.clear();
    onClosed?.call();
  }

  Future<void> dispose() async {
    _lost();
    await _input.cancel();
  }
}
