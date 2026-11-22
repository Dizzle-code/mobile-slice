import 'dart:math' as math;
import 'dart:typed_data';

/// Orbit camera around the model: [yaw] turns around the vertical axis, [pitch] tilts from
/// side view (0) to top view (π/2), [scale] previews a uniform model size factor.
class OrbitCamera {
  const OrbitCamera({this.yaw = -0.6, this.pitch = 0.55, this.zoom = 1, this.scale = 1});

  final double yaw;
  final double pitch;
  final double zoom;
  final double scale;

  static const minPitch = -0.2;
  static const maxPitch = math.pi / 2;

  OrbitCamera rotated(double dYaw, double dPitch) =>
      OrbitCamera(yaw: yaw + dYaw, pitch: (pitch + dPitch).clamp(minPitch, maxPitch), zoom: zoom, scale: scale);

  OrbitCamera zoomed(double factor) =>
      OrbitCamera(yaw: yaw, pitch: pitch, zoom: (zoom * factor).clamp(0.3, 8.0), scale: scale);

  OrbitCamera withScale(double scale) => OrbitCamera(yaw: yaw, pitch: pitch, zoom: zoom, scale: scale);
}

class PreviewScene {
  PreviewScene({
    required this.triangles,
    required this.center,
    required this.base,
    required this.radius,
    required this.bedX,
    required this.bedY,
    required this.modelColor,
  });

  final Float32List triangles;

  /// Orbit target (x, y, z) at scale 1.
  final List<double> center;

  /// Point the size preview scales around: center of the model's footprint on the bed.
  final List<double> base;
  final double radius;
  final double bedX;
  final double bedY;

  /// ARGB.
  final int modelColor;

  /// +1 normals point outwards, -1 inwards, 0 when the winding cannot be trusted (no culling then).
  late final int orientation = meshOrientation(triangles);
}

/// Screen-space geometry for one camera: model triangles back to front plus bed and grid.
class ProjectedFrame {
  const ProjectedFrame({
    required this.width,
    required this.height,
    required this.positions,
    required this.colors,
    required this.depths,
    required this.bed,
    required this.grid,
  });

  final double width;
  final double height;

  /// x, y per vertex, three vertices per triangle, farthest triangle first.
  final Float32List positions;

  /// ARGB per vertex.
  final Int32List colors;

  /// View depth per triangle (larger is farther), in drawing order.
  final Float32List depths;

  /// Bed corners x, y (4 points).
  final Float32List bed;

  /// Grid segments x0, y0, x1, y1.
  final Float32List grid;

  int get triangleCount => depths.length;
}

/// Sign of the enclosed volume: tells whether the STL's winding is consistent enough to cull back faces.
int meshOrientation(Float32List t) {
  var volume = 0.0;
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  for (var i = 0; i + 8 < t.length; i += 9) {
    final ax = t[i], ay = t[i + 1], az = t[i + 2];
    final bx = t[i + 3], by = t[i + 4], bz = t[i + 5];
    final cx = t[i + 6], cy = t[i + 7], cz = t[i + 8];
    volume += ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx);
    for (var v = 0; v < 9; v += 3) {
      minX = math.min(minX, t[i + v]);
      maxX = math.max(maxX, t[i + v]);
      minY = math.min(minY, t[i + v + 1]);
      maxY = math.max(maxY, t[i + v + 1]);
      minZ = math.min(minZ, t[i + v + 2]);
      maxZ = math.max(maxZ, t[i + v + 2]);
    }
  }
  final box = (maxX - minX) * (maxY - minY) * (maxZ - minZ);
  if (!(box > 0)) return 0;
  final ratio = volume / 6 / box;
  // Real solids fill a noticeable part of their bounding box; open or mixed meshes cancel out.
  if (ratio > 0.02) return 1;
  if (ratio < -0.02) return -1;
  return 0;
}

// Key light from the upper left, slightly towards the viewer (view space: right, depth, up).
final _light = _normalize(-0.45, -0.55, 0.7);
final _half = _normalize(_light[0], _light[1] - 1, _light[2]);

List<double> _normalize(double x, double y, double z) {
  final l = math.sqrt(x * x + y * y + z * z);
  return [x / l, y / l, z / l];
}

/// Soft lighting for a view-space normal facing the viewer: sky/ground hemisphere, key light and a highlight.
int shadeColor(int argb, double nr, double nd, double nu) {
  final hemi = 0.5 + 0.5 * nu;
  final ambient = 0.30 + 0.28 * hemi;
  final diffuse = math.max(0.0, nr * _light[0] + nd * _light[1] + nu * _light[2]) * 0.55;
  final spec = math.pow(math.max(0.0, nr * _half[0] + nd * _half[1] + nu * _half[2]), 28) * 0.28 * 255;
  final light = ambient + diffuse;
  int channel(int shift) => (((argb >> shift) & 0xFF) * light + spec).round().clamp(0, 255);
  return 0xFF000000 | channel(16) << 16 | channel(8) << 8 | channel(0);
}

ProjectedFrame project(PreviewScene scene, OrbitCamera camera, double width, double height) {
  final s = camera.scale;
  final cy = math.cos(camera.yaw), sy = math.sin(camera.yaw);
  final cp = math.cos(camera.pitch), sp = math.sin(camera.pitch);
  final bx = scene.base[0], by = scene.base[1], bz = scene.base[2];
  // Orbit target and framing follow the scaled model.
  final tx = bx + (scene.center[0] - bx) * s;
  final ty = by + (scene.center[1] - by) * s;
  final tz = bz + (scene.center[2] - bz) * s;
  final pixelsPerMm = camera.zoom * math.min(width, height) * 0.42 / math.max(scene.radius * s, 1);
  final halfW = width / 2, halfH = height / 2;

  // World point (already scaled) -> screen x, y and depth.
  var outX = 0.0, outY = 0.0, outD = 0.0;
  void view(double x, double y, double z) {
    x -= tx;
    y -= ty;
    z -= tz;
    final x1 = x * cy - y * sy;
    final y1 = x * sy + y * cy;
    outX = halfW + x1 * pixelsPerMm;
    outY = halfH - (y1 * sp + z * cp) * pixelsPerMm;
    outD = y1 * cp - z * sp;
  }

  final bed = Float32List(8);
  for (final (i, (x, y)) in [(0.0, 0.0), (scene.bedX, 0.0), (scene.bedX, scene.bedY), (0.0, scene.bedY)].indexed) {
    view(x, y, 0);
    bed[i * 2] = outX;
    bed[i * 2 + 1] = outY;
  }
  final grid = <double>[];
  void line(double ax, double ay, double bx2, double by2) {
    view(ax, ay, 0);
    grid..add(outX)..add(outY);
    view(bx2, by2, 0);
    grid..add(outX)..add(outY);
  }

  for (var g = 32.0; g < scene.bedX - 0.01; g += 32) {
    line(g, 0, g, scene.bedY);
  }
  for (var g = 32.0; g < scene.bedY - 0.01; g += 32) {
    line(0, g, scene.bedX, g);
  }

  final tri = scene.triangles;
  final count = tri.length ~/ 9;
  final orientation = scene.orientation;
  final screen = Float32List(count * 6);
  final colorOf = Int32List(count);
  final depthOf = Float64List(count);
  final kept = <int>[];
  for (var t = 0; t < count; t++) {
    final o = t * 9;
    final ax = tri[o], ay = tri[o + 1], az = tri[o + 2];
    final ux = tri[o + 3] - ax, uy = tri[o + 4] - ay, uz = tri[o + 5] - az;
    final vx = tri[o + 6] - ax, vy = tri[o + 7] - ay, vz = tri[o + 8] - az;
    var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len == 0) continue;
    nx /= len;
    ny /= len;
    nz /= len;
    var nr = nx * cy - ny * sy;
    final n1 = nx * sy + ny * cy;
    var nd = n1 * cp - nz * sp;
    var nu = n1 * sp + nz * cp;
    if (orientation != 0 && nd * orientation > 1e-6) continue;
    if (nd > 0) {
      // Seen from behind (open or flipped mesh): light the side that faces the viewer.
      nr = -nr;
      nd = -nd;
      nu = -nu;
    }
    var depth = 0.0;
    for (var v = 0; v < 3; v++) {
      view(bx + (tri[o + v * 3] - bx) * s, by + (tri[o + v * 3 + 1] - by) * s, bz + (tri[o + v * 3 + 2] - bz) * s);
      screen[t * 6 + v * 2] = outX;
      screen[t * 6 + v * 2 + 1] = outY;
      depth += outD;
    }
    depthOf[t] = depth / 3;
    colorOf[t] = shadeColor(scene.modelColor, nr, nd, nu);
    kept.add(t);
  }
  kept.sort((a, b) => depthOf[b].compareTo(depthOf[a]));

  final positions = Float32List(kept.length * 6);
  final colors = Int32List(kept.length * 3);
  final depths = Float32List(kept.length);
  for (var i = 0; i < kept.length; i++) {
    final t = kept[i];
    positions.setRange(i * 6, i * 6 + 6, screen, t * 6);
    colors.fillRange(i * 3, i * 3 + 3, colorOf[t]);
    depths[i] = depthOf[t];
  }
  return ProjectedFrame(
    width: width,
    height: height,
    positions: positions,
    colors: colors,
    depths: depths,
    bed: bed,
    grid: Float32List.fromList(grid),
  );
}
