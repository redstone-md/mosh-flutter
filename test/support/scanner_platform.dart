import 'dart:async';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:zxing2/qrcode.dart';

/// Camera hardware seam only. Frames are decoded by the real QR reader and
/// device authorization still uses the real bridge.
class ScannerPlatform extends CameraPlatform {
  ScannerPlatform({this.errorCode, this.cameras = const [_back]});

  /// The platform error `initialize` fails with, e.g. `CameraAccessDenied`.
  final String? errorCode;
  final List<CameraDescription> cameras;
  final frames = StreamController<CameraImageData>.broadcast();
  int starts = 0;
  int releases = 0;

  static const _back = CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90);

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
      CameraDescription description, MediaSettings? settings) async {
    starts++;
    if (errorCode != null) throw CameraException(errorCode!, null);
    return starts;
  }

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(
          cameraId, 640, 480, ExposureMode.auto, false, FocusMode.auto, false));

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId,
          {CameraImageStreamOptions? options}) =>
      frames.stream;

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<void> dispose(int cameraId) async => releases++;
}

/// A YUV camera frame showing [text] as a QR code. Rows are padded past the
/// visible width, as Android cameras often deliver them.
CameraImageData qrCameraFrame(String text) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.l).matrix!;
  const scale = 4, margin = 16;
  final width = matrix.width * scale + 2 * margin;
  final stride = width + 32;
  final luma = Uint8List(stride * width)..fillRange(0, stride * width, 255);
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) != 1) continue;
      for (var dy = 0; dy < scale; dy++) {
        final row = (margin + y * scale + dy) * stride + margin + x * scale;
        luma.fillRange(row, row + scale, 0);
      }
    }
  }
  return _frame(luma, width, stride);
}

/// A frame without any QR code in view.
CameraImageData blankCameraFrame() =>
    _frame(Uint8List(320 * 240)..fillRange(0, 320 * 240, 200), 320, 320);

CameraImageData _frame(Uint8List luma, int width, int stride) =>
    CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        width: width,
        height: luma.length ~/ stride,
        planes: [CameraImagePlane(bytes: luma, bytesPerRow: stride)]);
