// Immutable attachment-open intents shared by the DM, channel, and group
// orchestration paths. Screens interpret these intents and own the UI or
// platform side effect.
library;

import 'package:mosh/src/rust/conversation/attachments.dart';

sealed class AttachmentOpenIntent {
  const AttachmentOpenIntent();
}

final class AttachmentNoopOpenIntent extends AttachmentOpenIntent {
  const AttachmentNoopOpenIntent();
}

final class AttachmentMediaOpenIntent extends AttachmentOpenIntent {
  const AttachmentMediaOpenIntent({
    required this.descriptor,
    required this.src,
  });

  final AttachmentDescriptor descriptor;
  final String src;
}

final class AttachmentExternalOpenIntent extends AttachmentOpenIntent {
  const AttachmentExternalOpenIntent({required this.localPath});

  final String localPath;
}
