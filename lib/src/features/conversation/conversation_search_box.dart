import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show feedPadding;
import 'package:mosh/src/features/shared/search_field.dart';

/// The padding of the search under a conversation's header and of the
/// lines that take its place: 8 px above and below, the feed's own at the
/// sides.
EdgeInsets conversationToolsPadding({required bool compact}) =>
    EdgeInsets.symmetric(
        vertical: MoshSpace.s2, horizontal: feedPadding(compact: compact).left);

/// The search inside a conversation: the Search field card, fed by the
/// screen. It owns the controller, so a rebuild of the screen, which a poll
/// causes every second, never moves the caret.
class ConversationSearchBox extends StatefulWidget {
  const ConversationSearchBox({
    super.key,
    required this.search,
    required this.onSearch,
    required this.hint,
    this.autofocus = false,
    this.clearable = true,
    this.focusNode,
  });

  final String search;
  final ValueChanged<String> onSearch;

  /// What the field looks through, said while it is empty.
  final String hint;

  /// The mobile panel autofocuses on mount; the desktop row does not.
  final bool autofocus;

  /// Off on the phone, where the X beside the field closes the search.
  final bool clearable;

  /// Supplied by the mobile panel so its test can assert focus.
  final FocusNode? focusNode;

  @override
  State<ConversationSearchBox> createState() => _ConversationSearchBoxState();
}

class _ConversationSearchBoxState extends State<ConversationSearchBox> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.search);

  @override
  void didUpdateWidget(covariant ConversationSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host owns the value. Only write it back when it genuinely
    // diverged (e.g. the mobile close button clearing the query), so a
    // rebuild triggered by anything else leaves the caret alone.
    if (widget.search != _controller.text) {
      _controller.text = widget.search;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SearchField(
        controller: _controller,
        hint: widget.hint,
        onChanged: widget.onSearch,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        clearable: widget.clearable,
      );
}

/// The Segment card: a recessed pill track around two 32 px segments, of
/// which exactly one is lit.
class ConversationFilterToggle extends StatelessWidget {
  const ConversationFilterToggle({
    super.key,
    required this.attachmentsActive,
    required this.onAll,
    required this.onAttachments,
    required this.l,
  });

  final bool attachmentsActive;
  final VoidCallback onAll;
  final VoidCallback onAttachments;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Semantics(
      label: l.chatFilterAttachments,
      child: Container(
        padding: const EdgeInsets.all(MoshSpace.s1),
        decoration: ShapeDecoration(
            color: colors.surfaceContainerLowest, shape: MoshShapes.pill),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: MoshSpace.s1,
          children: <Widget>[
            _FilterSegment(
              label: l.chatFilterAll,
              active: !attachmentsActive,
              onTap: onAll,
            ),
            _FilterSegment(
              label: l.chatFilterAttachments,
              icon: MoshIcons.attach,
              active: attachmentsActive,
              onTap: onAttachments,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSegment extends StatelessWidget {
  const _FilterSegment({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final color = active ? colors.onSurface : colors.onSurfaceVariant;
    // A text button resized to the card: it brings the pill, the label
    // style and the focus ring.
    final style = TextButton.styleFrom(
      foregroundColor: color,
      iconColor: color,
      backgroundColor: active ? colors.surfaceBright : Colors.transparent,
      minimumSize: const Size(0, MoshSpace.s8),
      padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s3),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      iconSize: MoshSpace.s4,
    ).copyWith(overlayColor: MoshState.layer(colors.onSurface));
    // The card keeps 4 px between the glyph and the label, half of what a
    // button with an icon does.
    return TextButton(
      onPressed: onTap,
      style: style,
      child:
          Row(mainAxisSize: MainAxisSize.min, spacing: MoshSpace.s1, children: [
        if (icon != null) Icon(icon),
        Text(label),
      ]),
    );
  }
}
