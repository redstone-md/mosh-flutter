import 'package:mosh/src/features/shared/attachment_launcher.dart';

final class RecordingAttachmentLauncher implements AttachmentLauncher {
  RecordingAttachmentLauncher({this.error});

  final Object? error;
  final List<String> paths = [];

  @override
  Future<void> open(String localPath) async {
    paths.add(localPath);
    if (error != null) throw error!;
  }
}
