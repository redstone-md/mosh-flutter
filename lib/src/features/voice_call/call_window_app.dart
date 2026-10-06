import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_view.dart';
import 'call_view_state.dart';
import 'call_window_pipe.dart';

/// Returns before the normal app startup in a call-only child engine.
Future<bool> launchCallWindow() async {
  final current = await WindowController.fromCurrentEngine();
  if (current.arguments.isEmpty) return false;
  final args = jsonDecode(current.arguments) as Map<String, Object?>;
  if (args['type'] != 'voice-call') return false;
  final parent = WindowController.fromWindowId(args['parent'] as String);
  final token = args['token'] as String;
  final controller = _CallWindowController((command) => parent
      .invokeMethod<void>(
          'call-command', {...command.toMap(), 'token': token}));
  await controller.initialize();
  await current.setWindowMethodHandler(controller.handle);
  runApp(_CallWindowApp(controller));
  await parent.invokeMethod<void>('call-ready', {'token': token});
  return true;
}

/// A call-only process starts no Rust, storage, capture or playback runtime.
Future<void> launchProcessCallWindow() async {
  final pipe = CallWindowPipe(
      stdin.transform(utf8.decoder).transform(const LineSplitter()),
      stdout.writeln,
      outputDone: stdout.done);
  final controller = _CallWindowController((command) async {
    await pipe.invoke('call-command', command.toMap());
  });
  pipe.onMethod = controller.handle;
  pipe.onClosed = () => unawaited(windowManager.destroy());
  await controller.initialize();
  runApp(_CallWindowApp(controller));
  await pipe.invoke('call-ready');
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
        call.busy ||
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
    act(value!.command(value!.phase == CallViewPhase.incoming
        ? CallViewAction.decline
        : CallViewAction.end));
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
