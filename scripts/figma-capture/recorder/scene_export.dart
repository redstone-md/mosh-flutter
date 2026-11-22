// Records what the live Flutter tree paints and writes it as a JSON scene
// that scripts/figma-capture/build.mjs turns into editable Figma layers.
//
// Usage inside a testWidgets body, after the screen settles (the scenario
// harness does this for every scene):
//   await exportScene(tester, 'chat.dm.desktop', 'Chat / DM', outDir: dir);
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

part 'recording_canvas.dart';

/// Widget classes declared in lib/: layers are named after the nearest one.
final Set<String> _libWidgets = {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      for (final m in RegExp(
              r'^class (\w+)(?:<[^{]*?>)? extends \w*(Stateless|Stateful|Consumer|Animated)\w*Widget\b',
              multiLine: true)
          .allMatches(file.readAsStringSync()))
        m[1]!,
};

String? _flags(Map<String, bool> flags) {
  final on = [
    for (final MapEntry(:key, :value) in flags.entries)
      if (value) key
  ];
  return on.isEmpty ? null : on.join(' ');
}

/// The Material control [w] is, or null. Layers record the nearest one inside
/// their lib widget, so the component inventory sees the buttons, fields and
/// switches lib widgets build. Subclasses (FilledButton.icon) count as their base.
String? _controlKind(Widget w) => switch (w) {
      FilledButton() => 'FilledButton',
      OutlinedButton() => 'OutlinedButton',
      TextButton() => 'TextButton',
      ElevatedButton() => 'ElevatedButton',
      IconButton() => 'IconButton',
      MenuItemButton() => 'MenuItemButton',
      PopupMenuItem() => 'PopupMenuItem',
      TextField() => 'TextField',
      Switch() => 'Switch',
      Checkbox() => 'Checkbox',
      ChoiceChip() => 'ChoiceChip',
      ActionChip() => 'ActionChip',
      Slider() => 'Slider',
      CircularProgressIndicator() => 'CircularProgressIndicator',
      LinearProgressIndicator() => 'LinearProgressIndicator',
      ListTile() => 'ListTile',
      ExpansionTile() => 'ExpansionTile',
      Dialog() => 'Dialog',
      Card() => 'Card',
      Divider() || VerticalDivider() => 'Divider',
      AppBar() => 'AppBar',
      _ => null,
    };

/// The non-default state of control [w]: "disabled", "on disabled", "error"…
String? _controlState(Widget w) => _flags(switch (w) {
      ButtonStyleButton(:final enabled) ||
      PopupMenuItem(:final enabled) ||
      ListTile(:final enabled) =>
        {'disabled': !enabled},
      IconButton(:final onPressed, :final isSelected) => {
          'disabled': onPressed == null,
          'selected': isSelected == true,
        },
      MenuItemButton(:final onPressed) || ActionChip(:final onPressed) => {
          'disabled': onPressed == null,
        },
      TextField(:final enabled, :final decoration) => {
          'disabled': enabled == false,
          'error': decoration?.errorText != null || decoration?.error != null,
        },
      Switch(:final value, :final onChanged) => {
          (value ? 'on' : 'off'): true,
          'disabled': onChanged == null,
        },
      Checkbox(:final value, :final onChanged) => {
          (value == true ? 'checked' : 'unchecked'): true,
          'disabled': onChanged == null,
        },
      ChoiceChip(:final selected) => {'selected': selected},
      Slider(:final onChanged) => {'disabled': onChanged == null},
      ProgressIndicator(:final value) => {'determinate': value != null},
      _ => const {},
    });

double _r(double v) =>
    v.isFinite ? (v * 100).roundToDouble() / 100 : (v > 0 ? 100000 : -100000);

Map<String, Object?> _rect(Rect r) =>
    {'x': _r(r.left), 'y': _r(r.top), 'w': _r(r.width), 'h': _r(r.height)};

double _c(double v) => (v * 10000).roundToDouble() / 10000;

List<double> _color(Color c, double opacity) =>
    [_c(c.r), _c(c.g), _c(c.b), _c(c.a * opacity)];

/// A Material control instance that paints a layer.
typedef _Control = ({String kind, String? state, int id});

/// A painted scope: one render object, one clip, or the root.
class _Scope {
  _Scope(this.kind, this.rect, {this.name, this.lib, this.libId, this.control});
  final String kind;
  final Rect? rect;
  final String? name;
  final String? lib;
  final int? libId;
  final _Control? control;
  final List<Object> children = [];
  Map<String, Object?>? clip;

  Map<String, Object?> toJson() => {
        't': kind,
        if (name != null) 'name': name,
        if (lib != null) 'lib': lib,
        if (libId != null) 'libId': libId,
        if (control case final c?) ...{
          'control': c.kind,
          if (c.state != null) 'controlState': c.state,
          'controlId': c.id,
        },
        if (rect != null) ...{'r': _rect(rect!)},
        if (clip != null) 'clip': clip,
        'c': [for (final c in children) c is _Scope ? c.toJson() : c],
      };
}

class _Exporter {
  final _Scope root = _Scope('root', null);
  late final List<_Scope> _scopes = [root];
  final List<RenderObject?> _owners = [null];
  final Map<ui.Image, String> images = {};
  final Map<LayerLink, Matrix4> leaders = {};

  void pushScope(_Scope scope) {
    _scopes.last.children.add(scope);
    _scopes.add(scope);
    _owners.add(_owners.last);
  }

  void popScope() {
    if (_scopes.length > 1) {
      _scopes.removeLast();
      _owners.removeLast();
    }
  }

  void pushRenderScope(RenderObject ro, Rect? rect) {
    final (lib, libId, name, control) = _names(ro);
    final scope =
        _Scope('g', rect, name: name, lib: lib, libId: libId, control: control);
    _scopes.last.children.add(scope);
    _scopes.add(scope);
    _owners.add(ro);
  }

  void add(Map<String, Object?> node) => _scopes.last.children.add(node);

  Rect? clipRect() {
    for (final s in _scopes.reversed) {
      if (s.rect != null) return s.rect;
    }
    return null;
  }

  String imageKey(ui.Image image) =>
      images.putIfAbsent(image, () => 'img${images.length}');

  Map<String, Object?>? currentGradient() {
    final ro = _owners.last;
    final decoration = switch (ro) {
      RenderDecoratedBox(:final decoration) => decoration,
      _ => null,
    };
    final gradient = decoration is BoxDecoration ? decoration.gradient : null;
    if (gradient is! LinearGradient) return null;
    final begin = gradient.begin.resolve(TextDirection.ltr);
    final end = gradient.end.resolve(TextDirection.ltr);
    return {
      'type': 'linear',
      'begin': [begin.x, begin.y],
      'end': [end.x, end.y],
      'colors': [for (final c in gradient.colors) _color(c, 1)],
      'stops': gradient.stops,
    };
  }

  /// The render object's widget type, its nearest lib widget and the nearest
  /// Material control between the two.
  (String?, int?, String, _Control?) _names(RenderObject ro) {
    final creator = ro.debugCreator;
    final element = creator is DebugCreator ? creator.element : null;
    final type = element?.widget.runtimeType.toString().split('<').first ??
        ro.runtimeType.toString();
    String? lib;
    int? libId;
    _Control? control;
    bool visit(Element e) {
      final t = e.widget.runtimeType.toString().split('<').first;
      if (_libWidgets.contains(t)) {
        lib = t;
        libId = identityHashCode(e);
        return false;
      }
      if (control == null) {
        if (_controlKind(e.widget) case final kind?) {
          control = (
            kind: kind,
            state: _controlState(e.widget),
            id: identityHashCode(e)
          );
        }
      }
      return true;
    }

    if (element != null && visit(element)) element.visitAncestorElements(visit);
    return (lib, libId, type, control);
  }

  void text(
      ui.Paragraph paragraph, Offset offset, Matrix4 matrix, double opacity) {
    final ro = _owners.last;
    final InlineSpan? span = switch (ro) {
      RenderParagraph(:final text) => text,
      RenderEditable(:final text) => text,
      _ => null,
    };
    if (span == null) return;
    final buffer = StringBuffer();
    final runs = <Map<String, Object?>>[];
    void visit(InlineSpan s, TextStyle parent) {
      final style = parent.merge(s.style);
      if (s is TextSpan) {
        final t = s.text ?? '';
        if (t.isNotEmpty) {
          runs.add({
            's': buffer.length,
            'e': buffer.length + t.length,
            ...?_style(style, opacity)
          });
          buffer.write(t);
        }
        for (final c in s.children ?? const <InlineSpan>[]) {
          visit(c, style);
        }
      } else {
        buffer.write('￼');
      }
    }

    visit(span, const TextStyle());
    final m = matrix.storage;
    final scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    if ((scale - 1).abs() > 0.01) {
      for (final run in runs) {
        run['size'] = _r((run['size']! as num) * scale);
        if (run['ls'] != null) run['ls'] = _r((run['ls']! as num) * scale);
      }
    }
    final lines = paragraph.computeLineMetrics();
    final left =
        lines.isEmpty ? 0.0 : lines.map((l) => l.left).reduce(math.min);
    final single = lines.length == 1 && !paragraph.didExceedMaxLines;
    final local = Rect.fromLTWH(offset.dx + (single ? left : 0), offset.dy,
        single ? paragraph.longestLine : paragraph.width, paragraph.height);
    final align = switch (ro) {
      RenderParagraph(:final textAlign) => textAlign.name,
      RenderEditable(:final textAlign) => textAlign.name,
      _ => 'start',
    };
    final maxLines = switch (ro) {
      RenderParagraph(:final maxLines) => maxLines,
      RenderEditable(:final maxLines) => maxLines,
      _ => null,
    };
    final angle = math.atan2(m[1], m[0]) * 180 / math.pi;
    // Flutter breaks unspaced runs (tokens, URLs) mid-word; Figma does not,
    // so those break points travel with the text.
    final plain = buffer.toString();
    final breaks = <int>[];
    var pos = 0;
    while (pos < plain.length) {
      final end = paragraph.getLineBoundary(TextPosition(offset: pos)).end;
      if (end <= pos || end >= plain.length) break;
      final before = plain[end - 1], after = plain[end];
      if (before.trim().isNotEmpty &&
          after.trim().isNotEmpty &&
          before != '-') {
        breaks.add(end);
      }
      pos = end;
    }
    add({
      't': 'text',
      if (angle.abs() > 0.5) 'rot': _r(angle),
      if (breaks.isNotEmpty) 'breaks': breaks,
      'r': _rect(MatrixUtils.transformRect(matrix, local)),
      'text': buffer.toString(),
      'runs': runs,
      'lines': lines.length,
      'align': align,
      'ellipsis': ro is RenderParagraph &&
              ro.overflow == TextOverflow.ellipsis &&
              paragraph.didExceedMaxLines
          ? (maxLines ?? 1)
          : null,
      'editable': ro is RenderEditable,
    });
  }

  Map<String, Object?>? _style(TextStyle s, double opacity) {
    final color = s.foreground?.color ?? s.color ?? const Color(0xFF000000);
    return {
      'family': s.fontFamily,
      'size': s.fontSize ?? 14,
      'weight': s.fontWeight?.value ?? 400,
      if (s.fontStyle == FontStyle.italic) 'italic': true,
      'color': _color(color, opacity),
      if (s.height != null) 'height': s.height,
      if (s.letterSpacing != null && s.letterSpacing != 0)
        'ls': s.letterSpacing,
      if (s.decoration == TextDecoration.underline) 'underline': true,
      if (s.decoration == TextDecoration.lineThrough) 'strike': true,
    };
  }
}

/// Records the current frame of [tester] and writes
/// [outDir]/scene.json, its images and the reference render ref.png.
Future<void> exportScene(WidgetTester tester, String id, String title,
    {required String outDir, String? note}) async {
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element));
  }
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final size = view.size;
  final dir = Directory(outDir);
  // The reference render comes first: recording repoints render objects at
  // detached layers, so the live tree is repainted afterwards.
  final rootLayer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    dir.createSync(recursive: true);
    final shot = await rootLayer.toImage(Offset.zero & size);
    final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/ref.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    shot.dispose();
  });
  final exporter = _Exporter();
  _RecordingContext(exporter).paintChild(view.child!, Offset.zero);
  await tester.runAsync(() async {
    for (final entry in exporter.images.entries) {
      final data = await entry.key.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/${entry.value}.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    }
  });
  void repaint(RenderObject ro) {
    ro.markNeedsPaint();
    ro.visitChildren(repaint);
  }

  repaint(view.child!);
  await tester.pump();
  File('${dir.path}/scene.json').writeAsStringSync(jsonEncode({
    'id': id,
    'title': title,
    if (note != null) 'note': note,
    'w': size.width,
    'h': size.height,
    'tree': exporter.root.toJson(),
  }));
}
