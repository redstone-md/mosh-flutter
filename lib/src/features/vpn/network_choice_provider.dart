import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/network_inventory.dart';

enum NetworkChoiceFailure { save, restart }

class NetworkChoiceError implements Exception {
  const NetworkChoiceError(this.kind, this.cause);
  final NetworkChoiceFailure kind;
  final Object cause;
}

class NetworkChoiceState {
  const NetworkChoiceState(
      {this.savedAdapter, this.needsRestart = false, this.busy = false});
  final String? savedAdapter;
  final bool needsRestart;
  final bool busy;
}

class SavedNetworkChoice {
  const SavedNetworkChoice(this.interfaces, this.adapter);
  final List<NetworkInterfaceInfo> interfaces;
  final String? adapter;
}

class NetworkRouting {
  const NetworkRouting(this.saved, this.liveAdapter, this.vpnDetected);
  final SavedNetworkChoice saved;
  final String? liveAdapter;
  final bool vpnDetected;
}

// Kept for the bridge lifetime, so closing a settings disclosure does not
// forget that a saved choice still needs a process restart.
final networkChoiceProvider = NotifierProvider.family<NetworkChoiceController,
    NetworkChoiceState, BridgeFacade>(NetworkChoiceController.new);

class NetworkChoiceController extends Notifier<NetworkChoiceState> {
  NetworkChoiceController(this._bridge);
  final BridgeFacade _bridge;
  bool _known = false;
  bool _liveKnown = false;
  String? _liveAdapter;
  int _revision = 0;
  bool _restartPending = false;

  @override
  NetworkChoiceState build() {
    _known = false;
    _liveKnown = false;
    _liveAdapter = null;
    _revision++;
    return NetworkChoiceState(needsRestart: _restartPending);
  }

  Future<SavedNetworkChoice> readSaved() async {
    final startedUnder = ref;
    final revision = _revision;
    final (interfaces, consent) = await (
      Future.sync(_bridge.listInterfaces),
      Future.sync(_bridge.getVpnBypassConsent),
    ).wait;
    final adapter = _normalize(consent?.interface_);
    _checkRead(startedUnder);
    if (revision == _revision) {
      _known = true;
      state = NetworkChoiceState(
          savedAdapter: adapter,
          needsRestart: state.needsRestart || _restartPending,
          busy: state.busy);
    }
    return SavedNetworkChoice(interfaces, state.savedAdapter);
  }

  Future<NetworkRouting> readRouting() async {
    final startedUnder = ref;
    final (saved, binding, detection) = await (
      readSaved(),
      Future.sync(_bridge.getBindInterface),
      Future.sync(_bridge.detectVpn),
    ).wait;
    _checkRead(startedUnder);
    _liveKnown = true;
    _liveAdapter = _normalize(binding);
    return NetworkRouting(
        SavedNetworkChoice(saved.interfaces, state.savedAdapter),
        _liveAdapter,
        detection.vpnOwnsDefaultRoute);
  }

  Future<(SavedNetworkChoice, bool)> readPrompt() async {
    final startedUnder = ref;
    final (saved, detection) =
        await (readSaved(), Future.sync(_bridge.detectVpn)).wait;
    _checkRead(startedUnder);
    return (
      SavedNetworkChoice(saved.interfaces, state.savedAdapter),
      detection.vpnOwnsDefaultRoute
    );
  }

  bool requiresRestart(String? adapter) =>
      !_known ||
      state.needsRestart ||
      adapter != state.savedAdapter ||
      _liveKnown && adapter != _liveAdapter;

  /// Persist the choice and setup progress before attempting any restart.
  Future<void> apply(
    String? adapter, {
    Future<void> Function(Future<void> Function())? complete,
    required Future<void> Function() restart,
  }) async {
    final startedUnder = _acquire();
    try {
      final restartRequired = await _save(startedUnder, adapter);
      Future<void> applyRestart() async {
        if (!restartRequired) return;
        try {
          await restart();
        } catch (error) {
          throw NetworkChoiceError(NetworkChoiceFailure.restart, error);
        }
      }

      if (complete == null) {
        await applyRestart();
      } else {
        await complete(applyRestart);
      }
    } on NetworkChoiceError {
      rethrow;
    } catch (error) {
      throw NetworkChoiceError(NetworkChoiceFailure.save, error);
    } finally {
      _release(startedUnder);
    }
  }

  Future<void> clear() async {
    final startedUnder = _acquire();
    final changed = state.savedAdapter != null;
    try {
      // Declining is deliberately best-effort at the caller; still try to
      // clear persisted consent even if a preceding read returned none.
      await _bridge.setVpnBypassConsent(interfaceName: null);
      _publish(startedUnder, null, changed);
    } finally {
      _release(startedUnder);
    }
  }

  Future<bool> _save(Ref startedUnder, String? adapter) async {
    final changed = !_known || state.savedAdapter != adapter;
    final needsRestart = requiresRestart(adapter);
    if (changed) await _bridge.setVpnBypassConsent(interfaceName: adapter);
    _publish(startedUnder, adapter, needsRestart);
    return needsRestart;
  }

  void _publish(Ref startedUnder, String? adapter, bool needsRestart) {
    _restartPending |= needsRestart;
    if (!startedUnder.mounted) return;
    _revision++;
    _known = true;
    state = NetworkChoiceState(
        savedAdapter: adapter, needsRestart: _restartPending, busy: true);
  }

  Ref _acquire() {
    if (state.busy) {
      throw NetworkChoiceError(NetworkChoiceFailure.save,
          StateError('A network choice is already being saved'));
    }
    _revision++;
    state = NetworkChoiceState(
        savedAdapter: state.savedAdapter,
        needsRestart: state.needsRestart,
        busy: true);
    return ref;
  }

  void _release(Ref startedUnder) {
    if (!startedUnder.mounted) return;
    state = NetworkChoiceState(
        savedAdapter: state.savedAdapter,
        needsRestart: state.needsRestart || _restartPending);
  }

  void _checkRead(Ref startedUnder) {
    if (!startedUnder.mounted) throw StateError('Network choice was disposed');
  }

  String? _normalize(String? adapter) =>
      adapter == null || adapter.isEmpty ? null : adapter;
}
