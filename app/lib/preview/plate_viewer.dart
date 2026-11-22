import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/plate_project.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import 'model_viewer.dart' show PreviewPainter;
import 'plate_projector.dart';

/// 3D view of one plate. Drag an object to move it, drag the empty bed to turn the view,
/// right or middle mouse button (or two fingers) to pan, mouse wheel or pinch to zoom, double tap to reset.
class PlateViewer extends StatefulWidget {
  const PlateViewer({
    super.key,
    required this.objects,
    required this.bed,
    this.selected,
    this.onSelect,
    this.onMoveStart,
    this.onMove,
    this.onMoveEnd,
    this.topView = false,
  });

  final List<PlateObject> objects;
  final PlateSize bed;
  final int? selected;
  final ValueChanged<int?>? onSelect;
  final VoidCallback? onMoveStart;

  /// New footprint center of the selected object in bed millimetres.
  final void Function(double x, double y)? onMove;
  final VoidCallback? onMoveEnd;

  /// Starts looking straight down (bumped by changing the key).
  final bool topView;

  static const turnSpeed = 0.010;

  @override
  State<PlateViewer> createState() => PlateViewerState();
}

class PlateViewerState extends State<PlateViewer> {
  late PlateCamera _camera = widget.topView ? PlateCamera.top : const PlateCamera();
  PlateCamera _gestureStart = const PlateCamera();
  PlateFrame? _frame;
  Size _size = Size.zero;
  bool _busy = false;
  bool _dirty = false;
  int _generation = 0;

  // Dragging an object: where it was grabbed relative to its center, in bed mm.
  (double, double)? _grab;
  bool _panning = false;
  int _buttons = 0;

  @visibleForTesting
  PlateCamera get camera => _camera;

  @visibleForTesting
  PlateFrame? get frame => _frame;

  void resetView({bool top = false}) {
    _camera = top ? PlateCamera.top : const PlateCamera();
    _render();
  }

  @override
  void didUpdateWidget(PlateViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(old.objects, widget.objects) || old.selected != widget.selected || old.bed != widget.bed) _render();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  List<SceneObject> _scene() => [
        for (final o in widget.objects)
          () {
            final (matrix, sx, sy, sz) = o.placement;
            final b = o.source.mesh.bounds;
            return SceneObject(
              id: o.id,
              triangles: o.source.previewMesh.triangles,
              center: [b.centerX, b.centerY, b.centerZ],
              matrix: matrix,
              shift: [sx, sy, sz],
              color: PixelColors.accent.toARGB32(),
            );
          }(),
      ];

  /// Projects in a short-lived isolate; while one runs, only the newest request is kept.
  Future<void> _render() async {
    if (_size.isEmpty) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    _busy = true;
    final generation = _generation;
    final scene = _scene();
    final camera = _camera;
    final size = _size;
    final bed = widget.bed;
    final selected = widget.selected;
    final offBed = {for (final o in widget.objects) if (!o.fits(bed)) o.id};
    final triangles = scene.fold<int>(0, (sum, o) => sum + o.triangles.length ~/ 9);
    PlateFrame build() => projectPlate(
          objects: scene,
          camera: camera,
          width: size.width,
          height: size.height,
          bedX: bed.x,
          bedY: bed.y,
          bedHeight: bed.height,
          selected: selected,
          offBed: offBed,
        );
    try {
      // Small plates are faster on this thread than the isolate round trip.
      final frame = triangles < 4000 ? build() : await Isolate.run(build);
      if (!mounted || generation != _generation) return;
      setState(() => _frame = frame);
    } finally {
      _busy = false;
      if (_dirty && mounted) {
        _dirty = false;
        unawaited(_render());
      }
    }
  }

  PlateView get _view => PlateView(_camera, _size.width, _size.height, widget.bed.x, widget.bed.y, widget.bed.height);

  void _onPointerDown(PointerDownEvent event) {
    _buttons = event.buttons;
    _down = event.localPosition;
  }

  /// Where the button went down: the gesture is only recognized a few pixels later,
  /// and small objects must be grabbed where the user clicked.
  Offset? _down;

  /// Selects what is under the pointer; clicking the empty bed clears the selection.
  void _onTapUp(TapUpDetails details) {
    if ((_buttons & kPrimaryButton) == 0 && _buttons != 0) return;
    widget.onSelect?.call(_frame?.hit(details.localPosition.dx, details.localPosition.dy));
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _camera;
    _panning = details.pointerCount > 1 || (_buttons & (kSecondaryButton | kTertiaryButton)) != 0;
    _grab = null;
    if (_panning || details.pointerCount > 1) return;
    final at = _down ?? details.localFocalPoint;
    final hit = _frame?.hit(at.dx, at.dy);
    if (hit == null) return;
    widget.onSelect?.call(hit);
    if (widget.onMove == null) return;
    final object = widget.objects.where((o) => o.id == hit).firstOrNull;
    final point = _view.toBed(at.dx, at.dy);
    if (object == null || point == null) return;
    _grab = (point.$1 - object.x, point.$2 - object.y);
    widget.onMoveStart?.call();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final grab = _grab;
    if (grab != null && details.pointerCount == 1) {
      final point = _view.toBed(details.localFocalPoint.dx, details.localFocalPoint.dy);
      if (point != null) widget.onMove?.call(point.$1 - grab.$1, point.$2 - grab.$2);
      return;
    }
    if (details.pointerCount > 1) {
      _camera = _gestureStart.zoomed(details.scale).panned(details.focalPointDelta.dx, details.focalPointDelta.dy);
      _gestureStart = _camera.zoomed(1 / details.scale);
    } else if (_panning) {
      _camera = _camera.panned(details.focalPointDelta.dx, details.focalPointDelta.dy);
    } else {
      _camera = _camera.rotated(details.focalPointDelta.dx * PlateViewer.turnSpeed, details.focalPointDelta.dy * PlateViewer.turnSpeed);
    }
    _render();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_grab != null) widget.onMoveEnd?.call();
    _grab = null;
    _panning = false;
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _camera = _camera.zoomed(event.scrollDelta.dy > 0 ? 1 / 1.12 : 1.12);
      _render();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '3D-Ansicht der Druckplatte. Objekt ziehen verschiebt es, freie Fläche ziehen dreht die Ansicht.',
      image: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size != _size) {
            _size = size;
            WidgetsBinding.instance.addPostFrameCallback((_) => _render());
          }
          final frame = _frame;
          return Listener(
            onPointerDown: _onPointerDown,
            onPointerSignal: _onScroll,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: _onTapUp,
              onDoubleTap: () => resetView(),
              child: ClipRect(
                child: SizedBox.expand(
                  child: frame == null
                      ? const Center(child: PixelText.small('Platte wird gezeichnet …', color: PixelColors.muted))
                      : CustomPaint(painter: PlatePainter(frame, bedBelow: _camera.pitch >= 0)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Bed, grid and objects of a [PlateFrame], same look as the single-model preview.
class PlatePainter extends CustomPainter {
  PlatePainter(this.frame, {this.bedBelow = true});

  final PlateFrame frame;
  final bool bedBelow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // A frame computed for another size stays centered until the next one arrives.
    canvas.translate((size.width - frame.width) / 2, (size.height - frame.height) / 2);
    if (bedBelow) {
      _bed(canvas, 1);
      _objects(canvas);
    } else {
      _objects(canvas);
      _bed(canvas, 0.55);
    }
    canvas.restore();
  }

  void _objects(Canvas canvas) {
    if (frame.positions.isEmpty) return;
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, frame.positions, colors: frame.colors);
    canvas.drawVertices(vertices, BlendMode.dst, Paint()..isAntiAlias = true);
    vertices.dispose();
  }

  void _bed(Canvas canvas, double opacity) {
    final b = frame.bed;
    final outline = Path()
      ..moveTo(b[0], b[1])
      ..lineTo(b[2], b[3])
      ..lineTo(b[4], b[5])
      ..lineTo(b[6], b[7])
      ..close();
    canvas.drawPath(outline, Paint()..color = PreviewPainter.bedColor.withValues(alpha: opacity));
    final grid = Paint()
      ..color = PreviewPainter.gridColor.withValues(alpha: PreviewPainter.gridColor.a * opacity)
      ..strokeWidth = 1
      ..isAntiAlias = true;
    final g = frame.grid;
    for (var i = 0; i + 3 < g.length; i += 4) {
      canvas.drawLine(Offset(g[i], g[i + 1]), Offset(g[i + 2], g[i + 3]), grid);
    }
    canvas.drawPath(
      outline,
      Paint()
        ..color = PreviewPainter.edgeColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = true,
    );
    // Front-left corner mark, like the printer's origin.
    canvas.drawCircle(Offset(b[0], b[1]), 4, Paint()..color = PixelColors.accent.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(PlatePainter old) => old.frame != frame || old.bedBelow != bedBelow;
}
