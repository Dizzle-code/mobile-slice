import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/model/mesh.dart';
import 'package:mobile_slice/model/overhang.dart';

import 'model_test.dart' show box;

Mesh join(List<Float32List> parts) => Mesh(Float32List.fromList([for (final p in parts) ...p]));

void main() {
  test('Würfel auf dem Bett braucht keine Stützen', () {
    expect(overhangArea(Mesh(box(0, 0, 0, 20, 20, 20))), 0);
  });

  test('Ausladende Platte auf einer Säule braucht Stützen', () {
    final t = join([box(5, 5, 0, 15, 15, 10), box(0, 0, 10, 20, 20, 12)]);
    expect(overhangArea(t), closeTo(400, 0.01));
    expect(needsSupport(overhangArea(t), 1), isTrue);
    expect(needsSupport(overhangArea(t), 0.2), isFalse, reason: 'winzig skaliert reicht die Brücke');
  });

  test('45°-Fase zählt nicht, flache Schräge schon', () {
    Mesh ramp(double rise) => Mesh(Float32List.fromList([0, 0, 10, 0, 10, 10, 10, 0, 10 + rise]));
    expect(overhangArea(ramp(10)), 0);
    expect(overhangArea(ramp(2)), greaterThan(0));
  });
}
