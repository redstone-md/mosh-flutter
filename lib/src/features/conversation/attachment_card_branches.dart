part of 'attachment_card.dart';

/// Renders the image/video media preview: the decoded base64 thumbnail as
/// a tappable `Image.memory` (rounded, height-constrained) above the
/// shared name+meta+progress bar + actions row.
///
/// The preview opens media, with transfer controls alongside the caption.
/// The video play-overlay is decorative; the wrapper labels the open action.
class _MediaPreviewCard extends StatelessWidget {
  const _MediaPreviewCard({
    required this.attachment,
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
    this.messageFooter,
  });

  final ConversationAttachment attachment;
  final bool busy;
  final Widget? messageFooter;
  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final descriptor = attachment.descriptor;
    final thumb = descriptor.thumbnailB64;
    final localPath = attachment.localImagePreview;
    // A malformed server thumbnail must never take the conversation down:
    // base64Decode throws during build, which errorBuilder cannot catch.
    // Empty bytes on decode failure -> Image.memory's decode fails ->
    // errorBuilder renders the broken-image fallback.
    var bytes = Uint8List(0);
    try {
      if (thumb != null) bytes = base64Decode(thumb);
    } catch (_) {
      // malformed thumbnail: broken-image fallback below
    }
    // Drives the centered play-overlay on top of the thumbnail image.
    final isVideo = descriptor.mime.startsWith('video/');
    final previewLabel = l.attachmentOpenAria(descriptor.fileName);

    return _FileCardShell(
      failed: attachment.failed,
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
              // The bubble supplies the surface beneath transparent images.
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                constraints: const BoxConstraints(
                  minHeight: kAttachmentPreviewMinHeight,
                  maxHeight: kAttachmentPreviewMaxHeight,
                ),
                decoration: const BoxDecoration(
                  color: MoshColors.line,
                  borderRadius: MoshShapes.attachment,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image(
                      // Empty only when the base64 thumbnail was
                      // malformed; the errorBuilder renders the
                      // broken-image fallback in that case.
                      image: localPath != null
                          ? ResizeImage.resizeIfNeeded(
                              640, null, FileImage(File(localPath)))
                          : MemoryImage(bytes),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, _, __) => const SizedBox(
                        height: kAttachmentPreviewMinHeight,
                        width: double.infinity,
                        child: ColoredBox(
                          color: MoshColors.line,
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
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Controls precede time in the metadata row so its trailing
          // position stays fixed. The bubble supplies the bottom inset.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                10, 8, MoshShapes.attachmentFooterInset, 0),
            child: _buildBar(
              l: l,
              fileName: descriptor.fileName,
              totalSize: descriptor.totalSize,
              attachment: attachment,
              messageFooter: messageFooter,
              action: attachment.transferControl(busy: busy) != null
                  ? AttachmentActions(
                      attachment: attachment,
                      busy: busy,
                      onDownload: onDownload,
                      onCancel: onCancel,
                      l: l,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
