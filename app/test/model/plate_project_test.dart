import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/model/mesh.dart';
import 'package:mobile_slice/model/plate_project.dart';

import 'model_test.dart' show box;

const bed = PlateSize(256, 256, 250);

ModelSource source(Float32List triangles, [String name = 'teil.stl']) =>
    ModelSource(path: '/m/$name', name: name, mesh: Mesh(triangles));

/// A thin slab whose big faces point along [axis] (0 = x, 1 = y, 2 = z), lifted off the origin.
Float32List slab(int axis) => switch (axis) {
      0 => box(10, 10, 0, 12, 50, 40),
      1 => box(10, 10, 0, 50, 12, 40),
      _ => box(10, 10, 0, 50, 50, 2),
    };

void main() {
  group('PlateObject', () {
    test('ohne Drehung: auf dem Bett, Mitte auf x/y, Engine-JSON knapp', () {
      final o = PlateObject(id: 1, source: source(box(118, 118, 0, 138, 138, 20)), x: 50, y: 70);
      final f = o.footprint;
      expect([f.minX, f.minY, f.minZ, f.maxX, f.maxY, f.maxZ], [40, 60, 0, 60, 80, 20]);
      final placed = Mesh(o.placedTriangles()).bounds;
      expect(placed.minX, closeTo(40, 1e-4));
      expect(placed.minZ, closeTo(0, 1e-4));
      expect(o.toEngine(), {'model': '/m/teil.stl', 'x': 50.0, 'y': 70.0});
      expect(o.fits(bed), isTrue);
    });

    test('Drehung um Z um 90° tauscht Breite und Tiefe, Skalierung wirkt auf alle Achsen', () {
      final o = PlateObject(id: 1, source: source(box(0, 0, 0, 40, 10, 5)), x: 128, y: 128, rotZ: 90, scale: 2);
      final f = o.footprint;
      expect(f.sizeX, closeTo(20, 1e-6));
      expect(f.sizeY, closeTo(80, 1e-6));
      expect(f.sizeZ, closeTo(10, 1e-6));
      expect(o.toEngine(), containsPair('rotZ', 90.0));
      expect(o.toEngine(), containsPair('scale', 2.0));
    });

    test('Kippen um X stellt das Teil auf, es bleibt auf dem Bett', () {
      final o = PlateObject(id: 1, source: source(box(0, 0, 0, 40, 10, 5)), x: 128, y: 128, rotX: 90);
      final b = Mesh(o.placedTriangles()).bounds;
      expect(b.minZ, closeTo(0, 1e-4));
      expect(b.sizeZ, closeTo(10, 1e-4));
      expect(b.sizeY, closeTo(5, 1e-4));
    });

    test('Winkel werden auf -180..180 normalisiert', () {
      final o = PlateObject(id: 1, source: source(box(0, 0, 0, 1, 1, 1)), x: 0, y: 0);
      expect(o.copyWith(rotZ: 270).rotZ, -90);
      expect(o.copyWith(rotZ: -190).rotZ, 170);
      expect(o.copyWith(rotZ: 360).rotZ, 0);
    });

    test('vereinfachtes Netz liegt exakt wie das volle', () {
      final o = PlateObject(id: 1, source: source(box(3, 4, 5, 33, 24, 15)), x: 100, y: 90, rotZ: 30, rotX: 10);
      final full = Mesh(o.placedTriangles()).bounds;
      final same = Mesh(o.placedTriangles(o.source.mesh.triangles)).bounds;
      expect(same.minX, closeTo(full.minX, 1e-4));
      expect(same.minZ, closeTo(full.minZ, 1e-4));
    });

    test('ragt über den Rand: passt nicht, clampedTo holt es zurück', () {
      final o = PlateObject(id: 1, source: source(box(0, 0, 0, 20, 20, 20)), x: 250, y: 5);
      expect(o.fits(bed), isFalse);
      final c = o.clampedTo(bed);
      expect([c.x, c.y], [246, 10]);
      expect(c.fits(bed), isTrue);
    });
  });

  group('Flach hinlegen', () {
    for (final axis in [0, 1, 2]) {
      for (final flip in [false, true]) {
        test('größte Fläche zeigt nach unten (Achse $axis${flip ? ', gespiegelt' : ''})', () {
          var t = slab(axis);
          if (flip) {
            // Turn the slab upside down along another axis so the normal sign changes.
            final o = PlateObject(id: 1, source: source(t), x: 0, y: 0, rotX: axis == 0 ? 0 : 180, rotY: axis == 0 ? 180 : 0);
            t = o.placedTriangles();
          }
          final project = PlateProject(bed: bed)..add(source(t));
          project.layFlatSelected();
          final f = project.selected!.footprint;
          expect(f.sizeZ, closeTo(2, 0.05), reason: 'flach: nur noch 2 mm hoch');
        });
      }
    }

    test('schräge Fläche', () {
      // A slab tilted 30° around Y; laying flat must undo the tilt.
      final tilted = PlateObject(id: 1, source: source(slab(2)), x: 0, y: 0, rotY: 30).placedTriangles();
      final project = PlateProject(bed: bed)..add(source(tilted));
      final before = project.selected!.footprint.sizeZ;
      project.layFlatSelected();
      expect(before, greaterThan(10));
      expect(project.selected!.footprint.sizeZ, closeTo(2, 0.05));
    });
  });

  group('PlateProject', () {
    test('Hinzufügen: erstes Objekt in die Mitte, weitere überlappen nicht', () {
      final project = PlateProject(bed: bed);
      final cube = source(box(0, 0, 0, 30, 30, 30));
      final a = project.add(cube);
      expect([a.x, a.y], [128, 128]);
      for (var i = 0; i < 6; i++) {
        project.add(cube);
      }
      final objects = project.plate.objects;
      expect(objects, hasLength(7));
      for (var i = 0; i < objects.length; i++) {
        expect(objects[i].fits(bed), isTrue);
        for (var j = i + 1; j < objects.length; j++) {
          final p = objects[i].footprint, q = objects[j].footprint;
          final overlap = p.minX < q.maxX && p.maxX > q.minX && p.minY < q.maxY && p.maxY > q.minY;
          expect(overlap, isFalse, reason: '$i und $j überlappen');
        }
      }
      expect(project.selectedId, objects.last.id);
    });

    test('Verschieben bleibt auf dem Bett und lässt sich in einem Schritt rückgängig machen', () {
      final project = PlateProject(bed: bed);
      project.add(source(box(0, 0, 0, 20, 20, 20)));
      project.beginEdit();
      project.moveSelected(30, 40);
      project.moveSelected(500, -20);
      expect([project.selected!.x, project.selected!.y], [246, 10]);
      project.undo();
      expect([project.selected!.x, project.selected!.y], [128, 128]);
      project.redo();
      expect([project.selected!.x, project.selected!.y], [246, 10]);
    });

    test('Platten: hinzufügen, wechseln, Objekt verschieben, löschen', () {
      final project = PlateProject(bed: bed);
      project.add(source(box(0, 0, 0, 20, 20, 20)));
      expect(project.addPlate(), 1);
      expect(project.plate.isEmpty, isTrue);
      project.selectPlate(0);
      project.select(project.plate.objects.single.id);
      project.moveSelectedToPlate(1);
      expect(project.plateIndex, 1);
      expect(project.plates[0].isEmpty, isTrue);
      expect(project.plates[1].objects, hasLength(1));
      project.moveSelectedToPlate(2);
      expect(project.plates, hasLength(3));
      project.removePlate(1);
      expect(project.plates, hasLength(2));
      expect(project.objectCount, 1);
      project.removePlate(0);
      project.removePlate(0);
      expect(project.plates, hasLength(1), reason: 'eine Platte bleibt immer');
      expect(project.objectCount, 0);
    });

    test('Duplizieren und Entfernen', () {
      final project = PlateProject(bed: bed);
      project.add(source(box(0, 0, 0, 20, 20, 20)));
      project.duplicateSelected(count: 3);
      expect(project.plate.objects, hasLength(4));
      expect(project.plate.objects.map((o) => o.id).toSet(), hasLength(4));
      project.removeSelected();
      expect(project.plate.objects, hasLength(3));
      expect(project.selected, isNull);
    });

    test('Anordnen: ohne Überlappung auf dem Bett, Überlauf auf neue Platten', () {
      final project = PlateProject(bed: bed);
      final big = source(box(0, 0, 0, 100, 100, 10));
      for (var i = 0; i < 6; i++) {
        project.add(big);
      }
      // Pile everything on one spot first.
      for (final o in project.plate.objects) {
        project.select(o.id);
        project.updateSelected((s) => s.copyWith(x: 128, y: 128));
      }
      project.arrange();
      expect(project.plates.length, 2, reason: '4 passen auf 256 × 256, 2 gehen auf eine neue Platte');
      expect(project.objectCount, 6);
      for (var p = 0; p < project.plates.length; p++) {
        expect(project.plateFits(p), isTrue);
        final objects = project.plates[p].objects;
        for (var i = 0; i < objects.length; i++) {
          for (var j = i + 1; j < objects.length; j++) {
            final a = objects[i].footprint, b = objects[j].footprint;
            expect(a.minX < b.maxX - 0.01 && a.maxX > b.minX + 0.01 && a.minY < b.maxY - 0.01 && a.maxY > b.minY + 0.01, isFalse);
          }
        }
      }
      project.undo();
      expect(project.plates, hasLength(1));
    });

    test('Zu großes Objekt bleibt sichtbar auf der Platte und passt nicht', () {
      final project = PlateProject(bed: bed);
      project.add(source(box(0, 0, 0, 300, 20, 20)));
      project.arrange();
      expect(project.plates, hasLength(1));
      expect(project.plateFits(0), isFalse);
    });

    test('Engine-JSON der Platte', () {
      final project = PlateProject(bed: bed);
      project.add(source(box(0, 0, 0, 20, 20, 20), 'a.stl'));
      project.updateSelected((o) => o.copyWith(rotZ: 45));
      expect(project.engineJson(0), {
        'objects': [
          {'model': '/m/a.stl', 'x': 128.0, 'y': 128.0, 'rotZ': 45.0},
        ],
      });
    });
  });

  test('Drehmatrix ist orthogonal (keine Verzerrung)', () {
    final o = PlateObject(id: 1, source: source(box(-10, -10, -10, 10, 10, 10)), x: 0, y: 0, rotX: 33, rotY: -71, rotZ: 128);
    final t = o.placedTriangles();
    // Every edge of the cube keeps its length of 20 mm.
    for (var i = 0; i + 8 < t.length; i += 9) {
      final lengths = [
        for (final (a, b) in [(0, 3), (3, 6), (6, 0)])
          math.sqrt(math.pow(t[i + a] - t[i + b], 2) + math.pow(t[i + a + 1] - t[i + b + 1], 2) + math.pow(t[i + a + 2] - t[i + b + 2], 2)),
      ]..sort();
      expect(lengths[0], closeTo(20, 1e-3));
    }
  });
}
