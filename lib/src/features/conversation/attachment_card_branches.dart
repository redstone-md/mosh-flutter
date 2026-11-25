part of 'attachment_card.dart';

/// The Media card: a picture or a video shows its preview first, then its
/// name and size on one line. A press on the preview opens it. While the
/// file is arriving a ring over the preview shows how far it has come, and
/// stops the transfer when pressed; a transfer that stopped or failed
/// offers to pick it up again in the same place.
class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.attachment,
    required this.tone,
    required this.action,
    required this.onOpen,
  });

  final ConversationAttachment attachment;
  final MessageTone tone;
  final AttachmentAction? action;
  final VoidCallback onOpen;

  /// The disc a control stands on over a picture.
  static const double _disc = MoshSpace.s12;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final descriptor = attachment.descriptor;
    final failed = attachment.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: MoshSpace.s2,
      children: [
        _preview(context, l),
        // Set in as far as a message's text, so the file name and the text
        // under it start on one line.
        Padding(
          padding: MoshShapes.bubbleInset,
          child: Row(spacing: MoshSpace.s2, children: [
            Expanded(
                child: MiddleCutText(descriptor.fileName,
                    style: text.labelLarge!.copyWith(color: tone.ink))),
            Flexible(
                child: Text(
              attachmentDetail(attachment, l, failed: l.attachmentMediaFailed),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium!.copyWith(
                  color: failed ? tone.error : tone.quiet,
                  fontFeatures: kLiveNumberFontFeatures),
            )),
          ]),
        ),
      ],
    );
  }

  Widget _preview(BuildContext context, AppLocalizations l) {
    final colors = MoshColors.of(context);
    final descriptor = attachment.descriptor;
    final thumb = descriptor.thumbnailB64;
    // Decoded once per thumbnail and cached: list rebuilds must not re-run
    // base64 decoding on the UI thread. A malformed thumbnail yields empty
    // bytes, the decode fails and the broken-image fallback shows.
    final (:bytes, size: mediaSize) = decodeMiniature(thumb);
    final failed = attachment.failed;
    final transfer = action?.opens == false ? action : null;
    return Semantics(
      label: l.attachmentOpenAria(descriptor.fileName),
      image: true,
      button: true,
      child: GestureDetector(
        onTap: onOpen,
        // A narrower bubble scales the reserved height with the width.
        child: LayoutBuilder(
          builder: (context, constraints) => Container(
            width: double.infinity,
            height:
                attachmentPreviewHeight(mediaSize, width: constraints.maxWidth),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: failed ? colors.errorContainer : colors.tertiaryContainer,
              borderRadius: MoshShapes.attachment,
            ),
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                if (!failed) _previewImage(attachment, bytes, thumb ?? ''),
                if (transfer != null)
                  Center(child: _transferControl(context, transfer, l))
                else if (attachment.isVideo)
                  // Decorative: the preview itself is the open target.
                  Center(
                    child: ExcludeSemantics(
                      child: _onDisc(
                          colors,
                          Icon(MoshIcons.play,
                              size: MoshSpace.s6, color: colors.onSurface)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _onDisc(MoshColors colors, Widget child) => Container(
        width: _disc,
        height: _disc,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: colors.surface),
        child: child,
      );

  /// The ring of a running transfer, which a press stops, or the button
  /// that picks a stopped one up again.
  Widget _transferControl(
      BuildContext context, AttachmentAction transfer, AppLocalizations l) {
    final progress = attachment.progress;
    if (progress == null) {
      return Semantics(
        label: transfer.label,
        button: true,
        enabled: transfer.onPressed != null,
        child: IconButton(
          icon: Icon(transfer.glyph),
          tooltip: transfer.tooltip,
          onPressed: transfer.onPressed,
          style: moshTonalIconButtonStyle(MoshColors.of(context)),
        ),
      );
    }
    // The ring alone, as the card draws it, and a control like any other:
    // a keyboard reaches and presses it.
    return Tooltip(
      message: transfer.tooltip,
      child: Semantics(
        label: transfer.label,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: transfer.onPressed,
            child: SizedBox.square(
              dimension: MoshSpace.s10,
              child: CircularProgressIndicator(
                  value: progress.fraction,
                  strokeWidth: MoshSpace.s1,
                  semanticsLabel:
                      l.attachmentStateDownloading(progress.percent)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Try the original, then its clear JPEG, then the inline miniature.
Widget _previewImage(
    ConversationAttachment attachment, Uint8List bytes, String source) {
  Widget preview = Image(
    image: _boundedPreview(AttachmentMiniatureImage(bytes, source: source)),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    errorBuilder: (context, _, __) => Center(
      child: Icon(MoshIcons.imageBroken,
          size: MoshSpace.s8,
          color: MoshColors.of(context).onTertiaryContainer),
    ),
  );
  if (attachment.clearPreviewPath case final path?) {
    preview = _localPreview(path, preview, auxiliary: true);
  }
  if (attachment.isImage && attachment.localPath != null) {
    preview = _localPreview(attachment.localPath!, preview);
  }
  return preview;
}

Widget _localPreview(String path, Widget fallback, {bool auxiliary = false}) =>
    Image(
      image: _boundedPreview(auxiliary
          ? AttachmentPreviewFileImage(File(path))
          : FileImage(File(path))),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) =>
          synchronous || frame != null ? child : fallback,
      errorBuilder: (context, _, __) => fallback,
    );

/// Bound both decoded axes, including remote images with extreme aspect
/// ratios. Twice the widest card and the tallest preview, for dense screens.
ResizeImage _boundedPreview(ImageProvider<Object> provider) => ResizeImage(
      provider,
      width: (attachmentWidth(compact: false) * 2).toInt(),
      height: (kAttachmentPreviewMaxHeight * 2).toInt(),
      policy: ResizeImagePolicy.fit,
    );
