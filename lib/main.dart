import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/locale_provider.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/frb_generated.dart'; // RustLib (init entrypoint)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // frb 2.x: must initialize the bridge before any api call. In test
  // environments without the native cdylib this throws; main() is only
  // exercised in real device/desktop runs, not in `flutter test`.
  await RustLib.init();
  runApp(const ProviderScope(child: MoshApp()));
}

class MoshApp extends ConsumerWidget {
  const MoshApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Mosh',
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const MoshHome(),
    );
  }
}

class MoshHome extends StatelessWidget {
  const MoshHome({super.key});

  // appDiagnostics() reaches into RustLib.instance.api synchronously; if the
  // bridge is not initialized (e.g. under `flutter test` with no cdylib) it
  // throws during build. Wrap so the error flows through the FutureBuilder's
  // error branch instead of crashing the widget tree.
  Future<AppDiagnostics> _diagnostics() {
    try {
      return appDiagnostics();
    } catch (e) {
      return Future.error(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mosh')),
      // S2b smoke screen: prove the frb pipeline (init -> FFI -> opaque decode).
      // AppDiagnostics is generated as a RustAutoOpaque with no field getters
      // in Dart, so we render the resolved object identity rather than the 4
      // named fields. Field exposure requires an frb regen with the Rust
      // struct annotated non-opaque; out of scope for S2b.
      body: Center(
        child: FutureBuilder<AppDiagnostics>(
          future: _diagnostics(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'diagnostics error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            // Opaque round-trip succeeded; the bridge pipeline is proven.
            return const Text('Mosh');
          },
        ),
      ),
    );
  }
}
