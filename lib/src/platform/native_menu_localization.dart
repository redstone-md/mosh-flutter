import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/platform/native_menu_labels.dart';

final nativeMenuChannelProvider = Provider<MethodChannel?>((ref) =>
    Platform.isMacOS ? const MethodChannel('mosh/interface-menu') : null);

/// Relabels existing Cocoa commands after Flutter resolves the app language.
class NativeMenuLocalization extends ConsumerStatefulWidget {
  const NativeMenuLocalization({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<NativeMenuLocalization> createState() =>
      _NativeMenuLocalizationState();
}

class _NativeMenuLocalizationState
    extends ConsumerState<NativeMenuLocalization> {
  String? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = AppLocalizations.of(context)!;
    if (_locale == l.localeName) return;
    _locale = l.localeName;
    final channel = ref.read(nativeMenuChannelProvider);
    if (channel == null) return;
    final locale = l.localeName;
    final labels = nativeMenuLabels(l);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _locale == locale) unawaited(_update(channel, labels));
    });
  }

  Future<void> _update(
      MethodChannel channel, Map<String, String> labels) async {
    try {
      await channel.invokeMethod<void>('localize', labels);
    } on PlatformException catch (error) {
      debugPrint('Native menu localization failed: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Native menu localization is unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
