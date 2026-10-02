import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera hardware seam only. Device authorization still uses the real bridge.
class ScannerPlatform extends MobileScannerPlatform {
  ScannerPlatform({this.error});
  final MobileScannerErrorCode? error;
  final captures = StreamController<BarcodeCapture?>.broadcast();
  int starts = 0;
  int stops = 0;
  bool disposed = false;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const SizedBox.expand();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (error != null) throw MobileScannerException(errorCode: error!);
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async => disposed = true;
}
