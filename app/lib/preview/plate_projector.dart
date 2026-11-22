import 'dart:math' as math;
import 'dart:typed_data';

import 'projector.dart';

/// One object of the plate view: preview triangles in source coordinates plus its placement.
class SceneObject {
  SceneObject({
    required this.id,
    required this.triangles,
    required this.center,
    required this.matrix,
    required this.shift,
    required this.color,
  });

  final int id;

  /// Source mesh (possibly decimated), 9 floats per triangle.
  final Float32List triangles;

  /// Source bounding box center the matrix turns around.
  final List<double> center;

  /// Row-major 3x3 rotation and scale.
  final Float64List matrix;

  /// Move after turning: x, y, z.
  final List<double> shift;

  /// ARGB.
  final int color;

  late final int orientation = meshOrientation(triangles);
}

/// The whole plate as seen by the orbit camera, which always looks at the bed center.
/// Unlike [project], the framing follows the bed, not one model, so objects can be moved around.
class PlateCamera {
  const PlateCamera({this.yaw = -0.6, this.pitch = 0.75, this.zoom = 1, this.panX = 0, this.panY = 0});

  final double yaw;
  final double pitch;
  final double zoom;

  /// Screen offset of the view in logical pixels.
  final double panX;
  final double panY;

  static const minPitch = -0.2;
  static const maxPitch = math.pi / 2;
  static const top = PlateCamera(yaw: 0, pitch: maxPitch);

  PlateCamera rotated(double dYaw, double dPitch) =>
      PlateCamera(yaw: yaw + dYaw, pitch: (pitch + dPitch).clamp(minPitch, maxPitch), zoom: zoom, panX: panX, panY: panY);

  PlateCamera zoomed(double factor) =>
      PlateCamera(yaw: yaw, pitch: pitch, zoom: (zoom * factor).clamp(0.4, 12.0), panX: panX, panY: panY);

  PlateCamera panned(double dx, double dy) => PlateCamera(yaw: yaw, pitch: pitch, zoom: zoom, panX: panX + dx, panY: panY + dy);
}

/// Screen geometry of the plate: triangles back to front (with their object id), bed and grid.
class PlateFrame {
  const PlateFrame({
    required this.width,
    required this.height,
    required this.positions,
    required this.colors,
    required this.objectOf,
    required this.bed,
    required this.grid,
    required this.view,
  });

  final double width;
  final double height;
  final Float32List positions;
  final Int32List colors;

  /// Object id per drawn triangle, in drawing order (last is in front).
  final Int32List objectOf;
  final Float32List bed;
  final Float32List grid;

  /// The projection used, for picking and dragging on the bed.
  final PlateView view;

  int get triangleCount => objectOf.length;

  /// Id of the front-most object under [x], [y] (screen), or null.
  int? hit(double x, double y) {
    for (var t = objectOf.length - 1; t >= 0; t--) {
      final o = t * 6;
      if (_inside(x, y, positions[o], positions[o + 1], positions[o + 2], positions[o + 3], positions[o + 4], positions[o + 5])) {
        return objectOf[t];
      }
    }
    return null;
  }

  static bool _inside(double px, double py, double ax, double ay, double bx, double by, double cx, double cy) {
    final d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
    final d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
    final d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
    final negative = d1 < 0 || d2 < 0 || d3 < 0;
    final positive = d1 > 0 || d2 > 0 || d3 > 0;
    return !(negative && positive);
  }
}

/// Orthographic orbit projection of bed coordinates onto the screen.
class PlateView {
  PlateView(this.camera, this.width, this.height, this.bedX, this.bedY, this.bedHeight)
      : cy = math.cos(camera.yaw),
        sy = math.sin(camera.yaw),
        cp = math.cos(camera.pitch),
        sp = math.sin(camera.pitch) {
    // Fits the bed into the view at zoom 1: its diagonal across the width, its tilted depth across the height.
    final half = math.sqrt(bedX * bedX + bedY * bedY) / 2;
    final across = width / (2 * half);
    final deep = height / (2 * (half * sp + bedHeight * 0.15 * cp));
    pixelsPerMm = camera.zoom * 0.92 * math.min(across, deep);
  }

  final PlateCamera camera;
  final double width, height, bedX, bedY, bedHeight;
  final double cy, sy, cp, sp;
  late final double pixelsPerMm;

  double get _cx => width / 2 + camera.panX;
  double get _cy => height / 2 + camera.panY;

  /// Bed point -> screen x, y and depth (larger is farther).
  (double, double, double) toScreen(double x, double y, double z) {
    x -= bedX / 2;
    y -= bedY / 2;
    z -= bedHeight * 0.12;
    final x1 = x * cy - y * sy;
    final y1 = x * sy + y * cy;
    return (_cx + x1 * pixelsPerMm, _cy - (y1 * sp + z * cp) * pixelsPerMm, y1 * cp - z * sp);
  }

  /// Screen point -> point on the bed plane (z = 0), or null when looking along the bed.
  (double, double)? toBed(double screenX, double screenY) {
    if (sp.abs() < 0.05) return null;
    final x1 = (screenX - _cx) / pixelsPerMm;
    // screenY = _cy - (y1 * sp + z * cp) * ppm with z = -bedHeight * 0.12
    final z = -bedHeight * 0.12;
    final y1 = ((_cy - screenY) / pixelsPerMm - z * cp) / sp;
    final x = x1 * cy + y1 * sy;
    final y = -x1 * sy + y1 * cy;
    return (x + bedX / 2, y + bedY / 2);
  }
}

const _selectedTint = 0xFFFFD447;
const _offBedTint = 0xFFE8475B;

/// Projects all objects; [selected] is drawn in yellow, objects listed in [offBed] in red.
PlateFrame projectPlate({
  required List<SceneObject> objects,
  required PlateCamera camera,
  required double width,
  required double height,
  required double bedX,
  required double bedY,
  required double bedHeight,
  int? selected,
  Set<int> offBed = const {},
}) {
  final view = PlateView(camera, width, height, bedX, bedY, bedHeight);
  final cyaw = view.cy, syaw = view.sy, cp = view.cp, sp = view.sp;

  final bed = Float32List(8);
  for (final (i, (x, y)) in [(0.0, 0.0), (bedX, 0.0), (bedX, bedY), (0.0, bedY)].indexed) {
    final p = view.toScreen(x, y, 0);
    bed[i * 2] = p.$1;
    bed[i * 2 + 1] = p.$2;
  }
  final grid = <double>[];
  void line(double ax, double ay, double bx, double by) {
    final a = view.toScreen(ax, ay, 0), b = view.toScreen(bx, by, 0);
    grid.addAll([a.$1, a.$2, b.$1, b.$2]);
  }

  for (var g = 32.0; g < bedX - 0.01; g += 32) {
    line(g, 0, g, bedY);
  }
  for (var g = 32.0; g < bedY - 0.01; g += 32) {
    line(0, g, bedX, g);
  }

  var total = 0;
  for (final o in objects) {
    total += o.triangles.length ~/ 9;
  }
  final screen = Float32List(total * 6);
  final colorOf = Int32List(total);
  final depthOf = Float64List(total);
  final idOf = Int32List(total);
  final kept = <int>[];
  var index = 0;
  for (final object in objects) {
    final t = object.triangles;
    final m = object.matrix;
    final c = object.center;
    final s = object.shift;
    final base = object.id == selected ? _selectedTint : (offBed.contains(object.id) ? _offBedTint : object.color);
    // Turning keeps the winding when the determinant is positive (always, rotation times positive scale).
    final orientation = object.orientation;
    for (var i = 0; i + 8 < t.length; i += 9, index++) {
      final p = List<double>.filled(9, 0);
      for (var v = 0; v < 3; v++) {
        final px = t[i + v * 3] - c[0], py = t[i + v * 3 + 1] - c[1], pz = t[i + v * 3 + 2] - c[2];
        p[v * 3] = m[0] * px + m[1] * py + m[2] * pz + s[0];
        p[v * 3 + 1] = m[3] * px + m[4] * py + m[5] * pz + s[1];
        p[v * 3 + 2] = m[6] * px + m[7] * py + m[8] * pz + s[2];
      }
      final ux = p[3] - p[0], uy = p[4] - p[1], uz = p[5] - p[2];
      final vx = p[6] - p[0], vy = p[7] - p[1], vz = p[8] - p[2];
      var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len == 0) continue;
      nx /= len;
      ny /= len;
      nz /= len;
      var nr = nx * cyaw - ny * syaw;
      final n1 = nx * syaw + ny * cyaw;
      var nd = n1 * cp - nz * sp;
      var nu = n1 * sp + nz * cp;
      if (orientation != 0 && nd * orientation > 1e-6) continue;
      if (nd > 0) {
        nr = -nr;
        nd = -nd;
        nu = -nu;
      }
      var depth = 0.0;
      for (var v = 0; v < 3; v++) {
        final q = view.toScreen(p[v * 3], p[v * 3 + 1], p[v * 3 + 2]);
        screen[index * 6 + v * 2] = q.$1;
        screen[index * 6 + v * 2 + 1] = q.$2;
        depth += q.$3;
      }
      depthOf[index] = depth / 3;
      colorOf[index] = shadeColor(base, nr, nd, nu);
      idOf[index] = object.id;
      kept.add(index);
    }
  }
  kept.sort((a, b) => depthOf[b].compareTo(depthOf[a]));

  final positions = Float32List(kept.length * 6);
  final colors = Int32List(kept.length * 3);
  final ids = Int32List(kept.length);
  for (var i = 0; i < kept.length; i++) {
    final t = kept[i];
    positions.setRange(i * 6, i * 6 + 6, screen, t * 6);
    colors.fillRange(i * 3, i * 3 + 3, colorOf[t]);
    ids[i] = idOf[t];
  }
  return PlateFrame(
    width: width,
    height: height,
    positions: positions,
    colors: colors,
    objectOf: ids,
    bed: bed,
    grid: Float32List.fromList(grid),
    view: view,
  );
}
