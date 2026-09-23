// Embeddable OnboardMenu body: identity chip, Start tiles, Join tiles.
// No Scaffold so a caller embeds it (OnboardingScreen wraps in Center >
// SingleChildScrollView > ConstrainedBox; atomic #3 embeds the same widget
// inline in the desktop chat-pane).
//
// The Advanced + About disclosures moved to the settings screen (the gear
// at the rail bottom): connection controls, device picks and the crypto
// notice live there now, so the first-run surface is only identity + the
// four tiles. This menu keeps the display-name chip (`inviteFlowProvider`
// seeds it) and the tile taps, which call injected VoidCallbacks
// (onPickChat/Group/Channel/Join) — the menu does NOT context.go itself;
// the caller decides routing.
import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';

part 'onboard_menu_x.dart';

/// OnboardMenu body -- embeddable Column. Caller wraps it in its own
/// scroll/constraints (OnboardingScreen:
/// Center>SingleChildScrollView>ConstrainedBox(maxWidth:460)).
class OnboardMenu extends ConsumerStatefulWidget {
  const OnboardMenu({
    super.key,
    required this.onPickChat,
    required this.onPickGroup,
    required this.onPickChannel,
    required this.onPickJoin,
  });

  /// Start-section chat tile.
  final VoidCallback onPickChat;

  /// Start-section group tile.
  final VoidCallback onPickGroup;

  /// Join-section join tile.
  final VoidCallback onPickJoin;

  /// Join-section channel tile.
  final VoidCallback onPickChannel;

  @override
  ConsumerState<OnboardMenu> createState() => _OnboardMenuState();
}

class _OnboardMenuState extends ConsumerState<OnboardMenu> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    // Seed from the provider so a rebuild does not clobber an entered name.
    _nameController = TextEditingController(
      text: ref.read(inviteFlowProvider).displayName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) =>
      ref.read(inviteFlowProvider.notifier).setDisplayName(value);

  TextStyle? _sectionStyle(ThemeData t) => t.textTheme.labelSmall?.copyWith(
        color: MoshColors.fg4,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.365,
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IdentityChip(
          controller: _nameController,
          label: l.setupDisplayNameLabel,
          hint: l.setupDisplayNamePlaceholder,
          identityHint: l.onboardIdentityHint,
          onChanged: _onNameChanged,
        ),
        const SizedBox(height: 18),
        Text(
          l.onboardTitle,
          style: const TextStyle(
            fontSize: 23,
            letterSpacing: -0.23,
            color: MoshColors.fg1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l.onboardSubtitle,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: MoshColors.fg3,
          ),
        ),
        const SizedBox(height: 18),
        _TileSection(
          label: l.onboardStartLabel,
          labelStyle: _sectionStyle(theme),
          tiles: [
            _OnboardTile(
              icon: Icons.chat_bubble_outline,
              title: l.onboardTileChatTitle,
              desc: l.onboardTileChatDesc,
              onTap: widget.onPickChat,
            ),
            _OnboardTile(
              icon: Icons.group_outlined,
              title: l.onboardTileGroupTitle,
              desc: l.onboardTileGroupDesc,
              onTap: widget.onPickGroup,
            ),
          ],
        ),
        _TileSection(
          label: l.onboardJoinLabel,
          labelStyle: _sectionStyle(theme),
          tiles: [
            _OnboardTile(
              icon: Icons.link,
              title: l.onboardTileJoinTitle,
              desc: l.onboardTileJoinDesc,
              onTap: widget.onPickJoin,
            ),
            _OnboardTile(
              icon: Icons.tag,
              title: l.onboardTileChannelTitle,
              desc: l.onboardTileChannelDesc,
              onTap: widget.onPickChannel,
            ),
          ],
        ),
      ],
    );
  }
}
