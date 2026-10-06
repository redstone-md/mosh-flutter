import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mosh/src/app/mosh_menu_item.dart';
import 'package:mosh/src/app/mosh_menu_theme.dart';

part 'message_menu_layout.dart';

@immutable
class MessageMenuAction {
  const MessageMenuAction(this.label, this.icon, this.run,
      {this.danger = false});
  final String label;
  final IconData icon;
  final VoidCallback run;
  final bool danger;
}

/// One animated menu owner for the conversation's text and non-text rows.
class MessageContextMenu extends StatefulWidget {
  const MessageContextMenu({
    super.key,
    required this.selectionFocus,
    required this.onDismiss,
    required this.child,
  });
  final FocusNode selectionFocus;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<MessageContextMenu> createState() => MessageContextMenuState();
}

class MessageContextMenuState extends State<MessageContextMenu>
    with SingleTickerProviderStateMixin {
  final _menu = MenuController();
  final _focus = FocusScopeNode(debugLabel: 'Message menu');
  late final AnimationController _motion;
  Animation<double> _opacity = const AlwaysStoppedAnimation(0);
  Animation<double> _scale = const AlwaysStoppedAnimation(0.97);
  List<MessageMenuAction> _actions = const [];
  FocusNode? _originFocus;
  VoidCallback? _hideOverlay;
  bool _closing = false;

  bool get isOpen => _menu.isOpen && !_closing;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this)..addStatusListener(_settled);
  }

  void show(List<MessageMenuAction> actions, Offset globalPosition,
      FocusNode originFocus,
      {bool fromKeyboard = false}) {
    if (actions.isEmpty) return;
    _actions = actions;
    _originFocus = originFocus;
    final box = context.findRenderObject()! as RenderBox;
    _menu.open(position: box.globalToLocal(globalPosition));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isOpen) return;
      if (fromKeyboard) {
        _focus.nextFocus();
      } else {
        _focus.requestFocus();
      }
    });
  }

  void dismiss() {
    if (!isOpen) return;
    widget.onDismiss();
    close();
  }

  void close() {
    if (mounted && isOpen) _menu.close();
  }

  void _animate({required bool closing}) {
    final opacity = _opacity.value;
    final scale = _scale.value;
    _closing = closing;
    final curve =
        _motion.drive(CurveTween(curve: const Cubic(0.22, 1, 0.36, 1)));
    _opacity = Tween(begin: opacity, end: closing ? 0.0 : 1.0).animate(curve);
    _scale = Tween(begin: scale, end: closing ? 0.99 : 1.0).animate(curve);
    _motion.duration = Duration(milliseconds: closing ? 150 : 250);
    setState(() {});
    _motion.forward(from: 0);
    if (MediaQuery.disableAnimationsOf(context)) _motion.value = 1;
  }

  void _settled(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_closing) return;
    final hide = _hideOverlay;
    _hideOverlay = null;
    hide?.call();
    _scale = const AlwaysStoppedAnimation(0.97);
  }

  void _open(Offset? position, VoidCallback showOverlay) {
    _hideOverlay = null;
    showOverlay();
    _animate(closing: false);
  }

  void _close(VoidCallback hideOverlay) {
    if (_closing) return;
    _hideOverlay = hideOverlay;
    if (_originFocus?.context != null) _originFocus!.requestFocus();
    _animate(closing: true);
  }

  void _run(MessageMenuAction action) {
    if (!mounted || !isOpen) return;
    _menu.close();
    action.run();
  }

  @override
  void dispose() {
    _motion.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawMenuAnchor(
        controller: _menu,
        onOpenRequested: _open,
        onCloseRequested: _close,
        overlayBuilder: _overlay,
        child: widget.child,
      );

  Widget _overlay(BuildContext context, RawMenuOverlayInfo info) {
    return FocusScope(
      node: _focus,
      parentNode: widget.selectionFocus,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
              dismiss();
              return null;
            }),
          },
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) => _animatedPanel(context, info),
          ),
        ),
      ),
    );
  }

  Widget _animatedPanel(BuildContext context, RawMenuOverlayInfo info) {
    final position = info.anchorRect.topLeft + (info.position ?? Offset.zero);
    // Scaffold removes body insets; a floating menu still shares the full view.
    final view = MediaQueryData.fromView(View.of(context));
    return ExcludeFocus(
      excluding: _closing,
      child: ExcludeSemantics(
        excluding: _closing,
        child: IgnorePointer(
          ignoring: _closing,
          child: Flow(
            delegate: _MessageMenuLayout(
                position, view.padding + view.viewInsets, _opacity, _scale),
            children: [
              TapRegion(
                groupId: info.tapRegionGroupId,
                child: TapRegion(
                  groupId: SelectableRegion,
                  child: _MessageMenuPanel(actions: _actions, onSelect: _run),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageMenuPanel extends StatelessWidget {
  const _MessageMenuPanel({required this.actions, required this.onSelect});
  final List<MessageMenuAction> actions;
  final ValueChanged<MessageMenuAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final style = MoshMenuTheme.panel(Theme.of(context).colorScheme).style!;
    const states = <WidgetState>{};
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Material(
        key: const ValueKey('message-context-menu'),
        color: style.backgroundColor!.resolve(states),
        surfaceTintColor: style.surfaceTintColor!.resolve(states),
        shadowColor: style.shadowColor!.resolve(states),
        elevation: style.elevation!.resolve(states)!,
        shape: style.shape!.resolve(states),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Padding(
            padding: style.padding!.resolve(states)!,
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in actions)
                    MoshMenuItem(
                      label: action.label,
                      icon: action.icon,
                      danger: action.danger,
                      onPressed: () => onSelect(action),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
