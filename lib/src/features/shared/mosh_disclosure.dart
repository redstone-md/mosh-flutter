import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'focus_ring.dart';

/// The Disclosure card: a line that opens what is folded under it. The caret
/// turns and takes the accent while it is open.
///
/// [child] is built when the line is first opened and keeps its state while
/// it is folded again. Given a [PageStorageKey], the line remembers whether
/// it was open when its screen is rebuilt.
class MoshDisclosure extends StatefulWidget {
  const MoshDisclosure({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<MoshDisclosure> createState() => _MoshDisclosureState();
}

class _MoshDisclosureState extends State<MoshDisclosure> {
  bool _open = false;
  bool _visited = false;

  /// The storage of the screen, used only under a key of this line's own:
  /// without one the slot it would read is its scroller's offset.
  PageStorageBucket? get _storage =>
      widget.key is PageStorageKey ? PageStorage.maybeOf(context) : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_visited && _storage?.readState(context) == true) {
      _open = _visited = true;
    }
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      _visited = true;
    });
    _storage?.writeState(context, _open);
  }

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MoshMotion.effectsDefault.duration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line(context, motion),
        AnimatedSize(
          duration: motion,
          curve: MoshMotion.effectsDefault.curve,
          alignment: Alignment.topCenter,
          child: _visited
              ? Visibility(
                  visible: _open, maintainState: true, child: widget.child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// The line itself: its label, and the caret that turns when it opens.
  Widget _line(BuildContext context, Duration motion) {
    final colors = MoshColors.of(context);
    return Semantics(
      expanded: _open,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _toggle,
          borderRadius: MoshShapes.control,
          overlayColor: MoshState.layer(colors.onSurface),
          child: FocusRing(
            radius: MoshShapes.control,
            child: Container(
              constraints: BoxConstraints(
                  minHeight: MoshControl.height(Theme.of(context).platform)),
              padding: const EdgeInsetsDirectional.only(
                  start: MoshSpace.s3, end: MoshSpace.s2),
              child: Row(children: [
                Expanded(
                  child: Text(widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge!
                          .copyWith(color: colors.onSurfaceVariant)),
                ),
                const SizedBox(width: MoshSpace.s2),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: motion,
                  curve: MoshMotion.effectsDefault.curve,
                  child: Icon(MoshIcons.expandMore,
                      size: MoshSpace.s5,
                      color: _open ? colors.primary : colors.onSurfaceVariant),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
