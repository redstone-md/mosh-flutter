import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, moshTonalIconButtonStyle;
import 'package:mosh/src/features/conversation/conversation_tools.dart';

/// The search button of the Top bar card: opens and closes the search panel
/// under the bar. While the panel is open the button stands on a plate.
class MobileSearchToggle extends StatelessWidget {
  const MobileSearchToggle({
    super.key,
    required this.open,
    required this.onToggle,
    required this.l,
  });

  final bool open;
  final VoidCallback onToggle;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(MoshIcons.search),
        style: open ? moshTonalIconButtonStyle(MoshColors.of(context)) : null,
        tooltip: open ? l.closeMessageSearch : l.chatSearchPlaceholder,
        onPressed: onToggle,
      );
}

/// Mobile search panel: an autofocusing search `TextField` + a close icon
/// button that clears the query THEN closes.
///
/// Autofocus uses an explicit [FocusNode] created in `initState` and
/// `requestFocus()`ed there, PLUS `autofocus: true` on the `TextField`. The
/// explicit node lets the widget tests assert focus after `pump`; the
/// `autofocus` flag is the belt-and-suspenders guarantee the framework
/// requests focus on the first frame regardless of the node's lifecycle.
///
/// The close button calls `onSearch("")` THEN `onClose()` -- order matters,
/// so the query clears before the panel unmounts.
class MobileConversationSearch extends StatefulWidget {
  const MobileConversationSearch({
    super.key,
    required this.search,
    required this.onSearch,
    required this.onClose,
    required this.l,
  });

  final String search;
  final ValueChanged<String> onSearch;
  final VoidCallback onClose;
  final AppLocalizations l;

  @override
  State<MobileConversationSearch> createState() =>
      _MobileConversationSearchState();
}

class _MobileConversationSearchState extends State<MobileConversationSearch> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Autofocus on mount. Requested in initState so the focus lands on
    // the first frame the widget is visible.
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: conversationToolsPadding(compact: true),
        child: Row(
          spacing: MoshSpace.s2,
          children: [
            Expanded(
              child: ConversationSearchBox(
                search: widget.search,
                onSearch: widget.onSearch,
                hint: widget.l.chatSearchPlaceholder,
                autofocus: true,
                clearable: false,
                focusNode: _focusNode,
              ),
            ),
            // Clears the query THEN closes (order matters; the panel
            // unmounts after the clear).
            IconButton(
              icon: const Icon(MoshIcons.close),
              tooltip: widget.l.closeMessageSearch,
              onPressed: () {
                widget.onSearch('');
                widget.onClose();
              },
            ),
          ],
        ),
      );
}

/// The files filter on the phone: renders NOTHING while the filter is
/// `all`, and a line that says what is shown and how to go back while it is
/// `attachments`: a paperclip, "Files" and an "All messages" button, which
/// calls `onFilter(all)`.
///
/// The host renders this unconditionally (always in the layout) -- it
/// collapses to a zero-size [SizedBox.shrink] when the filter is `all`
/// (takes no space, so the effective layout is "not rendered").
class MobileConversationFilterNotice extends StatelessWidget {
  const MobileConversationFilterNotice({
    super.key,
    required this.filter,
    required this.onFilter,
    required this.l,
  });

  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    // Nothing to notice when the files filter is off.
    if (filter != ConversationFilter.attachments) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: conversationToolsPadding(compact: true),
      child: Row(
        spacing: MoshSpace.s2,
        children: [
          Icon(MoshIcons.attach, color: theme.colorScheme.primary),
          Expanded(
              child: Text(l.chatFilterAttachments,
                  style: theme.textTheme.labelLarge)),
          TextButton(
            onPressed: () => onFilter(ConversationFilter.all),
            child: Text(l.chatFilterAllMessages),
          ),
        ],
      ),
    );
  }
}
