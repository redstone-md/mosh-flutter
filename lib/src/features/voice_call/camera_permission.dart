import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Desktop capture requests its OS permission; Android must ask before opening.
Future<bool> requestCallCamera() async {
  if (!Platform.isAndroid) return true;
  try {
    return await const MethodChannel('app.mosh/call_permissions')
            .invokeMethod<bool>('camera') ??
        false;
  } on PlatformException {
    return false;
  }
}
