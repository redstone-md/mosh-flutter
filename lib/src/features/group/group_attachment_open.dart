import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// Immutable result used by the group screen when a pending media open is
/// resolved against a refreshed attachment snapshot.
sealed class GroupPendingResolution {
  const GroupPendingResolution();

  const factory GroupPendingResolution.show(
      AttachmentDescriptor descriptor, String src) = GroupPendingShow;
  const factory GroupPendingResolution.drop() = GroupPendingDrop;
  const factory GroupPendingResolution.none() = GroupPendingNone;
}

final class GroupPendingShow extends GroupPendingResolution {
  const GroupPendingShow(this.descriptor, this.src);

  final AttachmentDescriptor descriptor;
  final String src;
}

final class GroupPendingDrop extends GroupPendingResolution {
  const GroupPendingDrop();
}

final class GroupPendingNone extends GroupPendingResolution {
  const GroupPendingNone();
}
