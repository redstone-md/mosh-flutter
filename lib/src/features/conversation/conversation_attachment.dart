import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/features/shared/attachment_open.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

import 'conversation_state.dart';

enum AttachmentTransferAction { download, retryDownload, retry, cancel }

/// Interprets one attachment for message cards, the file index and opening.
/// The runtime's failed/cancelled state takes precedence over cached paths.
class ConversationAttachment {
  /// [own] carries message ownership when no runtime transfer view exists.
  /// A supplied view remains authoritative about direction and readiness.
  const ConversationAttachment({
    required this.descriptor,
    AttachmentView? view,
    bool own = false,
  })  : _view = view,
        _own = own;

  final AttachmentDescriptor descriptor;
  final AttachmentView? _view;
  final bool _own;

  bool get outgoing =>
      _view?.direction == 'outgoing' || (_view == null && _own);

  AttachmentState get state =>
      _view?.state ??
      (outgoing ? AttachmentState.available : AttachmentState.offered);

  bool get failed => state == AttachmentState.failed;
  bool get viewable => isViewableMedia(descriptor.mime);

  String? get localPath {
    final path = _view?.localPath;
    return state == AttachmentState.available && path != null && path.isNotEmpty
        ? path
        : null;
  }

  String? get localImagePreview {
    if (descriptor.mime.startsWith('image/') && localPath != null) {
      return localPath;
    }
    return clearPreviewPath;
  }

  String? get clearPreviewPath {
    final preview = _view?.previewPath;
    final media = descriptor.mime.startsWith('image/') ||
        descriptor.mime.startsWith('video/');
    return media && preview != null && preview.isNotEmpty ? preview : null;
  }

  bool get hasMediaPreview {
    if (localImagePreview != null) return true;
    final thumbnail = descriptor.thumbnailB64;
    return thumbnail != null &&
        thumbnail.isNotEmpty &&
        (descriptor.mime.startsWith('image/') ||
            descriptor.mime.startsWith('video/'));
  }

  ({AttachmentTransferAction action, bool enabled})? transferControl(
      {required bool busy}) {
    if (outgoing) return null;
    final action = switch (state) {
      AttachmentState.offered => AttachmentTransferAction.download,
      AttachmentState.cancelled => AttachmentTransferAction.retryDownload,
      AttachmentState.failed => AttachmentTransferAction.retry,
      AttachmentState.downloading => AttachmentTransferAction.cancel,
      AttachmentState.available => null,
    };
    return action == null
        ? null
        : (
            action: action,
            enabled: action == AttachmentTransferAction.cancel || !busy
          );
  }

  /// Null means no transfer; a null fraction means its size is unknown.
  ({double? fraction, int percent})? get progress {
    if (state != AttachmentState.downloading) return null;
    final total = _view?.chunkCount ?? BigInt.zero;
    if (total <= BigInt.zero) return (fraction: null, percent: 0);
    final completed = _view?.completedChunks ?? BigInt.zero;
    final bounded = completed < BigInt.zero
        ? BigInt.zero
        : completed > total
            ? total
            : completed;
    return (
      fraction: bounded.toDouble() / total.toDouble(),
      percent: ((bounded * BigInt.from(100)) ~/ total).toInt(),
    );
  }

  ({AttachmentOpenIntent intent, bool download, bool wait}) openPlan(
      AnyConversationTarget target) {
    final path = localPath;
    if (path != null) {
      return (
        intent: viewable
            ? AttachmentMediaOpenIntent(
                descriptor: descriptor, src: localFileSrc(path))
            : AttachmentExternalOpenIntent(localPath: path),
        download: false,
        wait: false,
      );
    }
    if (!viewable || outgoing) {
      return (
        intent: const AttachmentNoopOpenIntent(),
        download: false,
        wait: false,
      );
    }
    final streamable = isStreamableMedia(descriptor.mime);
    return (
      intent: streamable
          ? AttachmentMediaOpenIntent(
              descriptor: descriptor,
              src: streamingMediaSrc(
                  target.kind.name, target.id, descriptor.attachmentId))
          : const AttachmentNoopOpenIntent(),
      download: state != AttachmentState.downloading,
      wait: !streamable,
    );
  }

  ConversationPendingOpen resolvePendingOpen() {
    if (state == AttachmentState.failed || state == AttachmentState.cancelled) {
      return const ConversationPendingDropped();
    }
    final path = localPath;
    return path == null
        ? const ConversationPendingNone()
        : ConversationPendingShow(descriptor, localFileSrc(path));
  }
}
