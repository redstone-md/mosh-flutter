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
final class MediaRange {
  const MediaRange({required this.start, this.end, this.isDefault = false});

  final BigInt start;
  final BigInt? end;
  final bool isDefault;

  BigInt resolveEndExclusive() {
    final requestedEnd = end == null ? null : end! + BigInt.one;
    final windowEnd = (start + _maxWindowBigInt) > _maxU64
        ? _maxU64
        : start + _maxWindowBigInt;
    return requestedEnd == null || requestedEnd > windowEnd
        ? windowEnd
        : requestedEnd;
  }
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
      if (request.method != 'GET' && request.method != 'HEAD') {
        await _finish(
          request.response,
          HttpStatus.methodNotAllowed,
          headers: {'allow': 'GET, HEAD'},
        );
        return;
      }
      final route = MediaStreamRoute.parse(request.uri);
      if (route == null) {
        await _finish(request.response, HttpStatus.notFound);
        return;
      }
      final rangeHeaderValues = request.headers[HttpHeaders.rangeHeader];
      String? rangeHeader;
      var hasMultipleRanges = false;
      if (rangeHeaderValues != null && rangeHeaderValues.isNotEmpty) {
        if (rangeHeaderValues.length == 1) {
          rangeHeader = rangeHeaderValues[0];
        } else {
          hasMultipleRanges = true;
        }
      }
      final range = parseMediaRange(rangeHeader);
      if (hasMultipleRanges || range == null) {
        await _finish(
          request.response,
          HttpStatus.requestedRangeNotSatisfiable,
        );
        return;
      }

      final deadline = DateTime.now().add(_pollTimeout);
      final end = range.resolveEndExclusive();
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        AttachmentStreamRange result;
        try {
          result = await _fetchRange(
            kind: route.kind,
            host: route.host,
            attachmentId: route.attachmentId,
            start: range.start,
            end: end,
          ).timeout(remaining);
        } on TimeoutException {
          await _finish(request.response, HttpStatus.gatewayTimeout);
          return;
        } catch (_) {
          await _finish(request.response, HttpStatus.notFound);
          return;
        }
        switch (result.state) {
          case AttachmentStreamState.ready:
            await _writeReady(
              request,
              range,
              result.bytes,
              result.totalSize,
              result.mime,
            );
            return;
          case AttachmentStreamState.pending:
            if (range.start >= result.totalSize) {
              await _finish(
                request.response,
                HttpStatus.requestedRangeNotSatisfiable,
                headers: {'content-range': 'bytes */${result.totalSize}'},
              );
              return;
            }
            final wait = deadline.difference(DateTime.now());
            if (wait <= Duration.zero) break;
            await Future<void>.delayed(
              wait < _pollInterval ? wait : _pollInterval,
            );
            continue;
          case AttachmentStreamState.unknown:
            await _finish(request.response, HttpStatus.notFound);
            return;
        }
      }
      await _finish(request.response, HttpStatus.gatewayTimeout);
    } catch (_) {
      try {
        await _finish(request.response, HttpStatus.notFound);
      } catch (_) {
        // The client may have disconnected while the fetch was in flight.
      }
    }
  }

  Future<void> _writeReady(
    HttpRequest request,
    MediaRange range,
    List<int> bytes,
    BigInt totalSize,
    String mime,
  ) async {
    final start = range.start;
    final isEmptyAttachment = totalSize == BigInt.zero && start == BigInt.zero;
    if (isEmptyAttachment && !range.isDefault) {
      await _finish(
        request.response,
        HttpStatus.requestedRangeNotSatisfiable,
        headers: {'content-range': 'bytes */$totalSize'},
      );
      return;
    }
    if (!isEmptyAttachment &&
        (start >= totalSize || range.end != null && range.end! < range.start)) {
      await _finish(
        request.response,
        HttpStatus.requestedRangeNotSatisfiable,
        headers: {'content-range': 'bytes */$totalSize'},
      );
      return;
    }
    final requestedEndExclusive = range.resolveEndExclusive();
    final effectiveEndExclusive = requestedEndExclusive < totalSize
        ? requestedEndExclusive
        : totalSize;
    final expectedLength = effectiveEndExclusive - start;
    if (isEmptyAttachment) {
      if (bytes.isNotEmpty) {
        await _finish(request.response, HttpStatus.notFound);
        return;
      }
    } else if (BigInt.from(bytes.length) < expectedLength) {
      await _finish(request.response, HttpStatus.notFound);
      return;
    }
    var length = bytes.length;
    if (expectedLength < BigInt.from(length)) {
      length = expectedLength.toInt();
    }
    final body = length == bytes.length ? bytes : bytes.sublist(0, length);
    final last = length == 0
        ? range.start
        : range.start + BigInt.from(length) - BigInt.one;
    final response = request.response;
    response.statusCode = HttpStatus.partialContent;
    response.headers
      ..set('content-type', mime.isEmpty ? 'application/octet-stream' : mime)
      ..set('accept-ranges', 'bytes')
      ..set('content-range', 'bytes ${range.start}-$last/$totalSize')
      ..contentLength = length;
    if (request.method == 'GET') response.add(body);
    await response.close();
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
