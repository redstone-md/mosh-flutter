import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';

import 'qr_image.dart';

enum _CameraFailure { denied, unavailable }

/// The scanner owns camera lifecycle and permissions. URI validation stays native.
///
/// Frames come from the platform camera (CameraX on Android) and are decoded
/// by zxing2, so the scanner needs no Google Play Services.
class DeviceQrScanner extends StatefulWidget {
  const DeviceQrScanner({super.key});

  @override
  State<DeviceQrScanner> createState() => _DeviceQrScannerState();
}

class _DeviceQrScannerState extends State<DeviceQrScanner>
    with WidgetsBindingObserver {
  CameraController? _camera;
  _CameraFailure? _failure;
  bool _decoding = false;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _camera = null;
    super.dispose();
  }

  /// The camera plugin leaves lifecycle to the app: release the camera when
  /// Mosh leaves the foreground and open it again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && _camera != null) {
      final camera = _camera!;
      setState(() => _camera = null);
      camera.dispose();
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        _failure == null) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return _fail(_CameraFailure.unavailable);
      final camera = CameraController(
          cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first),
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420);
      _camera = camera;
      await camera.initialize();
      // The app may have left the foreground while the camera opened.
      if (!mounted || _camera != camera) return;
      await camera.startImageStream(_scan);
      setState(() {});
    } on CameraException catch (error) {
      _fail(error.code == 'CameraAccessDenied'
          ? _CameraFailure.denied
          : _CameraFailure.unavailable);
    }
  }

  void _fail(_CameraFailure failure) {
    if (mounted) setState(() => _failure = failure);
  }

  /// Decodes one frame at a time; frames that arrive meanwhile are dropped.
  Future<void> _scan(CameraImage image) async {
    if (_decoding || _returned) return;
    _decoding = true;
    final luma = image.planes.first;
    final uri = await decodeQrFrame(QrFrame(luma.bytes,
        width: image.width, height: image.height, rowStride: luma.bytesPerRow));
    _decoding = false;
    if (uri == null || uri.isEmpty || _returned || !mounted) return;
    _returned = true;
    Navigator.of(context).pop(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: Text(l.deviceLinkScan)),
      body: Column(children: [
        Expanded(
            child: switch (_failure) {
          _CameraFailure.denied => _message(l.deviceLinkCameraDenied),
          _CameraFailure.unavailable => _message(l.deviceLinkCameraUnavailable),
          null => camera != null && camera.value.isInitialized
              ? Center(child: CameraPreview(camera))
              : const SizedBox.expand(),
        }),
        _help(l),
      ]),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  Widget _help(AppLocalizations l) => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(l.deviceLinkScanHint, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.deviceLinkCameraFallback)),
              ]),
            ),
          ),
        ),
      );
}
