import 'dart:typed_data' show Int8List;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

const _maxImageBytes = 10 * 1024 * 1024;
const _maxPixels = 16 * 1024 * 1024;
const _invalidQrImage = 'Invalid QR image';

/// The luminance (Y) plane of one camera frame. Rows are [rowStride] bytes
/// apart, which can exceed [width] when the camera pads them.
@immutable
class QrFrame {
  const QrFrame(this.luma,
      {required this.width, required this.height, required this.rowStride});
  final Uint8List luma;
  final int width;
  final int height;
  final int rowStride;
}

/// Decode a desktop QR image off the UI thread.
Future<String> decodeDeviceQr(Uint8List bytes) => compute(_decode, bytes);

/// The QR text in a camera frame, or null when the frame holds none.
Future<String?> decodeQrFrame(QrFrame frame) => compute(_decodeFrame, frame);

String? _decodeFrame(QrFrame frame) {
  try {
    return _read(_FrameLuminance(frame));
  } on ReaderException {
    return null;
  }
}

/// zxing2 reads the camera's Y plane directly; it does not export a source
/// for planes with padded rows.
class _FrameLuminance extends LuminanceSource {
  _FrameLuminance(this._frame) : super(_frame.width, _frame.height);
  final QrFrame _frame;

  @override
  Int8List getRow(int y, Int8List? row) {
    final start = y * _frame.rowStride;
    return (row != null && row.length >= width ? row : Int8List(width))
      ..setRange(0, width, _frame.luma, start);
  }

  @override
  Int8List getMatrix() {
    final matrix = Int8List(width * height);
    for (var y = 0; y < height; y++) {
      matrix.setRange(
          y * width, (y + 1) * width, _frame.luma, y * _frame.rowStride);
    }
    return matrix;
  }
}

String _decode(Uint8List bytes) {
  if (bytes.length > _maxImageBytes) {
    throw const FormatException(_invalidQrImage);
  }
  try {
    return _decodeImage(bytes);
  } on ReaderException {
    throw const FormatException(_invalidQrImage);
  } on RangeError {
    throw const FormatException(_invalidQrImage);
  }
}

String _decodeImage(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > _maxPixels) {
    throw const FormatException(_invalidQrImage);
  }
  final image = decoder!.decodeFrame(0);
  if (image == null) throw const FormatException(_invalidQrImage);
  final pixels =
      image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr);
  final source = RGBLuminanceSource(
      image.width,
      image.height,
      pixels.buffer
          .asInt32List(pixels.offsetInBytes, pixels.lengthInBytes ~/ 4));
  try {
    return _read(source);
  } on ReaderException {
    // Clean desktop screenshots can be sampled without perspective detection.
    return QRCodeReader()
        .decode(BinaryBitmap(HybridBinarizer(source)),
            hints: DecodeHints()..put(DecodeHintType.pureBarcode))
        .text;
  }
}

String _read(LuminanceSource source) => QRCodeReader()
    .decode(BinaryBitmap(HybridBinarizer(source)),
        hints: DecodeHints()..put(DecodeHintType.tryHarder))
    .text;
