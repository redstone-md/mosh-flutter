import 'dart:async' show StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, MossLibraryInfo, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/channel_runtime.dart' show JoinChannelRequest;
import 'package:mosh/src/rust/channel_runtime/types.dart'
    show ChannelListSnapshot, ChannelSnapshot;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;
import 'package:mosh/src/rust/org_runtime.dart'
    show JoinOrgRequest, OrgSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show
        AcceptInviteRequest,
        CallStarted,
        InviteCreated,
        SessionListSnapshot,
        SessionSnapshot,
        StartSessionRequest;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show
        CreateGroupRequest,
        GroupCreated,
        GroupListSnapshot,
        GroupSnapshot,
        JoinGroupRequest;
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;

import 'gateway_snapshots.dart';
import 'scripted_calls.dart';
import 'scripted_conversations.dart';

part 'scriptable_bridge_diagnostics.dart';
part 'scriptable_bridge_conversations.dart';
part 'scriptable_bridge_organizations.dart';
part 'scriptable_bridge_network.dart';
part 'scriptable_bridge_calls.dart';

/// Every method on [BridgeFacade]. Tests name a method through this enum, so
/// a typo is a compile error instead of a call that is never scripted.
enum BridgeMethod {
  appDiagnostics,
  mossLibraryInfo,
  nativeRuntimeStatus,
  createInvite,
  acceptInvite,
  listSessions,
  readReceiptsEnabled,
  setReadReceiptsEnabled,
  crashReportingSalt,
  enableCrashReporting,
  disableCrashReporting,
  startPanicReporting,
  stopPanicReporting,
  listChannels,
  listGroups,
  joinChannel,
  createGroup,
  joinGroup,
  sendChannelDmOffer,
  sendGroupDmOffer,
  joinOrg,
  leaveOrg,
  listOrgs,
  pollOrg,
  sendOrgDmOffer,
  acceptOrgDmOffer,
  dismissOrgDmOffer,
  createOrgGroup,
  acceptOrgGroupOffer,
  dismissOrgGroupOffer,
  orgGroupInviteMembers,
  listInterfaces,
  detectVpn,
  getBindInterface,
  getVpnBypassConsent,
  setVpnBypassConsent,
  callStart,
  callAccept,
  callDecline,
  callEnd,
  callSendFrame,
  callDrainFrames,
}

/// One recorded call to the bridge facade.
typedef BridgeCall = ScriptedCall<BridgeMethod>;

/// Record and script facade calls; share conversation state with the gateway fake.
class ScriptableBridge extends _ScriptableBridgeState
    with
        _BridgeDiagnostics,
        _BridgeConversations,
        _BridgeOrganizations,
        _BridgeNetwork,
        _BridgeCalls {
  ScriptableBridge({super.conversations});
}

abstract class _ScriptableBridgeState
    with ScriptedEngine<BridgeMethod>
    implements BridgeFacade {
  _ScriptableBridgeState({ScriptedConversations? conversations})
      : conversations = conversations ?? ScriptedConversations();

  /// The seeded conversations `listSessions`/`listChannels`/`listGroups`
  /// serve and the invite paths insert into. Share the gateway double's
  /// instance so both surfaces see one runtime's state.
  final ScriptedConversations conversations;

  final Map<String, OrgSnapshot> _orgs = {};

  InviteCreated? _invite;
  NativeRuntimeStatus? _nativeStatus;
  MossLibraryInfo? _mossLibraryInfo;
  List<NetworkInterfaceInfo> _interfaces = const [];
  VpnDetection? _vpnDetection;
  String? _bindInterface;
  VpnBypassConsent? _vpnConsent;
  List<Uint8List> _callFrames = const [];
  bool _readReceiptsEnabled = false;
  String? _crashReportingSalt;

  void seedSessions(Iterable<SessionSnapshot> seeded) =>
      conversations.seedSessions(seeded);

  void seedChannels(Iterable<ChannelSnapshot> seeded) =>
      conversations.seedChannels(seeded);

  void seedGroups(Iterable<GroupSnapshot> seeded) =>
      conversations.seedGroups(seeded);

  void seedOrgs(Iterable<OrgSnapshot> orgs) {
    _orgs
      ..clear()
      ..addEntries(orgs.map((o) => MapEntry(o.orgPubkey, o)));
  }

  void seedInvite(InviteCreated invite) => _invite = invite;

  void seedNativeRuntimeStatus(NativeRuntimeStatus status) =>
      _nativeStatus = status;

  void seedMossLibraryInfo(MossLibraryInfo info) => _mossLibraryInfo = info;

  void seedInterfaces(List<NetworkInterfaceInfo> interfaces) =>
      _interfaces = interfaces;

  void seedVpnDetection(VpnDetection detection) => _vpnDetection = detection;

  void seedBindInterface(String? name) => _bindInterface = name;

  void seedVpnConsent(VpnBypassConsent? consent) => _vpnConsent = consent;

  void seedCallFrames(List<Uint8List> frames) => _callFrames = frames;

  void seedReadReceiptsEnabled(bool enabled) => _readReceiptsEnabled = enabled;

  void seedCrashReportingSalt(String? salt) => _crashReportingSalt = salt;

  /// What `startPanicReporting` streams; tests add Rust event JSON here.
  final StreamController<String> rustPanics = StreamController.broadcast();
}
