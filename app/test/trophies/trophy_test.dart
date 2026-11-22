import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/data/json_store.dart';
import 'package:mobile_slice/data/print_history.dart';
import 'package:mobile_slice/trophies/trophy_catalog.dart';
import 'package:mobile_slice/trophies/trophy_engine.dart';

var _id = 0;

PrintRecord rec({
  PrintResult result = PrintResult.finished,
  String model = 'teil.stl',
  DateTime? sentAt,
  int seconds = 3600,
  double grams = 10,
  String type = 'PLA',
  double layer = 0.2,
}) =>
    PrintRecord(
      id: '${_id++}',
      modelName: model,
      subtaskName: 'x',
      sentAt: sentAt ?? DateTime(2026, 1, 1, 12).add(Duration(minutes: _id)),
      result: result,
      printSeconds: seconds,
      grams: grams,
      filamentType: type,
      filamentLabel: type,
      layerHeight: layer,
      processLabel: '',
    );

List<PrintRecord> many(int n, {double grams = 10, int seconds = 3600}) => [for (var i = 0; i < n; i++) rec(grams: grams, seconds: seconds)];

Trophy byId(String id) => trophyCatalog.firstWhere((t) => t.id == id);

bool earned(String id, List<PrintRecord> records) => byId(id).progress(TrophyContext(records)).done;

void main() {
  test('Katalog: 14 Trophäen, eindeutige IDs, Icons passen', () {
    expect(trophyCatalog, hasLength(14));
    expect(trophyCatalog.map((t) => t.id).toSet(), hasLength(14));
    for (final t in trophyCatalog) {
      expect(t.glyph.rows.length, lessThanOrEqualTo(16), reason: t.id);
      expect(t.glyph.main.length + t.glyph.second.length, greaterThan(10), reason: t.id);
    }
  });

  test('Nichts ist ohne Drucke freigeschaltet', () {
    for (final t in trophyCatalog) {
      expect(t.progress(TrophyContext(const [])).done, isFalse, reason: t.id);
    }
  });

  test('Anzahl-Trophäen und Fortschritt', () {
    expect(earned('first_print', many(1)), isTrue);
    expect(earned('first_print', [rec(result: PrintResult.failed), rec(result: PrintResult.sent)]), isFalse);
    expect(earned('five_pack', many(4)), isFalse);
    expect(earned('five_pack', many(5)), isTrue);
    expect(earned('serial_production', many(25)), isTrue);
    expect(earned('print_factory', many(99)), isFalse);
    expect(earned('print_factory', many(100)), isTrue);
    final progress = byId('five_pack').progress(TrophyContext(many(2)));
    expect(progress.fraction, closeTo(0.4, 1e-9));
    expect(progress.label, '2 / 5');
  });

  test('Filamentmenge', () {
    expect(earned('first_kilo', many(9, grams: 100)), isFalse);
    expect(earned('first_kilo', many(10, grams: 100)), isTrue);
    expect(earned('heavyweight', many(49, grams: 100)), isFalse);
    expect(earned('heavyweight', many(50, grams: 100)), isTrue);
    expect(earned('first_kilo', [rec(grams: 5000, result: PrintResult.failed)]), isFalse, reason: 'nur fertige zählen');
  });

  test('Druckzeit', () {
    expect(earned('ten_hours', many(9)), isFalse);
    expect(earned('ten_hours', many(10)), isTrue);
    expect(earned('hundred_hours', many(100)), isTrue);
    expect(earned('marathon', [rec(seconds: 8 * 3600)]), isFalse, reason: 'mehr als 8 h');
    expect(earned('marathon', [rec(seconds: 8 * 3600 + 60)]), isTrue);
  });

  test('Nachteule', () {
    expect(earned('night_owl', [rec(sentAt: DateTime(2026, 1, 1, 4, 59))]), isTrue);
    expect(earned('night_owl', [rec(sentAt: DateTime(2026, 1, 1, 5))]), isFalse);
    expect(earned('night_owl', [rec(sentAt: DateTime(2026, 1, 1, 23, 59))]), isFalse);
    expect(earned('night_owl', [rec(sentAt: DateTime(2026, 1, 1, 0, 0), result: PrintResult.failed)]), isFalse);
  });

  test('Kapitän', () {
    expect(earned('captain', [rec(model: '3DBenchy.stl')]), isTrue);
    expect(earned('captain', [rec(model: 'BENCHY_v2.3mf')]), isTrue);
    expect(earned('captain', [rec(model: 'bench.stl')]), isFalse);
  });

  test('Materialkunde', () {
    expect(earned('materials', [rec(type: 'PLA'), rec(type: 'pla'), rec(type: 'PETG')]), isFalse);
    expect(earned('materials', [rec(type: 'PLA'), rec(type: 'PETG'), rec(type: 'TPU')]), isTrue);
  });

  test('Feinmechaniker', () {
    expect(earned('fine_mechanic', [rec(layer: 0.08)]), isTrue);
    expect(earned('fine_mechanic', [rec(layer: 0.12)]), isFalse);
  });

  test('Durchhalter', () {
    final t = DateTime(2026, 1, 1);
    List<PrintRecord> seq(List<PrintResult> results) =>
        [for (var i = 0; i < results.length; i++) rec(result: results[i], sentAt: t.add(Duration(days: i)))];
    const f = PrintResult.finished, x = PrintResult.failed;
    expect(earned('streak', seq([f, f, f, f, x, f])), isFalse);
    expect(earned('streak', seq([x, f, f, f, f, f])), isTrue);
    expect(earned('streak', seq([f, f, f, f, f, x])), isTrue, reason: 'einmal erreicht bleibt erreicht');
  });

  group('TrophyEngine', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('trophies'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('meldet neue Trophäen genau einmal und merkt sie sich', () async {
      final engine = TrophyEngine(JsonStore(dir));
      final first = await engine.check([rec(model: 'benchy.stl')], now: DateTime(2026, 2, 2));
      expect(first.map((t) => t.id), ['first_print', 'captain']);
      expect(await engine.check([rec(model: 'benchy.stl')]), isEmpty);

      final reloaded = TrophyEngine(JsonStore(dir));
      await reloaded.load();
      expect(reloaded.unlocked.value.keys, containsAll(['first_print', 'captain']));
      expect(reloaded.unlocked.value['captain'], DateTime(2026, 2, 2));
      // Deleting history does not take trophies away.
      expect(await reloaded.check(const []), isEmpty);
      expect(reloaded.unlocked.value, hasLength(2));
    });

    test('zurücksetzen', () async {
      final engine = TrophyEngine(JsonStore(dir));
      await engine.check(many(1));
      await engine.reset();
      expect(engine.unlocked.value, isEmpty);
      expect((await engine.check(many(1))).single.id, 'first_print');
    });
  });
}
