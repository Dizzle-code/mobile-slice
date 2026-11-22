import 'dart:math' as math;
import 'dart:typed_data';

class Bounds3 {
  const Bounds3(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ);

  final double minX, minY, minZ, maxX, maxY, maxZ;

  double get sizeX => maxX - minX;
  double get sizeY => maxY - minY;
  double get sizeZ => maxZ - minZ;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  double get centerZ => (minZ + maxZ) / 2;
  double get radius => math.sqrt(sizeX * sizeX + sizeY * sizeY + sizeZ * sizeZ) / 2;
}

/// Triangle soup: 9 floats per triangle.
class Mesh {
  Mesh(this.triangles) : assert(triangles.length % 9 == 0);

  final Float32List triangles;

  int get triangleCount => triangles.length ~/ 9;

  late final Bounds3 bounds = _bounds();

  Bounds3 _bounds() {
    if (triangles.isEmpty) return const Bounds3(0, 0, 0, 0, 0, 0);
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (var i = 0; i < triangles.length; i += 3) {
      final x = triangles[i], y = triangles[i + 1], z = triangles[i + 2];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }
    return Bounds3(minX, minY, minZ, maxX, maxY, maxZ);
  }

  /// Vertex clustering: snaps vertices to a grid and drops collapsed triangles,
  /// refining the grid until at most [maxTriangles] remain. Only for the preview.
  Mesh decimate(int maxTriangles) {
    if (triangleCount <= maxTriangles) return this;
    final b = bounds;
    final extent = math.max(b.sizeX, math.max(b.sizeY, b.sizeZ));
    if (extent <= 0) return this;
    var cells = math.max(8, math.sqrt(maxTriangles / 2).round());
    Mesh result = this;
    for (var attempt = 0; attempt < 12; attempt++) {
      result = _cluster(extent / cells);
      if (result.triangleCount <= maxTriangles) return result;
      cells = (cells * 0.8).floor();
      if (cells < 2) break;
    }
    return result;
  }

  Mesh _cluster(double cell) {
    final b = bounds;
    final sums = <int, List<double>>{};
    final ny = (b.sizeY / cell).floor() + 1;
    final nz = (b.sizeZ / cell).floor() + 1;
    int key(int i) {
      final cx = ((triangles[i] - b.minX) / cell).floor();
      final cy = ((triangles[i + 1] - b.minY) / cell).floor();
      final cz = ((triangles[i + 2] - b.minZ) / cell).floor();
      return (cx * ny + cy) * nz + cz;
    }

    final keys = Int64List(triangles.length ~/ 3);
    for (var v = 0; v < keys.length; v++) {
      final k = key(v * 3);
      keys[v] = k;
      final sum = sums.putIfAbsent(k, () => [0, 0, 0, 0]);
      sum[0] += triangles[v * 3];
      sum[1] += triangles[v * 3 + 1];
      sum[2] += triangles[v * 3 + 2];
      sum[3] += 1;
    }
    final out = <double>[];
    final seen = <(int, int, int)>{};
    for (var t = 0; t < triangleCount; t++) {
      final a = keys[t * 3], bk = keys[t * 3 + 1], c = keys[t * 3 + 2];
      if (a == bk || bk == c || a == c) continue;
      if (!seen.add((a, bk, c))) continue;
      for (final k in [a, bk, c]) {
        final s = sums[k]!;
        out
          ..add(s[0] / s[3])
          ..add(s[1] / s[3])
          ..add(s[2] / s[3]);
      }
    }
    return Mesh(Float32List.fromList(out));
  }
}
