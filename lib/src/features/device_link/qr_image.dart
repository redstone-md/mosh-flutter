import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

const _maxImageBytes = 10 * 1024 * 1024;
const _maxPixels = 16 * 1024 * 1024;
const _invalidQrImage = 'Invalid QR image';

/// Decode a desktop QR image off the UI thread.
Future<String> decodeDeviceQr(Uint8List bytes) => compute(_decode, bytes);

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
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  final bitmap = BinaryBitmap(HybridBinarizer(source));
  final reader = QRCodeReader();
  try {
    return reader.decode(bitmap, hints: hints).text;
  } on ReaderException {
    // Clean desktop screenshots can be sampled without perspective detection.
    return reader
        .decode(bitmap, hints: DecodeHints()..put(DecodeHintType.pureBarcode))
        .text;
  }
}
