import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../model/mesh.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import 'preview_worker.dart';
import 'projector.dart';

/// Smooth 3D preview drawn as vector triangles at full display resolution.
/// One finger turns the model, two fingers zoom, double tap resets the view.
class ModelViewer extends StatefulWidget {
  const ModelViewer({super.key, required this.mesh, required this.bedX, required this.bedY, this.color = PixelColors.accent, this.scale = 1});

  final Mesh mesh;
  final double bedX;
  final double bedY;
  final Color color;

  /// Uniform size factor around the model's base center.
  final double scale;

  /// Upper bound of preview triangles; slicing always uses the full model.
  static const maxTriangles = 60000;

  /// Radians per dragged logical pixel.
  static const turnSpeed = 0.012;

  @override
  State<ModelViewer> createState() => ModelViewerState();
}

class ModelViewerState extends State<ModelViewer> {
  PreviewWorker? _worker;
  StreamSubscription<ProjectedFrame>? _sub;
  ProjectedFrame? _frame;
  OrbitCamera _camera = const OrbitCamera();
  OrbitCamera _gestureStart = const OrbitCamera();
  Size _size = Size.zero;
  Object? _error;
  int _generation = 0;

  @visibleForTesting
  OrbitCamera get camera => _camera;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(ModelViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.mesh != widget.mesh || old.color != widget.color || old.bedX != widget.bedX || old.bedY != widget.bedY) {
      _start();
    } else if (old.scale != widget.scale) {
      _render();
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _stop();
    try {
      final mesh = widget.mesh.decimate(ModelViewer.maxTriangles);
      final b = mesh.bounds;
      final worker = await PreviewWorker.spawn(PreviewScene(
        triangles: mesh.triangles,
        center: [b.centerX, b.centerY, b.centerZ],
        base: [b.centerX, b.centerY, b.minZ],
        radius: b.radius,
        bedX: widget.bedX,
        bedY: widget.bedY,
        modelColor: widget.color.toARGB32(),
      ));
      if (!mounted || generation != _generation) {
        worker.dispose();
        return;
      }
      _worker = worker;
      _sub = worker.frames.listen((frame) {
        if (mounted) setState(() => _frame = frame);
      });
      _render();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _worker?.dispose();
    _worker = null;
  }

  void _render() {
    if (_size.isEmpty) return;
    _worker?.render(_camera.withScale(widget.scale), _size.width, _size.height);
  }

  @override
  void dispose() {
    _generation++;
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '3D-Vorschau. Mit einem Finger drehen, mit zwei Fingern zoomen, doppelt tippen setzt die Ansicht zurück.',
      image: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size != _size) {
            _size = size;
            WidgetsBinding.instance.addPostFrameCallback((_) => _render());
          }
          final frame = _frame;
          return GestureDetector(
            onScaleStart: (_) => _gestureStart = _camera,
            onScaleUpdate: (d) {
              // Dragging right turns the model to the right; dragging down tilts the view up towards the top.
              _camera = d.pointerCount > 1
                  ? _gestureStart.zoomed(d.scale)
                  : _camera.rotated(d.focalPointDelta.dx * ModelViewer.turnSpeed, d.focalPointDelta.dy * ModelViewer.turnSpeed);
              _render();
            },
            onDoubleTap: () {
              _camera = const OrbitCamera();
              _render();
            },
            child: ClipRect(
              child: SizedBox.expand(
                child: _error != null
                    ? const Center(child: PixelText('Vorschau nicht möglich', color: PixelColors.red))
                    : frame == null
                        ? const Center(child: _Loading())
                        : CustomPaint(painter: PreviewPainter(frame, bedBelow: _camera.pitch >= 0)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Draws bed, grid and model. Frames are computed for a size; a stale frame is centered until the next arrives.
class PreviewPainter extends CustomPainter {
  PreviewPainter(this.frame, {this.bedBelow = true});

  final ProjectedFrame frame;

  /// False when looking from below the bed: then the bed is drawn over the model, see-through.
  final bool bedBelow;

  static const bedColor = PixelColors.panel;
  static const gridColor = Color(0x668C8AA8);
  static const edgeColor = PixelColors.muted;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate((size.width - frame.width) / 2, (size.height - frame.height) / 2);
    if (bedBelow) {
      _bed(canvas, 1);
      _model(canvas);
    } else {
      _model(canvas);
      _bed(canvas, 0.55);
    }
    canvas.restore();
  }

  void _model(Canvas canvas) {
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
    canvas.drawPath(outline, Paint()..color = bedColor.withValues(alpha: opacity));
    final grid = Paint()
      ..color = gridColor.withValues(alpha: gridColor.a * opacity)
      ..strokeWidth = 1
      ..isAntiAlias = true;
    final g = frame.grid;
    for (var i = 0; i + 3 < g.length; i += 4) {
      canvas.drawLine(Offset(g[i], g[i + 1]), Offset(g[i + 2], g[i + 3]), grid);
    }
    canvas.drawPath(
      outline,
      Paint()
        ..color = edgeColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(PreviewPainter old) => old.frame != frame || old.bedBelow != bedBelow;
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const PixelPanel(child: PixelText.small('Vorschau wird gezeichnet …'));
}
