// The recording side of scene_export.dart: a Canvas and a PaintingContext
// that capture every paint call in global coordinates instead of drawing.
part of 'scene_export.dart';

class _State {
  _State(this.matrix, this.opacity);
  Matrix4 matrix;
  double opacity;
  int scopes = 0;
}

/// A Canvas that records geometry in global coordinates.
class _RecordingCanvas implements Canvas {
  _RecordingCanvas(this.exporter);
  final _Exporter exporter;
  final List<_State> _stack = [_State(Matrix4.identity(), 1)];
  _State get _s => _stack.last;

  Rect _global(Rect r) => MatrixUtils.transformRect(_s.matrix, r);
  double get _scale {
    final m = _s.matrix.storage;
    return math.sqrt(m[0] * m[0] + m[1] * m[1]);
  }

  @override
  void save() => _stack.add(_State(_s.matrix.clone(), _s.opacity));
  @override
  void saveLayer(Rect? bounds, Paint paint) {
    save();
    _s.opacity *= paint.color.a;
  }

  @override
  void restore() {
    if (_stack.length == 1) return;
    final s = _stack.removeLast();
    for (var i = 0; i < s.scopes; i++) {
      exporter.popScope();
    }
  }

  @override
  void restoreToCount(int count) {
    while (_stack.length > math.max(1, count)) {
      restore();
    }
  }

  @override
  int getSaveCount() => _stack.length;
  @override
  void translate(double dx, double dy) =>
      _s.matrix.translateByDouble(dx, dy, 0, 1);
  @override
  void scale(double sx, [double? sy]) =>
      _s.matrix.scaleByDouble(sx, sy ?? sx, 1, 1);
  @override
  void rotate(double radians) => _s.matrix.rotateZ(radians);
  @override
  void skew(double sx, double sy) {}
  @override
  void transform(Float64List matrix4) =>
      _s.matrix.multiply(Matrix4.fromFloat64List(matrix4));
  @override
  Float64List getTransform() => _s.matrix.storage;

  void _clip(Rect local, {double radius = 0}) {
    final g = _global(local);
    final scope = _Scope('clip', g)..clip = {'radius': _r(radius * _scale)};
    exporter.pushScope(scope);
    _s.scopes++;
  }

  @override
  void clipRect(Rect rect,
      {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    if (clipOp == ui.ClipOp.intersect) _clip(rect);
  }

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) =>
      _clip(rrect.outerRect, radius: rrect.tlRadiusX);
  @override
  void clipRSuperellipse(RSuperellipse rse, {bool doAntiAlias = true}) =>
      _clip(rse.outerRect, radius: rse.tlRadiusX);
  @override
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      _clip(path.getBounds(), radius: _cornerRadius(path));

  /// Corner radius of a rounded-rect path: the diagonal from the top-left
  /// corner enters a circular corner of radius r at r·(1 − 1/√2).
  static double _cornerRadius(Path path) {
    final b = path.getBounds();
    final limit = math.min(b.width, b.height) / 2;
    var t = 0.0;
    while (t < limit &&
        !path.contains(Offset(b.left + t + 0.01, b.top + t + 0.01))) {
      t += 0.25;
    }
    if (t < 0.25) return 0;
    var lo = t - 0.25, hi = t;
    for (var i = 0; i < 8; i++) {
      final mid = (lo + hi) / 2;
      final inside =
          path.contains(Offset(b.left + mid + 0.01, b.top + mid + 0.01));
      inside ? hi = mid : lo = mid;
    }
    // Nearest half pixel: shapes in the app use whole or half radii.
    return (hi / (1 - 1 / math.sqrt2) * 2).roundToDouble() / 2;
  }

  @override
  Rect getLocalClipBounds() => Rect.largest;
  @override
  Rect getDestinationClipBounds() => Rect.largest;

  Map<String, Object?> _paint(Paint p) {
    final out = <String, Object?>{};
    if (p.shader != null) {
      final gradient = exporter.currentGradient();
      if (gradient == null) return const {'skip': true};
      out['gradient'] = gradient;
    }
    final c = _color(p.color, _s.opacity);
    if (p.style == PaintingStyle.stroke) {
      out['stroke'] = c;
      out['sw'] = _r(math.max(p.strokeWidth, 1) * _scale);
    } else {
      out['fill'] = c;
    }
    final mask = p.maskFilter?.toString();
    if (mask != null) {
      final sigma = RegExp(r'([\d.]+)\)').firstMatch(mask)?.group(1);
      if (sigma != null) out['blur'] = double.parse(sigma) * _scale;
    }
    return out;
  }

  void _shape(String kind, Rect local, Paint p,
      [Map<String, Object?> extra = const {}]) {
    final paint = _paint(p);
    if (paint['skip'] == true) return;
    exporter.add({'t': kind, 'r': _rect(_global(local)), ...paint, ...extra});
  }

  @override
  void drawColor(Color color, BlendMode blendMode) =>
      drawPaint(Paint()..color = color);
  @override
  void drawPaint(Paint paint) {
    final clip = exporter.clipRect();
    if (clip == null) return;
    final paintJson = _paint(paint);
    if (paintJson['skip'] == true) return;
    exporter.add({'t': 'rect', 'r': _rect(clip), ...paintJson});
  }

  @override
  void drawRect(Rect rect, Paint paint) => _shape('rect', rect, paint);
  @override
  void drawRRect(RRect rrect, Paint paint) =>
      _shape('rect', rrect.outerRect, paint, {
        'radius': _r(rrect.tlRadiusX * _scale),
        'radii': [
          for (final v in [
            rrect.tlRadiusX,
            rrect.trRadiusX,
            rrect.brRadiusX,
            rrect.blRadiusX
          ])
            _r(v * _scale)
        ]
      });
  @override
  void drawRSuperellipse(RSuperellipse rse, Paint paint) => _shape(
      'rect', rse.outerRect, paint, {'radius': _r(rse.tlRadiusX * _scale)});
  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    final p = _paint(paint);
    if (p['skip'] == true) return;
    exporter.add({
      't': 'rect',
      'r': _rect(_global(outer.outerRect)),
      'radius': _r(outer.tlRadiusX * _scale),
      'stroke': p['fill'] ?? p['stroke'],
      'sw': _r((inner.left - outer.left) * _scale),
      'inside': true,
    });
  }

  @override
  void drawOval(Rect rect, Paint paint) => _shape('ellipse', rect, paint);
  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      _shape('ellipse', Rect.fromCircle(center: c, radius: radius), paint);
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy),
      paint..style = PaintingStyle.stroke);
  @override
  void drawArc(
      Rect rect, double start, double sweep, bool useCenter, Paint paint) {
    final path = Path();
    if (useCenter) path.moveTo(rect.center.dx, rect.center.dy);
    path.arcTo(rect, start, sweep, !useCenter);
    if (useCenter) path.close();
    drawPath(path, paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    final p = _paint(paint);
    if (p['skip'] == true) return;
    final d = StringBuffer();
    for (final metric in path.computeMetrics()) {
      final steps = math.min(400, math.max(2, metric.length.ceil()));
      for (var i = 0; i <= steps; i++) {
        final t = metric.getTangentForOffset(metric.length * i / steps);
        if (t == null) continue;
        final g = MatrixUtils.transformPoint(_s.matrix, t.position);
        d.write('${i == 0 ? 'M' : 'L'}${_r(g.dx)} ${_r(g.dy)} ');
      }
      if (metric.isClosed) d.write('Z ');
    }
    if (d.isEmpty) return;
    exporter.add({
      't': 'path',
      'r': _rect(_global(path.getBounds())),
      'd': d.toString().trim(),
      ...p
    });
  }

  @override
  void drawShadow(
      Path path, Color color, double elevation, bool transparentOccluder) {
    exporter.add({
      't': 'shadow',
      'r': _rect(_global(path.getBounds())),
      'elevation': _r(elevation),
      'color': _color(color, _s.opacity),
    });
  }

  void _image(ui.Image image, Rect dst, Paint paint) {
    exporter.add({
      't': 'image',
      'r': _rect(_global(dst)),
      'img': exporter.imageKey(image),
      'opacity': _r(paint.color.a * _s.opacity),
    });
  }

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) => _image(image,
      offset & Size(image.width.toDouble(), image.height.toDouble()), paint);
  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      _image(image, dst, paint);
  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) =>
      _image(image, dst, paint);

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      exporter.text(paragraph, offset, _s.matrix, _s.opacity);

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {
    for (final pt in points) {
      _shape(
          'ellipse',
          Rect.fromCircle(center: pt, radius: paint.strokeWidth / 2),
          Paint()..color = paint.color);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// PaintingContext that paints every child inline into the recording canvas.
class _RecordingContext extends PaintingContext {
  _RecordingContext(this.exporter) : super(ContainerLayer(), Rect.largest);
  final _Exporter exporter;
  late final _RecordingCanvas rec = _RecordingCanvas(exporter);

  @override
  Canvas get canvas => rec;

  @override
  void paintChild(RenderObject child, Offset offset) {
    Rect? rect;
    if (child is RenderBox && child.hasSize) {
      rect = MatrixUtils.transformRect(rec._s.matrix, offset & child.size);
    }
    exporter.pushRenderScope(child, rect);
    // ignore: invalid_use_of_protected_member
    child.paint(this, offset);
    exporter.popScope();
  }

  @override
  void pushLayer(
      ContainerLayer childLayer, PaintingContextCallback painter, Offset offset,
      {Rect? childPaintBounds}) {
    rec.save();
    switch (childLayer) {
      case OpacityLayer(:final alpha, offset: final o):
        rec.translate(o.dx, o.dy);
        rec._s.opacity *= (alpha ?? 255) / 255;
      case LeaderLayer(:final link, offset: final o):
        rec.translate(o.dx, o.dy);
        exporter.leaders[link] = rec._s.matrix.clone();
      case FollowerLayer(
          :final link,
          :final linkedOffset,
          :final unlinkedOffset,
          :final showWhenUnlinked
        ):
        final leader = exporter.leaders[link];
        if (leader != null) {
          rec._s.matrix = leader.clone()
            ..translateByDouble(
                linkedOffset?.dx ?? 0, linkedOffset?.dy ?? 0, 0, 1);
        } else if (showWhenUnlinked ?? false) {
          rec.translate(unlinkedOffset?.dx ?? 0, unlinkedOffset?.dy ?? 0);
        } else {
          rec.restore();
          return;
        }
      case BackdropFilterLayer(:final filter):
        final sigma = RegExp(r'blur\(([\d.]+)').firstMatch('$filter')?.group(1);
        final clip = exporter.clipRect();
        if (sigma != null && clip != null) {
          exporter.add(
              {'t': 'backdrop', 'r': _rect(clip), 'blur': double.parse(sigma)});
        }
      case TransformLayer(:final transform):
        if (transform != null) rec.transform(transform.storage);
      // After TransformLayer, which is itself an OffsetLayer.
      case OffsetLayer(offset: final o):
        rec.translate(o.dx, o.dy);
      case ClipRectLayer(:final clipRect):
        if (clipRect != null) rec.clipRect(clipRect);
      case ClipRRectLayer(:final clipRRect):
        if (clipRRect != null) rec.clipRRect(clipRRect);
      case ClipRSuperellipseLayer(:final clipRSuperellipse):
        if (clipRSuperellipse != null) rec.clipRSuperellipse(clipRSuperellipse);
      case ClipPathLayer(:final clipPath):
        if (clipPath != null) rec.clipPath(clipPath);
      default:
        break;
    }
    painter(this, offset);
    rec.restore();
  }

  @override
  void addLayer(Layer layer) {
    if (layer is TextureLayer) {
      exporter.add({
        't': 'rect',
        'r': _rect(MatrixUtils.transformRect(rec._s.matrix, layer.rect)),
        'fill': [0, 0, 0, 1],
        'video': true
      });
    }
  }

  @override
  void setIsComplexHint() {}
  @override
  void setWillChangeHint() {}
  @override
  // Nothing is recorded into a picture, so there is nothing to stop.
  // ignore: must_call_super
  void stopRecordingIfNeeded() {}
}
