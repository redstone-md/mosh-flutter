// Branch widgets of the [AttachmentCard]: the image/video media-preview
// card. A `part` of attachment_card.dart so the branch stays
// library-private while the file stays under the 400-line repo cap.
part of 'attachment_card.dart';

/// Renders the image/video media preview: the decoded base64 thumbnail as
/// a tappable `Image.memory` (rounded, height-constrained) above the
/// shared name+meta+progress bar + actions row.
///
/// IN SCOPE: the onOpen tap (a `GestureDetector` opens the local file) and
/// the actions row ([AttachmentActions] to the right of the bar). The
/// video play-overlay is decorative (`Semantics(excludeSemantics: true)`);
/// the wrapper uses the localized open attachment action as its semantics
/// label.
class _MediaPreviewCard extends StatelessWidget {
  const _MediaPreviewCard({
    required this.descriptor,
    required this.view,
    required this.own,
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  final AttachmentDescriptor descriptor;
  final AttachmentView? view;
  final bool own;
  final bool busy;
  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final outgoing = view?.direction == 'outgoing' || (view == null && own);
    final state = view?.state ??
        (outgoing ? AttachmentState.available : AttachmentState.offered);
    final percent = _progressPercent(view);
    final failed = state == AttachmentState.failed;
    final thumb = descriptor.thumbnailB64!;
    final bytes = Uint8List.fromList(base64Decode(thumb));
    // Drives the centered play-overlay on top of the thumbnail image.
    final isVideo = descriptor.mime.startsWith('video/');
    final previewLabel = l.attachmentOpenAria(descriptor.fileName);

    return _FileCardShell(
      failed: failed,
      theme: theme,
      media: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The preview is tappable (opens the local file) with the
          // localized open-attachment action. The video play-overlay is
          // decorative and stays on top.
          Semantics(
            label: previewLabel,
            image: true,
            button: true,
            child: GestureDetector(
              onTap: () => onOpen(descriptor),
              // Full-width bg-0 preview box; the shell already clips the
              // corners.
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: kAttachmentPreviewMinHeight,
                  maxHeight: kAttachmentPreviewMaxHeight,
                ),
                color: MoshColors.bg0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.memory(
                      bytes,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, _, __) => const SizedBox(
                        height: kAttachmentPreviewMinHeight,
                        width: double.infinity,
                        child: ColoredBox(
                          color: MoshColors.bg3,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 32,
                            color: MoshColors.fg3,
                          ),
                        ),
                      ),
                    ),
                    if (isVideo)
                      // 48px round dark play badge -- decorative, so no
                      // semantics.
                      Semantics(
                        excludeSemantics: true,
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MoshColors.bg0.withValues(alpha: 0.62),
                          ),
                          child: const Icon(Icons.play_arrow,
                              size: 24, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Bar row: info (expanding) + actions to its right. The media
          // shell itself has no padding, so the bar carries it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildBar(
                    l: l,
                    fileName: descriptor.fileName,
                    totalSize: descriptor.totalSize,
                    state: state,
                    percent: percent,
                  ),
                ),
                const SizedBox(width: 10),
                AttachmentActions(
                  descriptor: descriptor,
                  view: view,
                  state: state,
                  outgoing: outgoing,
                  busy: busy,
                  onDownload: onDownload,
                  onCancel: onCancel,
                  onOpen: onOpen,
                  l: l,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
