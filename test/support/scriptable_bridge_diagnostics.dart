part of 'scriptable_bridge.dart';

mixin _BridgeDiagnostics on _ScriptableBridgeState {
  @override
  Future<AppDiagnostics> appDiagnostics() =>
      runScripted(BridgeMethod.appDiagnostics, const {}, cannedAppDiagnostics);

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() => runScripted(
      BridgeMethod.nativeRuntimeStatus,
      const {},
      () => _nativeStatus ?? cannedNativeRuntimeStatus());

  @override
  Future<MossLibraryInfo> mossLibraryInfo({String? peerMossId}) => runScripted(
      BridgeMethod.mossLibraryInfo,
      {'peerMossId': peerMossId},
      () => _mossLibraryInfo ?? cannedMossLibraryInfo());

  @override
  Future<bool> readReceiptsEnabled() => runScripted(
      BridgeMethod.readReceiptsEnabled, const {}, () => _readReceiptsEnabled);

  @override
  Future<void> setReadReceiptsEnabled({required bool enabled}) =>
      runScripted(BridgeMethod.setReadReceiptsEnabled, {'enabled': enabled},
          () {
        _readReceiptsEnabled = enabled;
      });

  @override
  Future<String?> crashReportingSalt() => runScripted(
      BridgeMethod.crashReportingSalt, const {}, () => _crashReportingSalt);

  @override
  Future<String> enableCrashReporting() => runScripted(
      BridgeMethod.enableCrashReporting,
      const {},
      () => _crashReportingSalt ??= 'scripted-salt');

  @override
  Stream<String> startPanicReporting({required String dsn}) {
    calls.add(ScriptedCall(BridgeMethod.startPanicReporting, {'dsn': dsn}));
    return rustPanics.stream;
  }

  @override
  Future<void> stopPanicReporting() =>
      runScripted(BridgeMethod.stopPanicReporting, const {}, () {});

  @override
  Future<void> disableCrashReporting() =>
      runScripted(BridgeMethod.disableCrashReporting, const {}, () {
        _crashReportingSalt = null;
      });
}
