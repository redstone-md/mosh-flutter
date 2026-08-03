/// Desktop drag-and-drop file attach -- the 1-в-1 port of React's
/// `ChatDropZone` (ChatComposer.tsx:8-43). Wraps the message list so a dropped
/// file ingests through the SAME `onAttach`/`onError` contract the paperclip
/// picker uses (DRY via [ingestAttachment]); React wraps `<div className=
/// chat-pane>` and on drop calls `onAttach(files[0])`.
//
// React structure (ChatDropZone.tsx): `onDragOver`/`onDragEnter` set `dragging`
// and preventDefault; `onDragLeave`/`onDrop` clear it; `onDrop` reads
// `e.dataTransfer.files[0]` and calls `onAttach(file)`. `disabled` (while a
// send is in flight) makes every handler a no-op so no overlay shows.
//
// Flutter port: built on `desktop_drop`'s `DropTarget` -- `onDragEntered`
// sets `dragging`, `onDragExited`/`onDragDone` clear it, `onDragDone` reads
// the first `DropItem` (a `cross_file` `XFile`), reads its bytes, runs them
// through [ingestAttachment] (50 MB ceiling), and hands a ready-to-send
// [PickedAttachment] to `onAttach` (or fires `onError(tooLarge)` -- same path
// the paperclip uses). The overlay is a `Stack` layer over `child` shown only
// while `dragging`: an 82%-opaque backdrop with a 2px dashed `--moss` border
// (React chat-pane.css:665-685) and centered `l.chatDropHint` text.
//
// Dashed border: React uses CSS `border: 2px dashed var(--moss)`. Flutter has
// no built-in dashed border; rather than pull a `dotted_border` package dep
// (not currently a dep), a tiny `CustomPainter` strokes the dashes. This
// matches React visually; `--moss` is `#B7D84A` (summary_card.dart).
library;

import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:desktop_drop/desktop_drop.dart'
    show DropDoneDetails, DropEventDetails, DropTarget;
import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart' show AppLocalizations;
import 'package:mosh/src/features/shared/attachment_picker.dart'
    show
        AttachmentPickError,
        AttachmentPickErrorCallback,
        AttachmentPickedCallback,
        ingestAttachment;

/// 50 MB attach ceiling -- mirrors React `ATTACHMENT_MAX_BYTES` and the
/// paperclip picker's default `maxBytes`.
const int kAttachmentMaxBytes = 50 * 1024 * 1024;

/// `--moss` accent (#B7D84A) -- sourced from summary_card.dart / mosh_title_bar.
const Color _kMoss = Color(0xFFB7D84A);

/// Wraps [child] (the message list) so a desktop file drop ingests through
/// the same `onAttach`/`onError` pair the paperclip uses.
///
/// Stateful because `dragging` (whether a file is hovering) is transient UI
/// state owned here, not by the screen. `disabled` mirrors React: while a
/// send is in flight the drop zone does not ingest and shows no overlay.
class ChatDropZone extends StatefulWidget {
  const ChatDropZone({
    super.key,
    required this.child,
    required this.disabled,
    required this.onAttach,
    required this.onError,
    this.maxBytes = kAttachmentMaxBytes,
  });

  final Widget child;
  final bool disabled;
  final AttachmentPickedCallback onAttach;
  final AttachmentPickErrorCallback onError;
  final int maxBytes;

  @override
  State<ChatDropZone> createState() => _ChatDropZoneState();
}

class _ChatDropZoneState extends State<ChatDropZone> {
  /// Whether a file is hovering over the zone (drives the overlay). Mirrors
  /// React's `dragging` state.
  bool _dragging = false;

  void _onDragEntered(DropEventDetails _) {
    if (widget.disabled) return; // React: no-op while disabled (no overlay)
    if (!_dragging) setState(() => _dragging = true);
  }

  void _onDragExited(DropEventDetails _) {
    if (_dragging) setState(() => _dragging = false);
  }

  Future<void> _onDragDone(DropDoneDetails detail) async {
    // Clear the overlay first so the UI is responsive while bytes read.
    if (_dragging) setState(() => _dragging = false);
    if (widget.disabled) return; // React: no-op while disabled (no ingest)
    if (detail.files.isEmpty) return;
    final xfile = detail.files.first;
    final Uint8List bytes;
    try {
      bytes = await xfile.readAsBytes();
    } on Exception {
      return; // unreadable file -- mirror React (drop silently ignored)
    }
    final picked = await ingestAttachment(
      bytes: bytes,
      fileName: xfile.name,
      maxBytes: widget.maxBytes,
    );
    if (picked != null) {
      widget.onAttach(picked);
    } else {
      widget.onError(AttachmentPickError.tooLarge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return DropTarget(
      // `enable=false` also stops the platform listener (per desktop_drop's
      // didUpdateWidget note) -- a stronger gate than the in-handler `disabled`
      // checks, which we ALSO keep so a drop started before disable no-ops.
      enable: !widget.disabled,
      onDragEntered: _onDragEntered,
      onDragExited: _onDragExited,
      onDragDone: _onDragDone,
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: _DropOverlay(
                  hint: l.chatDropHint,
                  scaffoldBg: theme.scaffoldBackgroundColor,
                  // bodyMedium is nullable in some SDKs; fall back to the
                  // default TextStyle so the overlay text always renders.
                  text: theme.textTheme.bodyMedium ?? const TextStyle(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The drag overlay: an 82%-opaque backdrop with a 2px dashed `--moss`
/// border and centered hint text (React chat-pane.css:665-685).
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({
    required this.hint,
    required this.scaffoldBg,
    required this.text,
  });

  final String hint;
  final Color scaffoldBg;
  final TextStyle text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: scaffoldBg.withValues(alpha: 0.82),
      child: Padding(
        // React offsets the border -8px from the pane edges; Flutter uses an
        // 8px inset so the dashes sit just inside the message list.
        padding: const EdgeInsets.all(8),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: _kMoss, strokeWidth: 2),
          child: Center(
            child: Semantics(
              label: hint,
              child: Text(
                hint,
                style: text.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Strokes a dashed rectangle border -- Flutter has no built-in dashed
/// border, so this tiny painter matches React's `border: 2px dashed`. Dashes
/// are 6px on / 4px off along the rect path (visual match, not pixel-exact).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    // Stroke each edge as its own dashed line so corner miters are clean.
    const dash = 6.0;
    const gap = 4.0;
    void dashedLine(Offset a, Offset b) {
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len == 0) return;
      final ux = dx / len;
      final uy = dy / len;
      var drawn = 0.0;
      var on = true;
      while (drawn < len) {
        final remaining = len - drawn;
        final step = on ? dash : gap;
        final next = drawn + (step < remaining ? step : remaining);
        if (on) {
          canvas.drawLine(
            Offset(a.dx + ux * drawn, a.dy + uy * drawn),
            Offset(a.dx + ux * next, a.dy + uy * next),
            paint,
          );
        }
        drawn = next;
        on = !on;
      }
    }

    final r = rect.deflate(strokeWidth / 2);
    dashedLine(r.topLeft, r.topRight);
    dashedLine(r.topRight, r.bottomRight);
    dashedLine(r.bottomRight, r.bottomLeft);
    dashedLine(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
