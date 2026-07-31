// S4.4: slice-one onboarding screen - display-name entry + chat/group/join tiles.
// Matches React OnboardMenu (NewSessionPanelMenu.tsx): identity chip -> head
// (title + subtitle) -> "Start" tiles -> "Join" tile. Only the Chat tile is
// functional here (inviteFlowProvider.create() -> invite URI SnackBar; no router
// yet). Group/Join show a "later slice" SnackBar. State split per ADR 0010:
// cross-screen displayName lives in inviteFlowProvider; the TextEditingController
// is local State. All strings resolve through AppLocalizations.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/session_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    // Seed from the provider so a rebuild does not clobber an entered name.
    _nameController =
        TextEditingController(text: ref.read(inviteFlowProvider).displayName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) =>
      ref.read(inviteFlowProvider.notifier).setDisplayName(value);

  Future<void> _startChat() async {
    final scaffold = ScaffoldMessenger.of(context);
    final invite = await ref.read(inviteFlowProvider.notifier).create();
    if (!mounted) return;
    scaffold.showSnackBar(SnackBar(content: Text(invite.inviteUri)));
  }

  void _showLaterSlice() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.onboardJoinStepBody)),
    );
  }

  TextStyle? _sectionStyle(ThemeData t) => t.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
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
                Text(l.onboardTitle, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(l.onboardSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.55)),
                const SizedBox(height: 18),
                Text(l.onboardStartLabel, style: _sectionStyle(theme)),
                const SizedBox(height: 8),
                _OnboardTile(
                  icon: Icons.chat_bubble_outline,
                  title: l.onboardTileChatTitle,
                  desc: l.onboardTileChatDesc,
                  onTap: _startChat,
                ),
                const SizedBox(height: 8),
                _OnboardTile(
                  icon: Icons.group_outlined,
                  title: l.onboardTileGroupTitle,
                  desc: l.onboardTileGroupDesc,
                  onTap: _showLaterSlice,
                ),
                const SizedBox(height: 18),
                Text(l.onboardJoinLabel, style: _sectionStyle(theme)),
                const SizedBox(height: 8),
                _OnboardTile(
                  icon: Icons.link,
                  title: l.onboardTileJoinTitle,
                  desc: l.onboardTileJoinDesc,
                  onTap: _showLaterSlice,
                ),
              ],
            ),
          ),
        ),
      ),
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
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontSize: 13.5)),
        subtitle:
            Text(desc, style: const TextStyle(fontSize: 11.5), maxLines: 2),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }
}
