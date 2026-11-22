import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'mesh.dart';

/// One model file loaded into the project. Several objects can share it (copies).
class ModelSource {
  ModelSource({required this.path, required this.name, required this.mesh, this.bytes = 0});

  /// Absolute path of the model file the engine reads.
  final String path;
  final String name;

  /// Geometry as the engine loads it (already set on the bed), in millimetres.
  final Mesh mesh;
  final int bytes;

  /// Upper bound of triangles per object in the 3D view; slicing always uses the full model.
  static const previewTriangles = 40000;

  late final Mesh previewMesh = mesh.decimate(previewTriangles);

  /// Exact bounds after rotation and scale, by (rotX, rotY, rotZ, scale). Moving does not change them,
  /// so dragging never walks the full mesh.
  final _bounds = <(double, double, double, double), Bounds3>{};

  /// Overhang area at scale 1 by rotation (see overhangArea).
  final overhangCache = <(double, double, double), double>{};
}

/// An object on a plate: a [ModelSource] turned, scaled and moved.
/// Rotation is applied X, then Y, then Z around the source's bounding box center (same as the engine).
@immutable
class PlateObject {
  const PlateObject({
    required this.id,
    required this.source,
    required this.x,
    required this.y,
    this.rotX = 0,
    this.rotY = 0,
    this.rotZ = 0,
    this.scale = 1,
  });

  final int id;
  final ModelSource source;

  /// Bed position of the footprint center in mm.
  final double x;
  final double y;

  /// Degrees.
  final double rotX;
  final double rotY;
  final double rotZ;
  final double scale;

  String get name => source.name;

  PlateObject copyWith({double? x, double? y, double? rotX, double? rotY, double? rotZ, double? scale, int? id}) => PlateObject(
        id: id ?? this.id,
        source: source,
        x: x ?? this.x,
        y: y ?? this.y,
        rotX: _angle(rotX ?? this.rotX),
        rotY: _angle(rotY ?? this.rotY),
        rotZ: _angle(rotZ ?? this.rotZ),
        scale: scale ?? this.scale,
      );

  /// Keeps angles in (-180, 180] so they read naturally in the UI.
  static double _angle(double degrees) {
    var a = degrees % 360;
    if (a > 180) a -= 360;
    if (a <= -180) a += 360;
    return double.parse(a.toStringAsFixed(3));
  }

  /// Rotation and scale without the final move: maps source points into object space around the origin.
  Float64List get _linear {
    double rad(double d) => d * math.pi / 180;
    final cx = math.cos(rad(rotX)), sx = math.sin(rad(rotX));
    final cy = math.cos(rad(rotY)), sy = math.sin(rad(rotY));
    final cz = math.cos(rad(rotZ)), sz = math.sin(rad(rotZ));
    // R = Rz * Ry * Rx, row-major 3x3, times scale.
    return Float64List.fromList([
      cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx,
      sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx,
      -sy, cy * sx, cy * cx,
    ].map((v) => v * scale).toList());
  }

  /// The object's triangles in bed coordinates: on the bed (min z = 0), footprint centered on [x], [y].
  /// [triangles] may be a decimated copy of the source mesh; it is placed exactly like the full mesh.
  Float32List placedTriangles([Float32List? triangles]) {
    final src = triangles ?? source.mesh.triangles;
    final b = source.mesh.bounds;
    final r = _rotatedBounds;
    final m = _linear;
    final sx = x - (r.minX + r.maxX) / 2, sy = y - (r.minY + r.maxY) / 2, sz = -r.minZ;
    final out = Float32List(src.length);
    for (var i = 0; i < src.length; i += 3) {
      final px = src[i] - b.centerX, py = src[i + 1] - b.centerY, pz = src[i + 2] - b.centerZ;
      out[i] = m[0] * px + m[1] * py + m[2] * pz + sx;
      out[i + 1] = m[3] * px + m[4] * py + m[5] * pz + sy;
      out[i + 2] = m[6] * px + m[7] * py + m[8] * pz + sz;
    }
    return out;
  }

  /// Bounds of the turned and scaled object before it is moved (exact, from all vertices).
  Bounds3 get _rotatedBounds => source._bounds.putIfAbsent((rotX, rotY, rotZ, scale), _computeRotatedBounds);

  Bounds3 _computeRotatedBounds() {
    final src = source.mesh.triangles;
    final b = source.mesh.bounds;
    final m = _linear;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (var i = 0; i < src.length; i += 3) {
      final px = src[i] - b.centerX, py = src[i + 1] - b.centerY, pz = src[i + 2] - b.centerZ;
      final ox = m[0] * px + m[1] * py + m[2] * pz;
      final oy = m[3] * px + m[4] * py + m[5] * pz;
      final oz = m[6] * px + m[7] * py + m[8] * pz;
      if (ox < minX) minX = ox;
      if (ox > maxX) maxX = ox;
      if (oy < minY) minY = oy;
      if (oy > maxY) maxY = oy;
      if (oz < minZ) minZ = oz;
      if (oz > maxZ) maxZ = oz;
    }
    return src.isEmpty ? const Bounds3(0, 0, 0, 0, 0, 0) : Bounds3(minX, minY, minZ, maxX, maxY, maxZ);
  }

  /// 3x3 rotation-and-scale matrix (row-major) and the move after it, for drawing [ModelSource.previewMesh]:
  /// placed = M · (p − source center) + shift.
  (Float64List, double, double, double) get placement {
    final r = _rotatedBounds;
    return (_linear, x - (r.minX + r.maxX) / 2, y - (r.minY + r.maxY) / 2, -r.minZ);
  }

  /// Bounds on the bed.
  Bounds3 get footprint {
    final b = _rotatedBounds;
    final hx = (b.maxX - b.minX) / 2, hy = (b.maxY - b.minY) / 2;
    return Bounds3(x - hx, y - hy, 0, x + hx, y + hy, b.maxZ - b.minZ);
  }

  bool fits(PlateSize bed) {
    const eps = 0.01;
    final f = footprint;
    return f.minX >= -eps && f.minY >= -eps && f.maxX <= bed.x + eps && f.maxY <= bed.y + eps && f.maxZ <= bed.height + eps;
  }

  /// Moves the object back onto the bed if it sticks out (keeps it unchanged if it is too big anyway).
  PlateObject clampedTo(PlateSize bed) {
    final f = footprint;
    final hx = (f.maxX - f.minX) / 2, hy = (f.maxY - f.minY) / 2;
    double clamp(double v, double half, double size) => half * 2 > size ? size / 2 : v.clamp(half, size - half);
    return copyWith(x: clamp(x, hx, bed.x), y: clamp(y, hy, bed.y));
  }

  Map<String, Object?> toEngine() => {
        'model': source.path,
        'x': x,
        'y': y,
        if (rotX != 0) 'rotX': rotX,
        if (rotY != 0) 'rotY': rotY,
        if (rotZ != 0) 'rotZ': rotZ,
        if (scale != 1) 'scale': scale,
      };

  @override
  bool operator ==(Object other) =>
      other is PlateObject &&
      other.id == id &&
      identical(other.source, source) &&
      other.x == x &&
      other.y == y &&
      other.rotX == rotX &&
      other.rotY == rotY &&
      other.rotZ == rotZ &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(id, source, x, y, rotX, rotY, rotZ, scale);
}

@immutable
class PlateSize {
  const PlateSize(this.x, this.y, this.height);

  final double x;
  final double y;
  final double height;
}

@immutable
class Plate {
  const Plate({required this.id, this.objects = const []});

  final int id;
  final List<PlateObject> objects;

  Plate withObjects(List<PlateObject> objects) => Plate(id: id, objects: List.unmodifiable(objects));

  bool get isEmpty => objects.isEmpty;
}

/// The whole job: several plates with their objects, which one is shown and which object is selected.
/// Every edit replaces the immutable state, which keeps undo simple.
class PlateProject extends ChangeNotifier {
  PlateProject({required this.bed}) : _plates = [const Plate(id: 1)];

  final PlateSize bed;

  /// Gap between objects when arranging, in mm.
  static const spacing = 6.0;

  List<Plate> _plates;
  int _plateIndex = 0;
  int? _selectedId;
  int _nextObjectId = 1;
  int _nextPlateId = 2;
  final _undo = <(List<Plate>, int, int?)>[];
  final _redo = <(List<Plate>, int, int?)>[];

  List<Plate> get plates => List.unmodifiable(_plates);
  int get plateIndex => _plateIndex;
  Plate get plate => _plates[_plateIndex];
  int? get selectedId => _selectedId;

  PlateObject? get selected {
    for (final object in plate.objects) {
      if (object.id == _selectedId) return object;
    }
    return null;
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  int get objectCount => _plates.fold(0, (sum, p) => sum + p.objects.length);

  /// Plate numbers (1-based) whose objects do not all lie on the bed.
  bool plateFits(int index) => _plates[index].objects.every((o) => o.fits(bed));

  void _remember() {
    _undo.add((_plates, _plateIndex, _selectedId));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _set(List<Plate> plates, {int? plateIndex, int? selected, bool keepSelection = false}) {
    _plates = List.unmodifiable(plates);
    _plateIndex = (plateIndex ?? _plateIndex).clamp(0, _plates.length - 1);
    if (!keepSelection) _selectedId = selected;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add((_plates, _plateIndex, _selectedId));
    final (plates, index, selected) = _undo.removeLast();
    _set(plates, plateIndex: index, selected: selected);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add((_plates, _plateIndex, _selectedId));
    final (plates, index, selected) = _redo.removeLast();
    _set(plates, plateIndex: index, selected: selected);
  }

  void selectPlate(int index) {
    if (index == _plateIndex || index < 0 || index >= _plates.length) return;
    _plateIndex = index;
    _selectedId = null;
    notifyListeners();
  }

  void select(int? id) {
    if (id == _selectedId) return;
    _selectedId = id;
    notifyListeners();
  }

  int addPlate() {
    _remember();
    final plates = [..._plates, Plate(id: _nextPlateId++)];
    _set(plates, plateIndex: plates.length - 1, selected: null);
    return _plateIndex;
  }

  void removePlate(int index) {
    if (_plates.length <= 1) {
      clearPlate(index);
      return;
    }
    _remember();
    final plates = [..._plates]..removeAt(index);
    _set(plates, plateIndex: math.min(_plateIndex, plates.length - 1), selected: null);
  }

  void clearPlate(int index) {
    if (_plates[index].isEmpty) return;
    _remember();
    final plates = [..._plates];
    plates[index] = plates[index].withObjects(const []);
    _set(plates, selected: null);
  }

  /// Adds [source] to the current plate in a free spot; returns the new object.
  PlateObject add(ModelSource source) {
    _remember();
    final object = _place(PlateObject(id: _nextObjectId++, source: source, x: bed.x / 2, y: bed.y / 2), plate.objects);
    _replacePlateObjects([...plate.objects, object], select: object.id);
    return object;
  }

  /// [count] copies of the selected object next to it.
  void duplicateSelected({int count = 1}) {
    final original = selected;
    if (original == null) return;
    _remember();
    final objects = [...plate.objects];
    PlateObject? last;
    for (var i = 0; i < count; i++) {
      last = _place(original.copyWith(id: _nextObjectId++), objects);
      objects.add(last);
    }
    _replacePlateObjects(objects, select: last?.id);
  }

  void removeSelected() {
    final id = _selectedId;
    if (id == null) return;
    _remember();
    _replacePlateObjects([for (final o in plate.objects) if (o.id != id) o], select: null);
  }

  /// Live update while dragging: no undo step per frame. Call [beginEdit] once before.
  void moveSelected(double x, double y) {
    final object = selected;
    if (object == null) return;
    _update(object.copyWith(x: x, y: y).clampedTo(bed));
  }

  /// Saves the state before a continuous edit (drag) so it undoes in one step.
  void beginEdit() => _remember();

  void updateSelected(PlateObject Function(PlateObject) change) {
    final object = selected;
    if (object == null) return;
    _remember();
    _update(change(object).clampedTo(bed));
  }

  /// Turns the object so its largest flat face lies on the bed (like "lay on face" in Bambu Studio).
  void layFlatSelected() {
    final object = selected;
    if (object == null) return;
    final (rx, ry) = bestFlatRotation(object.source.mesh);
    _remember();
    _update(object.copyWith(rotX: rx, rotY: ry, rotZ: object.rotZ).clampedTo(bed));
  }

  /// Moves the selected object to another plate (index may be [plates.length] for a new one).
  void moveSelectedToPlate(int target) {
    final object = selected;
    if (object == null || target == _plateIndex) return;
    _remember();
    final plates = [..._plates];
    if (target >= plates.length) {
      plates.add(Plate(id: _nextPlateId++));
      target = plates.length - 1;
    }
    plates[_plateIndex] = plates[_plateIndex].withObjects([for (final o in plates[_plateIndex].objects) if (o.id != object.id) o]);
    final placed = _place(object, plates[target].objects);
    plates[target] = plates[target].withObjects([...plates[target].objects, placed]);
    _set(plates, plateIndex: target, selected: placed.id);
  }

  /// Packs all objects of the current plate in rows, largest first, centered on the bed.
  /// Objects that do not fit on this plate move to new plates.
  void arrange() {
    if (plate.isEmpty) return;
    _remember();
    final rows = packRows(plate.objects, bed, spacing);
    final plates = [..._plates];
    plates[_plateIndex] = plates[_plateIndex].withObjects(rows.placed);
    var overflow = rows.rest;
    var insertAt = _plateIndex + 1;
    while (overflow.isNotEmpty) {
      final next = packRows(overflow, bed, spacing);
      if (next.placed.isEmpty) {
        // Too big for any plate: keep it on the current plate so the user sees the problem.
        plates[_plateIndex] = plates[_plateIndex].withObjects([...plates[_plateIndex].objects, ...overflow]);
        break;
      }
      plates.insert(insertAt++, Plate(id: _nextPlateId++, objects: List.unmodifiable(next.placed)));
      overflow = next.rest;
    }
    _set(plates, keepSelection: true);
  }

  void _update(PlateObject object) {
    _replacePlateObjects([for (final o in plate.objects) o.id == object.id ? object : o], select: object.id);
  }

  void _replacePlateObjects(List<PlateObject> objects, {int? select}) {
    final plates = [..._plates];
    plates[_plateIndex] = plate.withObjects(objects);
    _set(plates, selected: select);
  }

  /// Finds a spot for [object] that does not overlap [others]: scans the bed from the center outwards.
  PlateObject _place(PlateObject object, List<PlateObject> others) {
    final f = object.footprint;
    final w = f.maxX - f.minX, d = f.maxY - f.minY;
    bool free(double x, double y) {
      if (x - w / 2 < 0 || y - d / 2 < 0 || x + w / 2 > bed.x || y + d / 2 > bed.y) return false;
      for (final o in others) {
        final b = o.footprint;
        if (x - w / 2 < b.maxX + spacing && x + w / 2 > b.minX - spacing && y - d / 2 < b.maxY + spacing && y + d / 2 > b.minY - spacing) {
          return false;
        }
      }
      return true;
    }

    if (others.isEmpty || free(bed.x / 2, bed.y / 2)) return object.copyWith(x: bed.x / 2, y: bed.y / 2).clampedTo(bed);
    const step = 4.0;
    final maxRing = (math.max(bed.x, bed.y) / step).ceil();
    for (var ring = 1; ring <= maxRing; ring++) {
      for (var i = -ring; i <= ring; i++) {
        for (final (dx, dy) in [(i, -ring), (i, ring), (-ring, i), (ring, i)]) {
          final x = bed.x / 2 + dx * step, y = bed.y / 2 + dy * step;
          if (free(x, y)) return object.copyWith(x: x, y: y);
        }
      }
    }
    // No free spot: next to the last object, possibly off the bed; the plate shows it as not fitting.
    return object.copyWith(x: bed.x / 2, y: bed.y / 2);
  }

  /// Engine input for plate [index]: `{"objects":[...]}`.
  Map<String, Object?> engineJson(int index) => {'objects': [for (final o in _plates[index].objects) o.toEngine()]};
}

/// Result of [packRows]: what fit on one plate and what is left.
typedef PackResult = ({List<PlateObject> placed, List<PlateObject> rest});

/// Shelf packing: sorts by depth, fills rows left to right, then centers the block on the bed.
PackResult packRows(List<PlateObject> objects, PlateSize bed, double spacing) {
  final sorted = [...objects]..sort((a, b) {
      final da = a.footprint.sizeY, db = b.footprint.sizeY;
      return db.compareTo(da);
    });
  final placed = <PlateObject>[];
  final rest = <PlateObject>[];
  var rowY = 0.0, rowDepth = 0.0, cursorX = 0.0;
  final rows = <List<int>>[[]];
  final rowWidths = <double>[0];
  for (final object in sorted) {
    final f = object.footprint;
    final w = f.sizeX, d = f.sizeY;
    if (w > bed.x || d > bed.y || f.sizeZ > bed.height) {
      rest.add(object);
      continue;
    }
    if (cursorX > 0 && cursorX + w > bed.x) {
      rowY += rowDepth + spacing;
      rowDepth = 0;
      cursorX = 0;
      rows.add([]);
      rowWidths.add(0);
    }
    if (rowY + d > bed.y) {
      rest.add(object);
      continue;
    }
    placed.add(object.copyWith(x: cursorX + w / 2, y: rowY + d / 2));
    rows.last.add(placed.length - 1);
    rowWidths[rowWidths.length - 1] = cursorX + w;
    cursorX += w + spacing;
    rowDepth = math.max(rowDepth, d);
  }
  if (placed.isEmpty) return (placed: placed, rest: rest);
  // Center every row horizontally and the whole block vertically.
  final totalDepth = rowY + rowDepth;
  final offsetY = (bed.y - totalDepth) / 2;
  for (var r = 0; r < rows.length; r++) {
    final offsetX = (bed.x - rowWidths[r]) / 2;
    for (final i in rows[r]) {
      placed[i] = placed[i].copyWith(x: placed[i].x + offsetX, y: placed[i].y + offsetY);
    }
  }
  return (placed: placed, rest: rest);
}

/// Rotation (rotX, rotY in degrees) that puts the mesh's largest coplanar face area on the bed.
(double, double) bestFlatRotation(Mesh mesh) {
  final t = mesh.triangles;
  final areas = <(int, int, int), (double, double, double, double)>{};
  for (var i = 0; i + 8 < t.length; i += 9) {
    final ax = t[i + 3] - t[i], ay = t[i + 4] - t[i + 1], az = t[i + 5] - t[i + 2];
    final bx = t[i + 6] - t[i], by = t[i + 7] - t[i + 1], bz = t[i + 8] - t[i + 2];
    var nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len == 0) continue;
    nx /= len;
    ny /= len;
    nz /= len;
    // Normals within ~2° count as the same face direction.
    final key = ((nx * 30).round(), (ny * 30).round(), (nz * 30).round());
    final old = areas[key] ?? (0.0, 0.0, 0.0, 0.0);
    final area = len / 2;
    areas[key] = (old.$1 + area, old.$2 + nx * area, old.$3 + ny * area, old.$4 + nz * area);
  }
  if (areas.isEmpty) return (0, 0);
  final best = areas.values.reduce((a, b) => a.$1 >= b.$1 ? a : b);
  final l = math.sqrt(best.$2 * best.$2 + best.$3 * best.$3 + best.$4 * best.$4);
  final nx = best.$2 / l, ny = best.$3 / l, nz = best.$4 / l;
  // Turn the normal n to (0, 0, -1): around X so it lies in the XZ plane pointing down (0 = ny', -r = nz'),
  // then around Y until x is 0 as well.
  final rx = math.atan2(-ny, -nz);
  final ry = math.atan2(nx, math.sqrt(ny * ny + nz * nz));
  double deg(double r) => double.parse((r * 180 / math.pi).toStringAsFixed(3));
  return (deg(rx), deg(ry));
}
