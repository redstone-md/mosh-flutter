import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/l10n/app_localizations.dart';

import 'call_video_renderer.dart';

/// Presentation only. Pixel changes never animate; stage presence may fade.
class CallVideoStage extends StatelessWidget {
  const CallVideoStage({super.key, required this.images, required this.peer});
  final ValueListenable<CallVideoImages> images;
  final String peer;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CallVideoImages>(
        valueListenable: images,
        builder: (context, images, _) => AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: images.remote == null && images.local == null
              ? const SizedBox.shrink(key: ValueKey(false))
              : _stage(context, images),
        ),
      );

  Widget _stage(BuildContext context, CallVideoImages images) {
    final remote = images.remote;
    final preview = images.local;
    final l = AppLocalizations.of(context)!;
    return Padding(
      key: const ValueKey(true),
      padding: const EdgeInsets.only(top: 12),
      child: AspectRatio(
          aspectRatio: 16 / 9,
          child: RepaintBoundary(
              child: ColoredBox(
                  color: MoshColors.bg0,
                  child: Stack(fit: StackFit.expand, children: [
                    _picture(
                        remote ?? preview!,
                        remote != null
                            ? l.callRemoteVideo(peer)
                            : l.callLocalPreview,
                        mirrored: remote == null),
                    if (remote != null && preview != null)
                      _preview(preview, l.callLocalPreview),
                  ])))),
    );
  }

  Widget _preview(ui.Image image, String label) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: FractionallySizedBox(
                widthFactor: .25,
                child: AspectRatio(
                    aspectRatio: image.width / image.height,
                    child: _picture(image, label, mirrored: true)))),
      );

  Widget _picture(ui.Image image, String label, {required bool mirrored}) =>
      Semantics(
          label: label,
          image: true,
          child: Transform.flip(
              flipX: mirrored,
              child: RawImage(image: image, fit: BoxFit.contain)));
}
