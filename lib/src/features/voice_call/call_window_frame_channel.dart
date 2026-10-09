import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Dedicated presentation bytes. Controls retain inherited stdio and priority.
/// The capability is handed only to the spawned renderer through that pipe.
class CallWindowFrameChannel {
  CallWindowFrameChannel._(this._server)
      : token = List.generate(32, (_) => Random.secure().nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join() {
    _connections = _server.listen(_accept);
  }

  static Future<CallWindowFrameChannel> bind() async =>
      CallWindowFrameChannel._(
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final String token;
  final _ready = Completer<void>();
  final _clients = <Socket>{};
  late final StreamSubscription<Socket> _connections;
  Socket? _socket;
  bool _closed = false;
  bool _claimed = false;
  void Function()? onClosed;
  Map<String, Object> get descriptor => {'port': _server.port, 'token': token};
  Future<void> get ready => _ready.future;

  void _accept(Socket socket) {
    if (_closed || _claimed || _clients.length >= 4) {
      socket.destroy();
      return;
    }
    _clients.add(socket);
    final received = <int>[];
    final deadline = Timer(const Duration(seconds: 2), socket.destroy);
    socket.listen((bytes) {
      if (identical(socket, _socket) || received.length + bytes.length > 64) {
        socket.destroy();
        return;
      }
      received.addAll(bytes);
      if (received.length != 64) return;
      var difference = 0;
      for (var i = 0; i < 64; ++i) {
        difference |= received[i] ^ token.codeUnitAt(i);
      }
      if (difference != 0 || _claimed) {
        socket.destroy();
        return;
      }
      deadline.cancel();
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _claimed = true;
      _ready.complete();
    }, onDone: () {
      deadline.cancel();
      _clients.remove(socket);
      if (identical(socket, _socket) && !_closed) {
        _socket = null;
        onClosed?.call();
      }
    }, onError: (Object _) => socket.destroy());
  }

  bool send(List<int> bytes) {
    if (_closed || _socket == null) return false;
    try {
      _socket!.add(bytes);
      return true;
    } catch (_) {
      _socket?.destroy();
      return false;
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    for (final socket in _clients.toList()) {
      socket.destroy();
    }
    _clients.clear();
    _socket = null;
    await _connections.cancel();
    await _server.close();
  }

  static Future<Socket> connect(int port, String token) async {
    if (port <= 0 ||
        port > 65535 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException('Invalid renderer capability');
    }
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port,
        timeout: const Duration(seconds: 5));
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.add(ascii.encode(token));
    return socket;
  }
}
