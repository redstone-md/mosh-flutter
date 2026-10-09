import 'package:record/record.dart';

/// Permission only; native WebRTC owns the microphone stream and processing.
Future<bool> requestCallMicrophone() async {
  final recorder = AudioRecorder();
  try {
    return await recorder.hasPermission();
  } catch (_) {
    return false;
  } finally {
    await recorder.dispose();
  }
}
