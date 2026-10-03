import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/features/diagnostics/state_label.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/util/format.dart';

class ChannelDiagnostics extends StatelessWidget {
  const ChannelDiagnostics(
      {super.key, required this.channel, this.libraryInfo});

  final ChannelSnapshot channel;
  final MossLibraryInfo? libraryInfo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ConversationDiagnosticsSections(
      label: l.diagGroupChannelDetails,
      mesh: channel.mesh,
      events: channel.events,
      libraryInfo: libraryInfo,
      rows: [
        (l.diagRowName, '#${channel.name}'),
        (l.diagRowDisplay, channel.displayName),
        (l.diagRowTopic, channel.topic),
        (l.diagRowDevice, shorten(channel.deviceFingerprint, 10)),
      ],
    );
  }
}

class GroupDiagnostics extends StatelessWidget {
  const GroupDiagnostics({super.key, required this.group, this.libraryInfo});

  final GroupSnapshot group;
  final MossLibraryInfo? libraryInfo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ConversationDiagnosticsSections(
      label: l.diagGroupGroupDetails,
      mesh: group.mesh,
      events: group.events,
      libraryInfo: libraryInfo,
      rows: [
        (l.diagRowLabel, group.label ?? l.diagDash),
        (l.diagRowMembers, group.memberCount.toString()),
        (l.diagRowRole, group.isAdmin ? l.diagRoleAdmin : l.diagRoleMember),
        (l.diagRowMlsState, stateLabel(l, group.state)),
        (l.diagRowDisplay, group.displayName),
        (l.diagRowGroupId, shorten(group.groupId, 12)),
        (l.diagRowCreator, shorten(group.creatorFingerprint, 8)),
        (l.diagRowDevice, shorten(group.deviceFingerprint, 10)),
      ],
    );
  }
}
