// Embeddable OnboardMenu body: identity chip, Start tiles, Join tiles,
// Advanced + About disclosures. No Scaffold so a caller embeds it
// (OnboardingScreen wraps in Center > SingleChildScrollView >
// ConstrainedBox; atomic #3 embeds the same widget inline in the desktop
// chat-pane).
//
// Owns the 3 TextEditingControllers + inviteFlow handlers verbatim from the
// former inline OnboardingScreen body. Tile taps call injected VoidCallbacks
// (onPickChat/Group/Channel/Join) -- the menu does NOT context.go itself;
// the caller decides routing. Diagnostics lives in the caller's AppBar /
// peer-status button, not here.
import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/disclosure.dart';
import 'package:mosh/src/features/shared/field.dart';
import 'package:mosh/src/features/shared/read_receipts_toggle.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/state/gateway_provider.dart';
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
  late final TextEditingController _staticPeerController;
  late final TextEditingController _listenPortController;

  @override
  void initState() {
    super.initState();
    // Seed from the provider so a rebuild does not clobber an entered name.
    _nameController = TextEditingController(
      text: ref.read(inviteFlowProvider).displayName,
    );
    // Advanced disclosure fields -- seeded from inviteFlow (staticPeer is
    // nullable String, listenPort defaults to 8765) so they survive rebuilds.
    _staticPeerController = TextEditingController(
      text: ref.read(inviteFlowProvider).staticPeer ?? '',
    );
    _listenPortController = TextEditingController(
      text: ref.read(inviteFlowProvider).listenPort.toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _staticPeerController.dispose();
    _listenPortController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) =>
      ref.read(inviteFlowProvider.notifier).setDisplayName(value);

  // Advanced disclosure handlers: staticPeer maps an empty string to null
  // (matching the String? state); listenPort parses with a 0 fallback on
  // non-numeric input.
  void _onStaticPeerChanged(String value) => ref
      .read(inviteFlowProvider.notifier)
      .setStaticPeer(value.isEmpty ? null : value);
  void _onListenPortChanged(String value) {
    // The port must stay in 0..65535 before it reaches inviteFlow (and
    // onward to Rust as listen_port). The range is enforced by clamping
    // the STORED value. The field text is intentionally NOT rewritten: a
    // mid-typing rewrite (e.g. "999" -> "65535") is jarring and fights the
    // user. The displayed text may therefore transiently show an
    // out-of-range value, but only the clamped stored value crosses the
    // seam.
    final parsed = int.tryParse(value) ?? 0;
    final n = parsed.clamp(0, 65535);
    ref.read(inviteFlowProvider.notifier).setListenPort(n);
  }

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
        const SizedBox(height: 18),
        Disclosure(
          icon: Icons.settings,
          label: l.onboardAdvancedToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AdvancedTextField(
                label: l.setupStaticPeerLabel,
                hint: l.setupStaticPeerHint,
                fieldHint: l.setupStaticPeerPlaceholder,
                controller: _staticPeerController,
                onChanged: _onStaticPeerChanged,
              ),
              const SizedBox(height: 12),
              _AdvancedTextField(
                label: l.setupListenPortLabel,
                hint: l.setupListenPortHint,
                controller: _listenPortController,
                keyboardType: TextInputType.number,
                onChanged: _onListenPortChanged,
              ),
              const SizedBox(height: 12),
              // Bind-interface override. Writes the same stored
              // VPN-bypass answer the startup question does + relaunches
              // via onAccept.
              BindInterfaceField(
                bridge: ref.read(bridgeFacadeProvider),
                l: l,
                onAccept: DesktopAppRelauncherScope.of(context).relaunch,
              ),
              const SizedBox(height: 12),
              // The app-level read-receipts answer (one toggle for every
              // DM; issue #2). Lives beside the bind-interface override
              // because both are Advanced-level settings with a persisted
              // answer read at call time.
              ReadReceiptsToggle(),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Disclosure(
          icon: Icons.verified_user,
          label: l.onboardAboutToggle,
          child: Text(
            l.cryptoNoticeBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}
