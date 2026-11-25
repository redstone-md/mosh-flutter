import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show
        MoshColors,
        MoshLevel,
        kLiveNumberFontFeatures,
        moshTonalIconButtonStyle;

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart' show VideoPlayer;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/features/shared/attachment_media_src.dart';
import 'package:mosh/src/features/shared/attachment_save.dart';
import 'package:mosh/src/features/shared/media_player.dart';
import 'package:mosh/src/features/shared/system_player.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

part 'media_viewer_controls.dart';
part 'media_viewer_stages.dart';

/// The Media viewer card: the whole window on the lowest tone, so nothing
/// competes with the picture. The file's name and who sent it sit in a bar
/// at the top with the two things to do: save it and close. A sound gets a
/// player; what Mosh cannot show says so and offers to save the file.
///
/// Construct directly and pass to `showDialog`, or use [showMediaViewer],
/// which wires [onClose] to `Navigator.pop` and [onSave] to the system's
/// save dialog.
class MediaViewer extends StatelessWidget {
  const MediaViewer({
    super.key,
    required this.descriptor,
    required this.src,
    required this.onClose,
    this.sent,
    this.onSave,
    this.createPlayer = createMediaPlayer,
  });

  /// The attachment's metadata: its mime picks the stage, its file name is
  /// the title and the semantics label.
  final AttachmentDescriptor descriptor;

  final String src;

  /// Who sent the file and when, the second line of the bar.
  final String? sent;

  /// Invoked by the close button and by a press beside the media.
  final VoidCallback onClose;

  /// Saves a copy of the file. Null while there is nothing to save yet: a
  /// file still arriving.
  final VoidCallback? onSave;

  /// Makes the player of a video or audio attachment; tests pass their own.
  final MediaPlayerFactory createPlayer;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: MoshMotion.effectsDefault.duration,
      curve: MoshMotion.effectsDefault.curve,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      // The dialog route already scopes the modal; the label names it.
      child: Semantics(
        container: true,
        label: descriptor.fileName,
        child: ModalFocusTrap(
          child: Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: colors.surfaceContainerLowest,
            elevation: 0,
            shape: const RoundedRectangleBorder(),
            // A press beside the media closes the viewer.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: SafeArea(
                child: Column(children: [
                  _ViewerBar(
                    fileName: descriptor.fileName,
                    sent: sent,
                    onSave: onSave,
                    onClose: onClose,
                  ),
                  Expanded(
                    child: _MediaStage(
                      descriptor: descriptor,
                      src: src,
                      onSave: onSave,
                      createPlayer: createPlayer,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar at the top of the viewer: the file's name over who sent it, then
/// save and close.
class _ViewerBar extends StatelessWidget {
  const _ViewerBar({
    required this.fileName,
    required this.sent,
    required this.onSave,
    required this.onClose,
  });

  final String fileName;
  final String? sent;
  final VoidCallback? onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = MoshColors.of(context);
    final text = Theme.of(context).textTheme;
    // A press on the bar is not a press beside the media.
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
            MoshSpace.s5, MoshSpace.s2, MoshSpace.s2, MoshSpace.s2),
        child: Row(spacing: MoshSpace.s2, children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: colors.onSurface)),
                if (sent != null)
                  Text(sent!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            tooltip: l.mediaViewerSave,
            onPressed: onSave,
            icon: const Icon(MoshIcons.download),
          ),
          IconButton(
            tooltip: l.closeViewer,
            onPressed: onClose,
            icon: const Icon(MoshIcons.close),
          ),
        ]),
      ),
    );
  }
}

/// The media in the middle of the viewer. A press on it does not close the
/// viewer. Its mime picks what it shows: a picture, a video, a player for a
/// sound, or the note that there is no preview.
class _MediaStage extends StatelessWidget {
  const _MediaStage({
    required this.descriptor,
    required this.src,
    required this.onSave,
    required this.createPlayer,
  });

  final AttachmentDescriptor descriptor;
  final String src;
  final VoidCallback? onSave;
  final MediaPlayerFactory createPlayer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final side = MoshControl.touch(Theme.of(context).platform)
        ? MoshSpace.s3
        : MoshSpace.s6;
    final media = GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: switch (attachmentMediaKind(descriptor.mime)) {
        AttachmentMediaKind.image =>
          _ImageStage(descriptor: descriptor, src: src),
        AttachmentMediaKind.video => _PlayingStage(
            src: src,
            createPlayer: createPlayer,
            builder: _videoPicture,
            unavailable: _Unavailable(
              icon: MoshIcons.video,
              title: l.mediaViewerVideoUnavailable,
              line: l.mediaViewerVideoUnavailableHint,
              onSave: onSave,
            ),
          ),
        AttachmentMediaKind.audio => _PlayingStage(
            src: src,
            createPlayer: createPlayer,
            builder: (player) => _AudioCard(player: player),
            unavailable: _Unavailable(
              icon: MoshIcons.playCircle,
              title: l.mediaViewerAudioUnavailable,
              line: l.mediaViewerAudioUnavailableHint,
              onSave: onSave,
            ),
          ),
        AttachmentMediaKind.file => _Unavailable(
            icon: MoshIcons.file,
            title: l.mediaViewerNoPreview,
            line: l.mediaViewerNoPreviewHint,
            onSave: onSave,
          ),
      },
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 0, side, MoshSpace.s6),
      child: Center(child: media),
    );
  }
}

/// A picture, whole inside the stage.
class _ImageStage extends StatelessWidget {
  const _ImageStage({required this.descriptor, required this.src});

  final AttachmentDescriptor descriptor;
  final String src;

  /// A downloaded attachment is a `file://` URL (see `localFileSrc`), which
  /// `NetworkImage` cannot fetch: `HttpClient` rejects the scheme and the
  /// stage would show the broken-image fallback for every local picture.
  ImageProvider get _image {
    final uri = Uri.parse(src);
    return uri.scheme == 'file'
        ? FileImage(File(uri.toFilePath()))
        : NetworkImage(src);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius:
            const BorderRadius.all(Radius.circular(MoshRadius.medium)),
        child: Image(
          image: _image,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: descriptor.fileName,
          errorBuilder: (context, error, stackTrace) => Icon(
            MoshIcons.imageBroken,
            size: MoshSpace.s12,
            color: MoshColors.of(context).onSurfaceVariant,
          ),
        ),
      );
}

/// Shows a [MediaViewer] as a fullscreen modal: the close button, a press
/// beside the media and Esc all pop the route. [sent] says who sent the file
/// and when.
///
/// A file that is on this device can be saved as a copy. [localPath] says
/// where it is at the moment Save is pressed, so a file that was still
/// arriving when the viewer opened can be saved once it is here; until then
/// Save says that it is still downloading. Without [localPath] only a
/// `file://` [src] can be saved.
Future<void> showMediaViewer({
  required BuildContext context,
  required AttachmentDescriptor descriptor,
  required String src,
  String? sent,
  String? Function()? localPath,
}) {
  final l = AppLocalizations.of(context)!;
  final toaster = context.toaster;
  final saver = ProviderScope.containerOf(context, listen: false)
      .read(attachmentSaverProvider);
  final uri = Uri.parse(src);
  final opened = uri.scheme == 'file' ? uri.toFilePath() : null;
  // One save dialog at a time, however often the button is pressed.
  var saving = false;
  Future<void> save() async {
    if (saving) return;
    final path = localPath?.call() ?? opened;
    if (path == null) return toaster.show(l.mediaViewerSaveArriving);
    saving = true;
    await saveAttachmentAs(
        saver: saver,
        toaster: toaster,
        l: l,
        localPath: path,
        fileName: descriptor.fileName);
    saving = false;
  }

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l.closeViewer,
    builder: (dialogContext) => MediaViewer(
      descriptor: descriptor,
      src: src,
      sent: sent,
      onClose: () => Navigator.of(dialogContext).pop(),
      onSave:
          localPath == null && opened == null ? null : () => unawaited(save()),
    ),
  );
}
