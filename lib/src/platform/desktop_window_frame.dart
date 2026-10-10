import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mosh/src/features/conversation/active_peer_status_drawer.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_title_bar.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';

import 'desktop_caption_buttons.dart';
import 'desktop_chrome_scope.dart';
import 'desktop_window_controller.dart';

/// One persistent titlebar above routed content and the first-run gate.
class DesktopWindowFrame extends ConsumerStatefulWidget {
  const DesktopWindowFrame(
      {super.key,
      required this.controller,
      required this.router,
      required this.child});
  final DesktopWindowController? controller;
  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends ConsumerState<DesktopWindowFrame> {
  bool _showStatus = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c == null) return widget.child;
    final ready = !ref.watch(firstRunEnabledProvider) ||
        ref.watch(firstRunProfileProvider).value?.completed == true;
    final active = ref.watch(activeConversationProvider);
    final narrow = isMobileBreakpoint(context);
    // The titlebar is above the router's Navigator. Its tooltips and diagnostics
    // need an overlay even when the first-run gate has not mounted that router.
    return Navigator(pages: [
      MaterialPage(
          child: ListenableBuilder(
        listenable: widget.router.routeInformationProvider,
        builder: (context, _) {
          final path = widget.router.routeInformationProvider.value.uri.path;
          final chatRoute = ready &&
              (path == AppRoutes.sessions ||
                  path == AppRoutes.chat ||
                  [AppRoutes.dm, AppRoutes.channel, AppRoutes.group]
                      .any((p) => path.startsWith('$p/')));
          final onList = narrow && path == AppRoutes.sessions;
          final hasStatus = chatRoute && !onList && active != null;
          if (!hasStatus) _showStatus = false;
          return _chrome(c,
              chatRoute: chatRoute && !onList,
              hasStatus: hasStatus,
              onToggleChatList:
                  narrow ? () => widget.router.go(AppRoutes.sessions) : null);
        },
      ))
    ], onDidRemovePage: (_) {});
  }

  Widget _chrome(DesktopWindowController c,
          {required bool chatRoute,
          required bool hasStatus,
          VoidCallback? onToggleChatList}) =>
      ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final content = DesktopChromeScope(
                child: Column(children: [
              Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: MoshTitleBar(
                      integrated: true,
                      showChatList: chatRoute,
                      onToggleChatList: onToggleChatList,
                      leading:
                          DesktopCaptionButtons(controller: c, leading: true),
                      trailing:
                          DesktopCaptionButtons(controller: c, leading: false),
                      dragArea: (child) => _dragArea(c, child),
                      onOpenPeerStatus: hasStatus
                          ? () => setState(() => _showStatus = true)
                          : null)),
              Expanded(
                  child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: Stack(children: [
                        Positioned.fill(child: widget.child),
                        if (_showStatus)
                          Positioned.fill(
                              child: ActivePeerStatusDrawer(
                                  onClose: () =>
                                      setState(() => _showStatus = false))),
                      ]))),
            ]));
            return c.platform == TargetPlatform.linux &&
                    !c.maximized &&
                    !c.fullScreen
                ? DragToResizeArea(resizeEdgeSize: 5, child: content)
                : content;
          });

  Widget _dragArea(DesktopWindowController c, Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => unawaited(c.startDragging()),
        onDoubleTap: () => unawaited(c.doubleClick()),
        onSecondaryTap: c.platform == TargetPlatform.macOS
            ? null
            : () => unawaited(c.showMenu()),
        child: child,
      );
}
