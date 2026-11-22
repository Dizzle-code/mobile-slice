import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/model/mesh.dart';
import 'package:mobile_slice/model/plate_project.dart';
import 'package:mobile_slice/preview/plate_projector.dart';

import 'model_test.dart' show box;

void main() {
  test('Bildschirm -> Bett ist die Umkehrung von Bett -> Bildschirm (jede Ansicht)', () {
    for (final camera in [
      PlateCamera.top,
      const PlateCamera(),
      const PlateCamera(yaw: 2.1, pitch: 0.4, zoom: 2.5, panX: 40, panY: -25),
    ]) {
      final view = PlateView(camera, 800, 600, 256, 256, 250);
      for (final (x, y) in [(128.0, 128.0), (100.0, 50.0), (200.0, 220.0), (0.0, 256.0)]) {
        final (sx, sy, _) = view.toScreen(x, y, 0);
        final bed = view.toBed(sx, sy)!;
        expect(bed.$1, closeTo(x, 1e-6));
        expect(bed.$2, closeTo(y, 1e-6));
      }
    }
  });

  test('Draufsicht: rechts auf dem Bildschirm ist +X, oben ist +Y', () {
    final view = PlateView(PlateCamera.top, 800, 600, 256, 256, 250);
    final center = view.toScreen(128, 128, 0);
    final right = view.toScreen(138, 128, 0);
    final back = view.toScreen(128, 138, 0);
    expect(right.$1, greaterThan(center.$1));
    expect(back.$2, lessThan(center.$2));
  });

  test('Auswahl trifft das vordere Objekt, Rand-Objekte rot, Auswahl gelb', () {
    PlateObject object(int id, double x) =>
        PlateObject(id: id, source: ModelSource(path: '/m', name: 'm', mesh: Mesh(box(0, 0, 0, 20, 20, 20))), x: x, y: 128);
    SceneObject scene(PlateObject o) {
      final (m, sx, sy, sz) = o.placement;
      final b = o.source.mesh.bounds;
      return SceneObject(id: o.id, triangles: o.source.mesh.triangles, center: [b.centerX, b.centerY, b.centerZ], matrix: m, shift: [sx, sy, sz], color: 0xFFFF8A3D);
    }

    final left = object(1, 60), right = object(2, 200);
    final frame = projectPlate(
      objects: [scene(left), scene(right)],
      camera: PlateCamera.top,
      width: 800,
      height: 600,
      bedX: 256,
      bedY: 256,
      bedHeight: 250,
      selected: 2,
      offBed: {1},
    );
    final (lx, ly, _) = frame.view.toScreen(60, 128, 20);
    final (rx, ry, _) = frame.view.toScreen(200, 128, 20);
    expect(frame.hit(lx, ly), 1);
    expect(frame.hit(rx, ry), 2);
    final (ex, ey, _) = frame.view.toScreen(128, 30, 0);
    expect(frame.hit(ex, ey), isNull);
    int red(int c) => (c >> 16) & 0xFF;
    int green(int c) => (c >> 8) & 0xFF;
    final colorOf = {for (var t = 0; t < frame.triangleCount; t++) frame.objectOf[t]: frame.colors[t * 3]};
    expect(green(colorOf[2]!), greaterThan(green(colorOf[1]!)), reason: 'gelb vs. rot');
    expect(red(colorOf[1]!), greaterThan(green(colorOf[1]!) * 2));
  });
}
