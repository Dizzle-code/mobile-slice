import 'dart:math' as math;

import 'mesh.dart';

/// Faces flatter than this (degrees from horizontal) and facing down print in the air.
const overhangAngle = 40.0;

/// Area in mm² of downward faces that would need support, ignoring faces lying on the bed.
double overhangArea(Mesh mesh, {double angle = overhangAngle}) {
  final t = mesh.triangles;
  if (t.isEmpty) return 0;
  final limit = -math.cos(angle * math.pi / 180);
  final bedZ = mesh.bounds.minZ + 0.3;
  var area = 0.0;
  for (var i = 0; i < t.length; i += 9) {
    final ax = t[i + 3] - t[i], ay = t[i + 4] - t[i + 1], az = t[i + 5] - t[i + 2];
    final bx = t[i + 6] - t[i], by = t[i + 7] - t[i + 1], bz = t[i + 8] - t[i + 2];
    final nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (length == 0 || nz / length > limit) continue;
    if ((t[i + 2] + t[i + 5] + t[i + 8]) / 3 <= bedZ) continue;
    area += length / 2;
  }
  return area;
}

/// True when [area] (from [overhangArea]) at [scale] is enough that the print likely fails without support.
bool needsSupport(double area, double scale) => area * scale * scale >= 25;
