import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/rust/api/device_link.dart' as api;
import 'package:mosh/src/rust/device_link/types.dart';

final deviceLinkProvider =
    AsyncNotifierProvider.autoDispose<DeviceLinkController, DeviceLinkSnapshot>(
  DeviceLinkController.new,
);

class DeviceLinkController extends AsyncNotifier<DeviceLinkSnapshot> {
  bool _reading = false;

  @override
  Future<DeviceLinkSnapshot> build() async {
    final timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    ref.onDispose(timer.cancel);
    return api.snapshot();
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final value = await api.snapshot();
      if (ref.mounted) state = AsyncData(value);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    } finally {
      _reading = false;
    }
  }

  Future<void> _act(Future<DeviceLinkSnapshot> Function() action) async {
    final value = await action();
    if (ref.mounted) state = AsyncData(value);
  }

  Future<void> createQr(String name) =>
      _act(() => api.createQr(deviceName: name));
  Future<void> importQr(String uri) => _act(() => api.importQr(uri: uri));
  Future<void> approve(String code) =>
      _act(() => api.approve(confirmationCode: code));
  Future<void> cancel() => _act(api.cancel);
}
