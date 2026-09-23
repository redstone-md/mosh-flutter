// The Connection settings section: the advanced connection controls that
// used to live in the onboarding menu's Advanced disclosure — static peer,
// listen port, the bind-interface override and the read-receipts toggle.
//
// The two text fields edit the same `inviteFlowProvider` state the
// new-session flow reads (one source of truth; a change here immediately
// shapes the next session). `BindInterfaceField` and `ReadReceiptsToggle`
// are reused as-is — they own their own persistence + relaunch/error
// surfaces, so this section is only a frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/field.dart' show Field;
import 'package:mosh/src/features/shared/read_receipts_toggle.dart'
    show ReadReceiptsToggle;
import 'package:mosh/src/features/vpn/bind_interface_field.dart'
    show BindInterfaceField;
import 'package:mosh/src/platform/desktop_app_relauncher.dart'
    show DesktopAppRelauncherScope;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;

class ConnectionSettingsSection extends ConsumerStatefulWidget {
  const ConnectionSettingsSection({super.key});

  @override
  ConsumerState<ConnectionSettingsSection> createState() =>
      _ConnectionSettingsSectionState();
}

class _ConnectionSettingsSectionState
    extends ConsumerState<ConnectionSettingsSection> {
  late final TextEditingController _staticPeerController;
  late final TextEditingController _listenPortController;

  @override
  void initState() {
    super.initState();
    // Seeded from the provider (the same fields the new-session flow uses)
    // so a rebuild does not clobber entered values.
    _staticPeerController = TextEditingController(
      text: ref.read(inviteFlowProvider).staticPeer ?? '',
    );
    _listenPortController = TextEditingController(
      text: ref.read(inviteFlowProvider).listenPort.toString(),
    );
  }

  @override
  void dispose() {
    _staticPeerController.dispose();
    _listenPortController.dispose();
    super.dispose();
  }

  // An empty string maps to null (matching inviteFlow's String? state).
  void _onStaticPeerChanged(String value) => ref
      .read(inviteFlowProvider.notifier)
      .setStaticPeer(value.isEmpty ? null : value);

  // The port stays in 0..65535 before it reaches inviteFlow; the STORED
  // value is clamped, the field text is intentionally not rewritten (a
  // mid-typing rewrite fights the user — see the onboarding twin).
  void _onListenPortChanged(String value) {
    final parsed = int.tryParse(value) ?? 0;
    ref.read(inviteFlowProvider.notifier).setListenPort(parsed.clamp(0, 65535));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Field(
          label: l.setupStaticPeerLabel,
          hint: l.setupStaticPeerHint,
          child: TextFormField(
            controller: _staticPeerController,
            decoration: InputDecoration(hintText: l.setupStaticPeerPlaceholder),
            onChanged: _onStaticPeerChanged,
          ),
        ),
        const SizedBox(height: 16),
        Field(
          label: l.setupListenPortLabel,
          hint: l.setupListenPortHint,
          child: TextFormField(
            controller: _listenPortController,
            keyboardType: TextInputType.number,
            onChanged: _onListenPortChanged,
          ),
        ),
        const SizedBox(height: 16),
        BindInterfaceField(
          bridge: ref.read(bridgeFacadeProvider),
          l: l,
          onAccept: DesktopAppRelauncherScope.of(context).relaunch,
        ),
        const SizedBox(height: 16),
        ReadReceiptsToggle(),
      ],
    );
  }
}
