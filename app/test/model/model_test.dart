import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/model/mesh.dart';
import 'package:mobile_slice/model/stl_reader.dart';
import 'package:mobile_slice/preview/model_viewer.dart';
import 'package:mobile_slice/preview/preview_worker.dart';
import 'package:mobile_slice/preview/projector.dart';

/// Axis-aligned box as 12 triangles.
Float32List box(double x0, double y0, double z0, double x1, double y1, double z1) {
  final v = [
    [x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0],
    [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1],
  ];
  const faces = [
    [0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4],
    [1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7],
  ];
  return Float32List.fromList([for (final f in faces) for (final i in f) ...v[i]]);
}

/// A finely tessellated sphere for decimation tests.
Float32List sphere(int rings, int segments, double r) {
  final out = <double>[];
  List<double> point(int ring, int seg) {
    final theta = ring / rings * 3.141592653589793;
    final phi = seg / segments * 2 * 3.141592653589793;
    return [r * _sin(theta) * _cos(phi), r * _sin(theta) * _sin(phi), r * _cos(theta)];
  }

  for (var i = 0; i < rings; i++) {
    for (var j = 0; j < segments; j++) {
      final a = point(i, j), b = point(i + 1, j), c = point(i + 1, j + 1), d = point(i, j + 1);
      out..addAll(a)..addAll(b)..addAll(c)..addAll(a)..addAll(c)..addAll(d);
    }
  }
  return Float32List.fromList(out);
}

double _sin(double x) => math.sin(x);
double _cos(double x) => math.cos(x);

void main() {
  group('STL', () {
    test('binär hin und zurück', () {
      final tris = box(0, 0, 0, 20, 20, 20);
      final read = readStl(writeBinaryStl(tris));
      expect(read, tris);
    });

    test('Text-STL', () {
      const text = '''solid test
facet normal 0 0 1
 outer loop
  vertex 0 0 0
  vertex 1 0 0
  vertex 0 1.5e1 0
 endloop
endfacet
endsolid test''';
      expect(readStl(Uint8List.fromList(utf8.encode(text))), Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 15, 0]));
    });

    test('binäre Datei, deren Kopf mit "solid" beginnt', () {
      final bytes = writeBinaryStl(box(0, 0, 0, 1, 1, 1));
      bytes.setRange(0, 5, ascii.encode('solid'));
      expect(readStl(bytes).length, 12 * 9);
    });

    test('mitgelieferter Testwürfel', () {
      final mesh = Mesh(readStl(File('assets/engine/models/test_cube.stl').readAsBytesSync()));
      expect(mesh.triangleCount, 12);
      expect(mesh.bounds.sizeX, closeTo(20, 1e-4));
    });

    test('kaputte Dateien werden abgelehnt', () {
      expect(() => readStl(Uint8List.fromList([1, 2, 3])), throwsA(isA<StlFormatException>()));
      expect(() => readStl(Uint8List.fromList(utf8.encode('solid x\nendsolid'))), throwsA(isA<StlFormatException>()));
      final nan = writeBinaryStl(Float32List.fromList([double.nan, 0, 0, 1, 0, 0, 0, 1, 0]));
      expect(() => readStl(nan), throwsA(isA<StlFormatException>()));
    });
  });

  group('Mesh', () {
    test('Bounding Box', () {
      final b = Mesh(box(-5, 2, 0, 15, 12, 30)).bounds;
      expect([b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ], [-5, 2, 0, 15, 12, 30]);
      expect(b.centerZ, 15);
    });

    test('Ausdünnen hält Grenze und Form ein', () {
      final mesh = Mesh(sphere(120, 240, 50));
      expect(mesh.triangleCount, 57600);
      final small = mesh.decimate(5000);
      expect(small.triangleCount, lessThanOrEqualTo(5000));
      expect(small.triangleCount, greaterThan(500));
      expect(small.bounds.sizeX, closeTo(mesh.bounds.sizeX, 10));
      expect(identical(mesh.decimate(100000), mesh), isTrue);
    });
  });

  group('Vorschau-Projektor', () {
    PreviewScene scene(Float32List tris, {int color = 0xFFFF8A3D}) {
      final b = Mesh(tris).bounds;
      return PreviewScene(
        triangles: tris,
        center: [b.centerX, b.centerY, b.centerZ],
        base: [b.centerX, b.centerY, b.minZ],
        radius: b.radius,
        bedX: 256,
        bedY: 256,
        modelColor: color,
      );
    }

    (double, double, double, double) extent(Float32List xy) {
      var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
      for (var i = 0; i < xy.length; i += 2) {
        minX = math.min(minX, xy[i]);
        maxX = math.max(maxX, xy[i]);
        minY = math.min(minY, xy[i + 1]);
        maxY = math.max(maxY, xy[i + 1]);
      }
      return (minX, minY, maxX, maxY);
    }

    test('Würfel liegt in der Bildmitte, Rückseiten werden verworfen', () {
      final frame = project(scene(box(118, 118, 0, 138, 138, 20)), const OrbitCamera(), 400, 300);
      expect(frame.triangleCount, 6, reason: 'drei sichtbare Seiten');
      expect(frame.colors.length, frame.triangleCount * 3);
      final (x0, y0, x1, y1) = extent(frame.positions);
      expect((x0 + x1) / 2, closeTo(200, 20));
      expect((y0 + y1) / 2, closeTo(150, 20));
      expect(frame.bed.length, 8);
      expect(frame.grid.length, greaterThan(0));
    });

    test('Wicklung: nach innen gedreht wird umgekehrt, offene Netze werden nicht beschnitten', () {
      final outward = box(0, 0, 0, 10, 10, 10);
      final inward = Float32List(outward.length);
      for (var t = 0; t < outward.length; t += 9) {
        inward.setRange(t, t + 3, outward, t);
        inward.setRange(t + 3, t + 6, outward, t + 6);
        inward.setRange(t + 6, t + 9, outward, t + 3);
      }
      expect(meshOrientation(outward), 1);
      expect(meshOrientation(inward), -1);
      expect(project(scene(inward), const OrbitCamera(), 200, 200).triangleCount, 6);
      // A single open face has no volume: both sides stay visible.
      final open = Float32List.fromList(outward.sublist(0, 18));
      expect(meshOrientation(open), 0);
      expect(project(scene(open), const OrbitCamera(pitch: -0.1), 200, 200).triangleCount, 2);
    });

    test('Dreiecke kommen von hinten nach vorn', () {
      final tris = Float32List.fromList([...box(100, 100, 0, 156, 156, 5), ...box(120, 120, 0, 136, 136, 40)]);
      final frame = project(scene(tris), const OrbitCamera(yaw: 0.3, pitch: 0.8), 300, 300);
      for (var i = 1; i < frame.triangleCount; i++) {
        expect(frame.depths[i], lessThanOrEqualTo(frame.depths[i - 1]));
      }
      // From the top the taller box's lid is the nearest triangle.
      final top = project(scene(tris), const OrbitCamera(yaw: 0, pitch: math.pi / 2), 300, 300);
      final (x0, y0, x1, y1) = extent(Float32List.sublistView(top.positions, top.positions.length - 6));
      final (bx0, by0, bx1, by1) = extent(top.positions);
      expect(x1 - x0, lessThan((bx1 - bx0) * 0.5));
      expect(y1 - y0, lessThan((by1 - by0) * 0.5));
    });

    test('Beleuchtung ist weich, ohne harte Stufen', () {
      final colors = <int>{};
      var previous = shadeColor(0xFFFF8A3D, 0, -1, 0);
      for (var i = 1; i <= 90; i++) {
        final a = i / 90 * math.pi / 2;
        final c = shadeColor(0xFFFF8A3D, 0, -math.cos(a), math.sin(a));
        colors.add(c);
        for (final shift in [16, 8, 0]) {
          expect((((c >> shift) & 0xFF) - ((previous >> shift) & 0xFF)).abs(), lessThan(12), reason: 'Sprung bei $i°');
        }
        previous = c;
      }
      expect(colors.length, greaterThan(40));
      // Faces towards the sky are brighter than faces towards the ground.
      int red(int c) => (c >> 16) & 0xFF;
      expect(red(shadeColor(0xFF808080, 0, 0, 1)), greaterThan(red(shadeColor(0xFF808080, 0, 0, -1))));
    });

    test('Zoom vergrößert, Skalierung verkleinert das Bett relativ zum Modell', () {
      final s = scene(box(118, 118, 0, 138, 138, 20));
      double width(Float32List xy) {
        final (x0, _, x1, _) = extent(xy);
        return x1 - x0;
      }

      expect(width(project(s, const OrbitCamera(zoom: 2), 300, 300).positions),
          closeTo(2 * width(project(s, const OrbitCamera(), 300, 300).positions), 1));
      final normal = project(s, const OrbitCamera(), 300, 300);
      final doubled = project(s, const OrbitCamera(scale: 2), 300, 300);
      expect(width(doubled.positions), closeTo(width(normal.positions), 1), reason: 'Ausschnitt folgt dem Modell');
      expect(width(doubled.bed), closeTo(width(normal.bed) / 2, 1));
    });

    test('Kamera begrenzt Neigung und Zoom und behält die Skalierung', () {
      const camera = OrbitCamera(scale: 1.5);
      expect(camera.rotated(0, 10).pitch, OrbitCamera.maxPitch);
      expect(camera.zoomed(100).zoom, 8);
      expect(camera.rotated(1, 0).zoomed(2).scale, 1.5);
    });

    test('Worker-Isolate liefert Frames', () async {
      final worker = await PreviewWorker.spawn(scene(box(118, 118, 0, 138, 138, 20)));
      final frame = await worker.renderOnce(const OrbitCamera(), 400, 300);
      worker.dispose();
      expect(frame.width, 400);
      expect(frame.triangleCount, 6);
      expect(frame.positions.length, 36);
      expect(frame.bed.length, 8);
    });
  });

  testWidgets('Gesten: nach rechts ziehen dreht nach rechts, nach unten ziehen senkt die Ansicht', (tester) async {
    final mesh = Mesh(box(118, 118, 0, 138, 138, 20));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 300, height: 300, child: ModelViewer(mesh: mesh, bedX: 256, bedY: 256))),
    ));
    final state = tester.state<ModelViewerState>(find.byType(ModelViewer));
    final start = state.camera;
    await tester.drag(find.byType(ModelViewer), const Offset(100, 0));
    await tester.pump();
    expect(state.camera.yaw, greaterThan(start.yaw));
    final pitch = state.camera.pitch;
    await tester.drag(find.byType(ModelViewer), const Offset(0, 60));
    await tester.pump();
    expect(state.camera.pitch, greaterThan(pitch));
    await tester.pump(const Duration(seconds: 1));
  });
}
