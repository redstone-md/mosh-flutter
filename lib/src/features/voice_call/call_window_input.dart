import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'call_video_frame.dart';

enum _Mode { prefix, line, header, body }

/// Separates bounded binary frames from existing newline control messages.
class CallWindowInput {
  CallWindowInput(Stream<List<int>> bytes, this.onFrame, {this.onProfile}) {
    _input = bytes.listen(_receive,
        onDone: _done,
        onError: (Object error, StackTrace trace) => _fail(error, trace));
  }
  final void Function(CallVideoFrame) onFrame;
  final void Function(Map<String, int>)? onProfile;
  Stopwatch? _transfer;
  int _copyMicros = 0;
  int _chunks = 0;
  final _lines = StreamController<String>();
  late final StreamSubscription<List<int>> _input;
  final _prefix = Uint8List(4);
  final _header = Uint8List(12);
  final _line = BytesBuilder();
  _Mode _mode = _Mode.prefix;
  int _offset = 0;
  int _metadataLength = 0;
  Uint8List? _body;
  bool _closed = false;
  Stream<String> get lines => _lines.stream;

  void _receive(List<int> bytes) {
    if (_closed) return;
    try {
      var position = 0;
      while (position < bytes.length) {
        position = switch (_mode) {
          _Mode.prefix => _readPrefix(bytes, position),
          _Mode.line => _readLine(bytes, position),
          _Mode.header => _readHeader(bytes, position),
          _Mode.body => _readBody(bytes, position),
        };
      }
    } catch (error, trace) {
      _fail(const FormatException('Invalid call window input'), trace);
    }
  }

  int _readPrefix(List<int> bytes, int position) {
    final byte = bytes[position++];
    if (byte == 10) {
      _lines.add(utf8.decode(_prefix.sublist(0, _offset)));
      _offset = 0;
      return position;
    }
    _prefix[_offset++] = byte;
    if (_offset != 4) return position;
    if (_prefix[0] == 77 &&
        _prefix[1] == 67 &&
        _prefix[2] == 70 &&
        _prefix[3] == 49) {
      _header.setRange(0, 4, _prefix);
      _mode = _Mode.header;
    } else {
      _line.add(_prefix);
      _offset = 0;
      _mode = _Mode.line;
    }
    return position;
  }

  int _readLine(List<int> bytes, int position) {
    final newline = bytes.indexOf(10, position);
    final end = newline < 0 ? bytes.length : newline;
    if (_line.length + end - position > 65536) {
      throw const FormatException('Control line too long');
    }
    _line.add(bytes.sublist(position, end));
    if (newline >= 0) {
      _lines.add(utf8.decode(_line.takeBytes()));
      _mode = _Mode.prefix;
    }
    return newline < 0 ? end : end + 1;
  }

  int _readHeader(List<int> bytes, int position) {
    final count = math.min(12 - _offset, bytes.length - position);
    _header.setRange(_offset, _offset + count, bytes, position);
    _offset += count;
    if (_offset == 12) {
      final header = ByteData.sublistView(_header);
      _metadataLength = header.getUint32(4);
      final length = header.getUint32(8);
      if (_metadataLength == 0 ||
          _metadataLength > CallVideoFrame.maximumMetadataBytes ||
          length == 0 ||
          length > CallVideoFrame.maximumBytes) {
        throw const FormatException('Frame length exceeds limit');
      }
      _body = Uint8List(_metadataLength + length);
      if (onProfile != null) {
        _transfer = Stopwatch()..start();
        _copyMicros = _chunks = 0;
      }
      _offset = 0;
      _mode = _Mode.body;
    }
    return position + count;
  }

  int _readBody(List<int> bytes, int position) {
    final body = _body!;
    final count = math.min(body.length - _offset, bytes.length - position);
    final copy = onProfile == null ? null : (Stopwatch()..start());
    body.setRange(_offset, _offset + count, bytes, position);
    _copyMicros += copy?.elapsedMicroseconds ?? 0;
    ++_chunks;
    _offset += count;
    if (_offset == body.length) {
      final frame = CallVideoFrame.decode(body, _metadataLength);
      _body = null;
      _offset = 0;
      _mode = _Mode.prefix;
      if (_transfer != null) {
        onProfile?.call({
          'copyUs': _copyMicros,
          'bodyUs': _transfer!.elapsedMicroseconds,
          'chunks': _chunks
        });
      }
      onFrame(frame);
    }
    return position + count;
  }

  void _done() {
    if (!_closed && (_mode != _Mode.prefix || _offset != 0)) {
      _lines.addError(const FormatException('Truncated call window input'));
    }
    _closed = true;
    unawaited(_lines.close());
  }

  void _fail(Object error, StackTrace trace) {
    if (_closed) return;
    _lines.addError(error, trace);
    _closed = true;
    unawaited(_input.cancel());
    unawaited(_lines.close());
  }

  Future<void> dispose() async {
    _closed = true;
    _body = null;
    await _input.cancel();
    await _lines.close();
  }
}
