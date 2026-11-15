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
  Stream<String> startEventCapture({required String dsn}) {
    calls.add(ScriptedCall(BridgeMethod.startEventCapture, {'dsn': dsn}));
    return rustEvents.stream;
  }

  @override
  Future<void> stopEventCapture() =>
      runScripted(BridgeMethod.stopEventCapture, const {}, () {});

  @override
  Future<void> reportStartupFailure(String message) => runScripted(
      BridgeMethod.reportStartupFailure, {'message': message}, () {});

  @override
  Future<List<String>> logFiles() =>
      runScripted(BridgeMethod.logFiles, const {}, () => _logFiles);

  @override
  Future<void> disableCrashReporting() =>
      runScripted(BridgeMethod.disableCrashReporting, const {}, () {
        _crashReportingSalt = null;
      });
}
