// The currently-active conversation key, 1-1 with React's
// `activeConversationKey` (private-dm-screen.tsx): `'dm:<id>'` /
// `'channel:<name>'` / `'group:<id>'` or null when no conversation is open.
//
// This is the small prerequisite state for the unread-lifecycle diff
// (clearOnActive + window-focus toasts): React passes `activeKey` into
// `useUnreadNotifications` and clears it on close. The Flutter side keeps
// the same value in a Riverpod Notifier so the lifecycle provider can read
// it + the chat screens can set/clear it on open/leave without threading a
// prop through every rebuild.
//
// Set by the sessions rail on select + the chat screens on open (initState);
// cleared on leave/close. null = no conversation open (React's empty-string
// `activeConversationKey` maps to `activeKey: null`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the active conversation key (`'dm:<id>'` / `'channel:<name>'` /
/// `'group:<id>'`) or null when nothing is open. Mirrors React's
/// `activeConversationKey || null` shape passed to `useUnreadNotifications`.
final activeConversationKeyProvider =
    NotifierProvider<_ActiveConversationKeyNotifier, String?>(
  _ActiveConversationKeyNotifier.new,
);

class _ActiveConversationKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets the active conversation key (called on open/select).
  void set(String? key) {
    if (state == key) return;
    state = key;
  }

  /// Clears the active key to null (called on leave/close).
  void clear() {
    if (state == null) return;
    state = null;
  }
}
