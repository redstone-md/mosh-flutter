import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/shared/press_scale.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
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
        Text(l.onboardTitle, style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          l.onboardSubtitle,
          style: text.bodySmall?.copyWith(color: MoshColors.fg3),
        ),
        const SizedBox(height: 18),
        _TileSection(
          label: l.onboardStartLabel,
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
        const SizedBox(height: 18),
        _TileSection(
          label: l.onboardJoinLabel,
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
