import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_view.dart';
import 'call_view_state.dart';
import 'call_window_pipe.dart';

/// A call-only process starts no Rust, storage, capture or playback runtime.
Future<void> launchProcessCallWindow() async {
  final pipe = CallWindowPipe(
      stdin.transform(utf8.decoder).transform(const LineSplitter()),
      stdout.writeln,
      outputDone: stdout.done);
  pipe.onClosed = () => unawaited(windowManager.destroy());
  pipe.onMethod = await startCallWindowView((command) async {
    await pipe.invoke('call-command', command.toMap());
  });
  await pipe.invoke('call-ready');
}

/// The shared view is independent of the process transport and owns no audio.
Future<Future<Object?> Function(MethodCall)> startCallWindowView(
    Future<void> Function(CallViewCommand) sendCommand) async {
  final controller = _CallWindowController(sendCommand);
  await controller.initialize();
  runApp(_CallWindowApp(controller));
  return controller.handle;
}

class _CallWindowController extends ValueNotifier<CallViewState?>
    with WindowListener {
  _CallWindowController(this.sendCommand) : super(null);

  final Future<void> Function(CallViewCommand) sendCommand;
  bool _shown = false;
  bool _closing = false;

  Future<void> initialize() async {
    await windowManager.waitUntilReadyToShow(const WindowOptions(
      size: Size(420, 300),
      minimumSize: Size(340, 260),
      center: true,
      title: 'Mosh',
      alwaysOnTop: true,
    ));
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'call-present':
        value = CallViewState.fromMap(call.arguments as Map<Object?, Object?>);
        await windowManager.setTitle('Mosh · ${value!.peer}');
        if (!_shown) {
          _shown = true;
          await show();
        }
      case 'call-show':
        await show();
      case 'call-is-focused':
        return windowManager.isFocused();
      case 'call-close':
        _closing = true;
        value = null;
        await windowManager.setPreventClose(false);
        // Reply before destroying the engine that owns this method channel.
        Timer(const Duration(milliseconds: 20),
            () => unawaited(windowManager.close()));
      default:
        throw MissingPluginException('Unknown call window method');
    }
    return null;
  }

  Future<void> show() async {
    if (_closing) return;
    await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  void act(CallViewCommand command) {
    final call = value;
    if (_closing ||
        call == null ||
        (call.busy && !command.action.availableWhileBusy) ||
        call.sessionId != command.sessionId ||
        call.callId != command.callId) {
      return;
    }
    unawaited(sendCommand(command).catchError((Object error) {
      // Main-engine controls remain the authority if the IPC route is lost.
      debugPrint('Call window command failed: ${error.runtimeType}');
    }));
  }

  @override
  void onWindowClose() {
    if (_closing || value == null) return;
    act(value!.command(CallViewAction.end));
  }
}

class _CallWindowApp extends StatelessWidget {
  const _CallWindowApp(this.controller);
  final _CallWindowController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CallViewState?>(
        valueListenable: controller,
        builder: (_, call, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: call == null ? 'Mosh' : 'Mosh · ${call.peer}',
          theme: moshThemeData,
          locale: Locale(call?.language ?? 'en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: call == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: CallView(
                          call: call,
                          onAction: (action) =>
                              controller.act(call.command(action))))),
        ),
      );
}
