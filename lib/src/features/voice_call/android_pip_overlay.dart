import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'android_call_presentation.dart';
import 'call_video_stage.dart';

/// Above the entire root Navigator, including modal routes and their barriers.
/// Offstage preserves dialogs and drafts until the Activity returns from PiP.
class AndroidPipOverlay extends ConsumerStatefulWidget {
  const AndroidPipOverlay({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AndroidPipOverlay> createState() => _AndroidPipOverlayState();
}

class _AndroidPipOverlayState extends ConsumerState<AndroidPipOverlay> {
  AndroidCallPresentation? _presentation;
  Size? _appSize;
  MediaQueryData? _appMedia;

  @override
  void initState() {
    super.initState();
    _presentation = ref.read(androidCallPresentationProvider);
    _presentation?.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _presentation?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    if (presentation == null) return widget.child;
    final images = presentation.images;
    return LayoutBuilder(builder: (context, constraints) {
      if (!presentation.inPip) {
        _appSize = constraints.biggest;
        _appMedia = MediaQuery.of(context);
      }
      final size = _appSize ?? constraints.biggest;
      return Stack(fit: StackFit.expand, children: [
        Offstage(
            offstage: presentation.inPip,
            child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: MediaQuery(
                    data: _appMedia ?? MediaQuery.of(context),
                    child: widget.child))),
        if (presentation.inPip)
          Material(
              color: Colors.black,
              child: Center(
                  child: images == null
                      ? const SizedBox.shrink()
                      : CallVideoStage(
                          images: images,
                          peer: presentation.call?.peer ?? '',
                          remoteCamera:
                              presentation.call?.media?.remoteCamera == true,
                          alwaysVisible: true,
                          inset: false))),
      ]);
    });
  }
}
