import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mosh/src/rust/api/attachment_stream.dart';

typedef AttachmentRangeFetcher = Future<AttachmentStreamRange> Function({
  required String kind,
  required String host,
  required String attachmentId,
  required BigInt start,
  required BigInt end,
});

const int _maxWindow = 512 * 1024;
final BigInt _maxU64 = BigInt.parse('18446744073709551615');
final BigInt _maxWindowBigInt = BigInt.from(_maxWindow);

/// The end of the window fetched at [start], inside a span that ends at
/// [end] when it has one. Ends are exclusive.
BigInt _windowEnd(BigInt start, BigInt? end) {
  final window =
      (start + _maxWindowBigInt) > _maxU64 ? _maxU64 : start + _maxWindowBigInt;
  return end == null || end > window ? window : end;
}

final class MediaRange {
  const MediaRange({required this.start, this.end, this.isDefault = false});

  final BigInt start;

  /// The last byte asked for; null when the range runs to the end.
  final BigInt? end;
  final bool isDefault;

  /// Where the range stops, exclusively, when it names an end.
  BigInt? get limit => end == null ? null : end! + BigInt.one;

  /// Where the range stops in an attachment of [totalSize]: one without an
  /// end, or with an end past the attachment, runs to the attachment's.
  BigInt endExclusive(BigInt totalSize) {
    final limit = this.limit;
    return limit == null || limit > totalSize ? totalSize : limit;
  }
}

/// A request the server ends with [status] instead of the attachment.
final class _Refusal implements Exception {
  const _Refusal(this.status, [this.headers = const <String, String>{}]);

  /// A range that starts outside an attachment of [totalSize].
  _Refusal.outside(BigInt totalSize)
      : this(HttpStatus.requestedRangeNotSatisfiable,
            {'content-range': 'bytes */$totalSize'});

  final int status;
  final Map<String, String> headers;
}

MediaRange? parseMediaRange(String? value) {
  if (value == null) {
    return MediaRange(start: BigInt.zero, isDefault: true);
  }
  if (value.contains(',')) return null;
  final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(value.trim());
  if (match == null) return null;
  final start = BigInt.tryParse(match.group(1)!);
  final endText = match.group(2)!;
  final end = endText.isEmpty ? null : BigInt.tryParse(endText);
  if (start == null || start > _maxU64) return null;
  if (endText.isNotEmpty && (end == null || end > _maxU64)) return null;
  if (end != null && end < start) return null;
  return MediaRange(start: start, end: end);
}

final class MediaStreamRoute {
  const MediaStreamRoute({
    required this.kind,
    required this.host,
    required this.attachmentId,
  });

  final String kind;
  final String host;
  final String attachmentId;

  static MediaStreamRoute? parse(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 3 || segments.any((segment) => segment.isEmpty)) {
      return null;
    }
    final kind = segments[0];
    if (kind != 'dm' && kind != 'channel' && kind != 'group') return null;
    return MediaStreamRoute(
      kind: kind,
      host: segments[1],
      attachmentId: segments[2],
    );
  }
}

final class MediaStreamServer {
  MediaStreamServer({
    required AttachmentRangeFetcher fetchRange,
    Duration pollInterval = const Duration(milliseconds: 60),
    Duration pollTimeout = const Duration(seconds: 30),
  })  : _fetchRange = fetchRange,
        _pollInterval = pollInterval,
        _pollTimeout = pollTimeout;

  static final MediaStreamServer instance = MediaStreamServer(
    fetchRange: streamAttachmentRange,
  );

  final AttachmentRangeFetcher _fetchRange;
  final Duration _pollInterval;
  final Duration _pollTimeout;
  HttpServer? _server;
  Future<void>? _startOperation;

  Uri? get baseUri {
    final server = _server;
    return server == null
        ? null
        : Uri(scheme: 'http', host: server.address.address, port: server.port);
  }

  Future<void> start() {
    if (_server != null) return Future<void>.value();
    return _startOperation ??= _bindServer().whenComplete(() {
      _startOperation = null;
    });
  }

  Future<void> _bindServer() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
  }

  Future<void> close() async {
    final startOperation = _startOperation;
    if (startOperation != null) {
      try {
        await startOperation;
      } catch (_) {
        return;
      }
    }
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handle(request));
      }
    } on StateError {
      // Closing the server ends the stream with a StateError on some hosts.
    } on SocketException {
      // A process-level socket shutdown is already a successful close.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await _answer(request);
    } catch (error) {
      // Anything that is not a refusal is an attachment the fetch failed on.
      final refusal =
          error is _Refusal ? error : const _Refusal(HttpStatus.notFound);
      try {
        await _finish(request.response, refusal.status,
            headers: refusal.headers);
      } catch (_) {
        // The client may have disconnected while the fetch was in flight.
      }
    }
  }

  /// The attachment and the range [request] asks for.
  (MediaStreamRoute, MediaRange) _asked(HttpRequest request) {
    if (request.method != 'GET' && request.method != 'HEAD') {
      throw const _Refusal(HttpStatus.methodNotAllowed, {'allow': 'GET, HEAD'});
    }
    final route = MediaStreamRoute.parse(request.uri);
    if (route == null) throw const _Refusal(HttpStatus.notFound);
    final ranges = request.headers[HttpHeaders.rangeHeader] ?? const [];
    final range = switch (ranges) {
      [] => parseMediaRange(null),
      [final only] => parseMediaRange(only),
      _ => null,
    };
    if (range == null) {
      throw const _Refusal(HttpStatus.requestedRangeNotSatisfiable);
    }
    return (route, range);
  }

  /// One window of an attachment, waited for while it is still downloading.
  Future<AttachmentStreamRange> _ready(
    MediaStreamRoute route,
    BigInt start,
    BigInt end,
  ) async {
    final deadline = DateTime.now().add(_pollTimeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const _Refusal(HttpStatus.gatewayTimeout);
      }
      final AttachmentStreamRange result;
      try {
        result = await _fetchRange(
          kind: route.kind,
          host: route.host,
          attachmentId: route.attachmentId,
          start: start,
          end: end,
        ).timeout(remaining);
      } on TimeoutException {
        throw const _Refusal(HttpStatus.gatewayTimeout);
      }
      switch (result.state) {
        case AttachmentStreamState.ready:
          return result;
        case AttachmentStreamState.unknown:
          throw const _Refusal(HttpStatus.notFound);
        case AttachmentStreamState.pending:
          if (start >= result.totalSize) {
            throw _Refusal.outside(result.totalSize);
          }
          await Future<void>.delayed(
            remaining < _pollInterval ? remaining : _pollInterval,
          );
      }
    }
  }

  /// Answers with everything the range asks for, however many windows that
  /// is: a player may take a response as the whole of what it requested.
  Future<void> _answer(HttpRequest request) async {
    final (route, range) = _asked(request);
    final start = range.start;
    final first = await _ready(route, start, _windowEnd(start, range.limit));
    final total = first.totalSize;
    final empty = total == BigInt.zero && start == BigInt.zero;
    if (empty ? !range.isDefault : start >= total) {
      throw _Refusal.outside(total);
    }
    if (empty && first.bytes.isNotEmpty) {
      throw const _Refusal(HttpStatus.notFound);
    }
    final end = range.endExclusive(total);
    final head = _exactly(first.bytes, _windowEnd(start, end) - start);
    final last = end == start ? start : end - BigInt.one;
    final response = request.response;
    response.statusCode = HttpStatus.partialContent;
    response.headers
      ..set('content-type',
          first.mime.isEmpty ? 'application/octet-stream' : first.mime)
      ..set('accept-ranges', 'bytes')
      ..set('content-range', 'bytes $start-$last/$total')
      ..contentLength = (end - start).toInt();
    if (request.method == 'GET') {
      try {
        await _send(
            response, route, head, start + BigInt.from(head.length), end);
      } catch (_) {
        // The status is already sent, so a window that never comes can only
        // cut the connection: the player then asks again from where it
        // stopped, instead of taking what it got for the whole attachment.
        response.deadline = Duration.zero;
        return;
      }
    }
    await response.close();
  }

  /// Writes [head] and then the windows from [sent] up to [end], each once
  /// the client has taken the one before, so no more than a window waits
  /// in memory.
  Future<void> _send(
    HttpResponse response,
    MediaStreamRoute route,
    List<int> head,
    BigInt sent,
    BigInt end,
  ) async {
    response.add(head);
    while (sent < end) {
      await response.flush();
      final windowEnd = _windowEnd(sent, end);
      final next = await _ready(route, sent, windowEnd);
      response.add(_exactly(next.bytes, windowEnd - sent));
      sent = windowEnd;
    }
  }

  /// The first [length] of a window's [bytes]; a window shorter than that
  /// is not the attachment's.
  List<int> _exactly(List<int> bytes, BigInt length) {
    if (BigInt.from(bytes.length) < length) {
      throw const _Refusal(HttpStatus.notFound);
    }
    return bytes.length == length.toInt()
        ? bytes
        : bytes.sublist(0, length.toInt());
  }

  Future<void> _finish(
    HttpResponse response,
    int status, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    response.statusCode = status;
    for (final entry in headers.entries) {
      response.headers.set(entry.key, entry.value);
    }
    await response.close();
  }
}

final class MediaStreamLifecycleOwner with WidgetsBindingObserver {
  MediaStreamLifecycleOwner._(this.server);

  static MediaStreamLifecycleOwner? _processOwner;
  static Future<MediaStreamLifecycleOwner>? _processStart;

  final MediaStreamServer server;
  bool _disposed = false;

  static Future<MediaStreamLifecycleOwner> start({
    MediaStreamServer? server,
  }) async {
    final selectedServer = server ?? MediaStreamServer.instance;
    if (!identical(selectedServer, MediaStreamServer.instance)) {
      return _startOwner(selectedServer, retainForProcess: false);
    }
    final existing = _processOwner;
    if (existing != null && !existing._disposed) {
      return existing;
    }
    return _processStart ??= _startOwner(
      selectedServer,
      retainForProcess: true,
    );
  }

  static Future<MediaStreamLifecycleOwner> _startOwner(
    MediaStreamServer server, {
    required bool retainForProcess,
  }) async {
    try {
      final owner = MediaStreamLifecycleOwner._(server);
      await server.start();
      WidgetsBinding.instance.addObserver(owner);
      if (retainForProcess) _processOwner = owner;
      return owner;
    } finally {
      if (retainForProcess) _processStart = null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_processOwner, this)) _processOwner = null;
    await server.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_disposed && state == AppLifecycleState.detached) {
      unawaited(dispose());
    }
  }
}
