// Embeddable OnboardMenu body -- 1:1 with React `OnboardMenu`
// (src/features/private-dm/NewSessionPanelMenu.tsx:19-94): identity chip,
// Start tiles, Join tiles, Advanced + About disclosures. No Scaffold so a
// caller embeds it (OnboardingScreen wraps in Center >
// SingleChildScrollView > ConstrainedBox; atomic #3 embeds the same widget
// inline in the desktop chat-pane).
//
// Owns the 3 TextEditingControllers + inviteFlow handlers verbatim from the
// former inline OnboardingScreen body. Tile taps call injected VoidCallbacks
// (onPickChat/Group/Channel/Join) -- the menu does NOT context.go itself;
// the caller decides routing. Diagnostics lives in the caller's AppBar /
// peer-status button, not here (React has no diagnostics surface in
// OnboardMenu).
import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/disclosure.dart';
import 'package:mosh/src/features/shared/field.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

/// OnboardMenu body -- embeddable Column mirroring React's `OnboardMenu`
/// (NewSessionPanelMenu.tsx:19). Caller wraps it in its own scroll/constraints
/// (OnboardingScreen: Center>SingleChildScrollView>ConstrainedBox(maxWidth:460)).
class OnboardMenu extends ConsumerStatefulWidget {
  const OnboardMenu({
    super.key,
    required this.onPickChat,
    required this.onPickGroup,
    required this.onPickChannel,
    required this.onPickJoin,
  });

  /// Start-section chat tile (React onPick("chat"), NewSessionPanelMenu.tsx:44).
  final VoidCallback onPickChat;

  /// Start-section group tile (React onPick("group"), NewSessionPanelMenu.tsx:50).
  final VoidCallback onPickGroup;

  /// Join-section join tile (React onPick("join"), NewSessionPanelMenu.tsx:60).
  final VoidCallback onPickJoin;

  /// Join-section channel tile (React onPick("channel"), NewSessionPanelMenu.tsx:66).
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

  // Advanced disclosure handlers (1:1 with React's NewSessionPanelMenu.tsx):
  // staticPeer mirrors `props.onStaticPeer(e.target.value)` (null when empty to
  // match the String? state); listenPort mirrors `Number(e.target.value) || 0`
  // via tryParse with a 0 fallback on non-numeric input.
  void _onStaticPeerChanged(String value) => ref
      .read(inviteFlowProvider.notifier)
      .setStaticPeer(value.isEmpty ? null : value);
  void _onListenPortChanged(String value) {
    // React parity: NewSessionPanelMenu.tsx renders `<input type="number"
    // min={0} max={65535} ...>` so the browser rejects/flags out-of-range
    // values and `Number(e.target.value) || 0` coerces non-numeric to 0.
    // Flutter has no native ranged numeric input, so the range constraint
    // is enforced here by clamping the STORED value to 0..65535 before it
    // reaches inviteFlow (and onward to Rust as listen_port). The field
    // text is intentionally NOT rewritten: a mid-typing rewrite (e.g.
    // "999" -> "65535") is jarring and fights the user. The displayed text
    // may therefore transiently show an out-of-range value, but only the
    // clamped stored value crosses the seam -- mirroring the conservative
    // reading of the React `<input min/max>` behavior.
    final parsed = int.tryParse(value) ?? 0;
    final n = parsed.clamp(0, 65535);
    ref.read(inviteFlowProvider.notifier).setListenPort(n);
  }

  // `.onboard-section-label { font-size: 10.5px; font-weight: 700;
  // letter-spacing: 0.13em; color: var(--fg-4) }`.
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
        // `.onboard-head h1 { font-size: 23px; letter-spacing: -0.01em }`
        // over `p { margin: 6px 0 0; font-size: 12.5px; line-height: 1.55;
        // color: var(--fg-3) }`.
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
        Text(l.onboardStartLabel, style: _sectionStyle(theme)),
        const SizedBox(height: 8),
        _OnboardTile(
          icon: Icons.chat_bubble_outline,
          title: l.onboardTileChatTitle,
          desc: l.onboardTileChatDesc,
          onTap: widget.onPickChat,
        ),
        const SizedBox(height: 8),
        _OnboardTile(
          icon: Icons.group_outlined,
          title: l.onboardTileGroupTitle,
          desc: l.onboardTileGroupDesc,
          onTap: widget.onPickGroup,
        ),
        const SizedBox(height: 18),
        Text(l.onboardJoinLabel, style: _sectionStyle(theme)),
        const SizedBox(height: 8),
        _OnboardTile(
          icon: Icons.link,
          title: l.onboardTileJoinTitle,
          desc: l.onboardTileJoinDesc,
          onTap: widget.onPickJoin,
        ),
        const SizedBox(height: 8),
        _OnboardTile(
          icon: Icons.tag,
          title: l.onboardTileChannelTitle,
          desc: l.onboardTileChannelDesc,
          onTap: widget.onPickChannel,
        ),
        const SizedBox(height: 18),
        Disclosure(
          icon: Icons.settings,
          label: l.onboardAdvancedToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Field(
                label: l.setupStaticPeerLabel,
                hint: l.setupStaticPeerHint,
                child: TextField(
                  controller: _staticPeerController,
                  decoration: InputDecoration(
                    hintText: l.setupStaticPeerPlaceholder,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                  onChanged: _onStaticPeerChanged,
                ),
              ),
              const SizedBox(height: 12),
              Field(
                label: l.setupListenPortLabel,
                hint: l.setupListenPortHint,
                child: TextField(
                  controller: _listenPortController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                  onChanged: _onListenPortChanged,
                ),
              ),
              const SizedBox(height: 12),
              // Bind-interface override -- 1:1 with React's
              // NewSessionPanelMenu.tsx Advanced disclosure child
              // (L93 <BindInterfaceField gateway={props.gateway} />).
              // Writes the same stored VPN-bypass answer the
              // startup question does + relaunches via onAccept
              BindInterfaceField(
                gateway: ref.read(gatewayProvider),
                l: l,
                onAccept: DesktopAppRelauncherScope.of(context).relaunch,
              ),
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

class _IdentityChip extends StatelessWidget {
  const _IdentityChip({
    required this.controller,
    required this.label,
    required this.hint,
    required this.identityHint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final String identityHint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: const Icon(Icons.person, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                helperText: identityHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardTile extends StatelessWidget {
  const _OnboardTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // React `.onboard-tile { padding: 13px 14px; gap: 13px; border: 1px
    // solid var(--line); border-radius: 12px; background: var(--bg-2) }`,
    // with a `.tile-icon` on --moss-glow (NOT a solid moss fill) and a
    // --fg-4 chevron.
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: MoshColors.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MoshColors.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        horizontalTitleGap: 13,
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MoshColors.mossGlow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: MoshColors.moss),
        ),
        title: Text(title,
            style: const TextStyle(fontSize: 13.5, color: MoshColors.fg1)),
        subtitle: Text(
          desc,
          style: const TextStyle(fontSize: 11.5, color: MoshColors.fg3),
          maxLines: 2,
        ),
        trailing:
            const Icon(Icons.chevron_right, size: 18, color: MoshColors.fg4),
        onTap: onTap,
      ),
    );
  }
}
