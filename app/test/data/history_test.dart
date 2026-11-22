import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/data/json_store.dart';
import 'package:mobile_slice/data/print_history.dart';
import 'package:mobile_slice/data/stats.dart';
import 'package:mobile_slice/engine/slice_outcome.dart';
import 'package:mobile_slice/printer/printer_status.dart';

SliceOutcome outcome({String name = 'benchy.stl', int seconds = 3600, double grams = 12, String type = 'PLA', double layer = 0.2}) =>
    SliceOutcome(
      modelName: name,
      archivePath: '/x/${baseNameOf(name)}.gcode.3mf',
      printSeconds: seconds,
      grams: grams,
      meters: 4,
      layers: 100,
      supportUsed: false,
      layerHeight: layer,
      processLabel: 'Standard',
      filamentLabel: 'Generic $type',
      filamentType: type,
      infill: 15,
      walls: 2,
      warnings: const [],
      slicedAt: DateTime(2026),
    );

PrinterStatus status(String state, String name) =>
    const PrinterStatus().merge({'print': {'gcode_state': state, 'subtask_name': name}});

void main() {
  late Directory dir;
  late JsonStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('history_test');
    store = JsonStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('JsonStore', () {
    test('schreiben, lesen, löschen', () async {
      expect(await store.read('a'), isNull);
      await store.write('a', {'x': 1});
      expect(await store.readMap('a'), {'x': 1});
      expect(File('${dir.path}/a.json.tmp').existsSync(), isFalse);
      await store.delete('a');
      expect(await store.read('a'), isNull);
    });

    test('viele Schreibvorgänge hintereinander: der letzte gewinnt', () async {
      await Future.wait([for (var i = 0; i < 20; i++) store.write('n', i)]);
      expect(await store.read('n'), 19);
    });

    test('kaputte Datei wird beiseitegelegt statt die App zu blockieren', () async {
      File('${dir.path}/b.json').writeAsStringSync('{kaputt');
      expect(await store.read('b'), isNull);
      expect(File('${dir.path}/b.json.broken').existsSync(), isTrue);
    });

    test('Namen mit Pfadteilen werden abgelehnt', () {
      expect(() => store.write('../x', 1), throwsArgumentError);
    });
  });

  group('PrintHistory', () {
    test('Senden legt Eintrag an, Druckerstatus schließt ihn ab', () async {
      final history = PrintHistory(store);
      final sent = DateTime(2026, 11, 21, 10);
      await history.recordSent(outcome(), 'benchy', now: sent);
      expect(history.records.value.single.result, PrintResult.sent);

      expect(await history.applyStatus(status('PREPARE', 'benchy'), now: sent.add(const Duration(minutes: 1))), isNull);
      expect(history.records.value.single.result, PrintResult.printing);
      final done = await history.applyStatus(status('FINISH', 'benchy'), now: sent.add(const Duration(hours: 1)));
      expect(done!.result, PrintResult.finished);
      expect(done.finishedAt, sent.add(const Duration(hours: 1)));
      // Repeated FINISH reports change nothing.
      expect(await history.applyStatus(status('FINISH', 'benchy')), isNull);

      final reloaded = PrintHistory(store);
      await reloaded.load();
      expect(reloaded.records.value.single.result, PrintResult.finished);
    });

    test('veralteter FINISH direkt nach dem Senden schließt nicht ab', () async {
      final history = PrintHistory(store);
      final sent = DateTime(2026, 11, 21, 10);
      await history.recordSent(outcome(seconds: 7200), 'benchy', now: sent);
      expect(await history.applyStatus(status('FINISH', 'benchy'), now: sent.add(const Duration(seconds: 5))), isNull);
      expect(history.records.value.single.result, PrintResult.sent);
      // Later, without ever seeing it run (app was closed): plausible after half the estimate.
      final later = await history.applyStatus(status('FINISH', 'benchy'), now: sent.add(const Duration(hours: 3)));
      expect(later!.result, PrintResult.finished);
    });

    test('Abbruch und andere Dateinamen', () async {
      final history = PrintHistory(store);
      final sent = DateTime(2026, 11, 21, 10);
      await history.recordSent(outcome(), 'benchy', now: sent);
      expect(await history.applyStatus(status('RUNNING', 'anderes'), now: sent), isNull);
      expect(history.records.value.single.result, PrintResult.sent);
      await history.applyStatus(status('RUNNING', 'benchy'), now: sent);
      final failed = await history.applyStatus(status('FAILED', 'benchy'), now: sent.add(const Duration(minutes: 3)));
      expect(failed!.result, PrintResult.failed);
    });

    test('der neueste offene Eintrag mit dem Namen wird abgeschlossen', () async {
      final history = PrintHistory(store);
      final t = DateTime(2026, 11, 21, 10);
      await history.recordSent(outcome(), 'benchy', now: t);
      await history.recordSent(outcome(), 'benchy', now: t.add(const Duration(hours: 2)));
      await history.applyStatus(status('RUNNING', 'benchy'), now: t.add(const Duration(hours: 2)));
      expect(history.records.value.map((r) => r.result), [PrintResult.printing, PrintResult.sent]);
    });

    test('beschädigte Einträge werden übersprungen', () async {
      File('${dir.path}/history.json').writeAsStringSync(jsonEncode([
        {'id': 'a', 'sentAt': '2026-11-21T10:00:00.000', 'result': 'finished', 'modelName': 'ok'},
        {'id': 'b', 'sentAt': 'kein Datum'},
      ]));
      final history = PrintHistory(store);
      await history.load();
      expect(history.records.value.map((r) => r.modelName), ['ok']);
    });

    test('verpasstes Ende: Drucker aus oder nächster Druck schließt den gesehenen Druck nach der Schätzzeit ab', () async {
      final history = PrintHistory(store);
      final t = DateTime(2026, 11, 21, 10);
      await history.recordSent(outcome(seconds: 3600), 'benchy', now: t);
      await history.applyStatus(status('RUNNING', 'benchy'), now: t.add(const Duration(minutes: 5)));
      // Printer restarted: idle without a job name. Too early is not enough.
      expect(await history.applyStatus(status('IDLE', ''), now: t.add(const Duration(minutes: 30))), isNull);
      expect(history.records.value.single.result, PrintResult.printing);
      final done = await history.applyStatus(status('IDLE', ''), now: t.add(const Duration(hours: 2)));
      expect(done!.result, PrintResult.finished);

      // Never seen running: stays open for the user to decide.
      await history.recordSent(outcome(name: 'teil.stl', seconds: 60), 'teil', now: t.add(const Duration(hours: 3)));
      expect(await history.applyStatus(status('RUNNING', 'anderes'), now: t.add(const Duration(hours: 9))), isNull);
      expect(history.records.value.first.result, PrintResult.sent);

      await history.applyStatus(status('RUNNING', 'teil'), now: t.add(const Duration(hours: 9)));
      final moved = await history.applyStatus(status('PREPARE', 'nächster'), now: t.add(const Duration(hours: 10)));
      expect(moved!.modelName, 'teil.stl');
      expect(history.records.value.map((r) => r.result), [PrintResult.finished, PrintResult.finished]);
    });

    test('Jobname mit Dateiendung oder anderer Schreibweise passt', () async {
      final history = PrintHistory(store);
      final t = DateTime(2026, 11, 21, 10);
      await history.recordSent(outcome(), 'Benchy', now: t);
      await history.applyStatus(status('RUNNING', '/sdcard/benchy.gcode.3mf'), now: t);
      expect(history.records.value.single.result, PrintResult.printing);
      final done = await history.applyStatus(status('FINISH', 'BENCHY.3mf'), now: t.add(const Duration(hours: 1)));
      expect(done!.result, PrintResult.finished);
    });

    test('Ergebnis von Hand setzen', () async {
      final history = PrintHistory(store);
      final t = DateTime(2026, 11, 21, 10);
      final r = await history.recordSent(outcome(), 'benchy', now: t);
      await history.setResult(r.id, PrintResult.finished, now: t.add(const Duration(hours: 1)));
      expect(history.records.value.single.result, PrintResult.finished);
      expect(history.records.value.single.finishedAt, t.add(const Duration(hours: 1)));
      final reloaded = PrintHistory(store);
      await reloaded.load();
      expect(reloaded.records.value.single.result, PrintResult.finished);
    });

    test('Löschen', () async {
      final history = PrintHistory(store);
      final r = await history.recordSent(outcome(), 'benchy');
      await history.delete(r.id);
      expect(history.records.value, isEmpty);
    });
  });

  group('PrintStats', () {
    PrintRecord rec(PrintResult result, {int day = 1, int seconds = 3600, double grams = 10, String type = 'PLA'}) => PrintRecord(
          id: '$day',
          modelName: 'm',
          subtaskName: 'm',
          sentAt: DateTime(2026, 1, day),
          result: result,
          printSeconds: seconds,
          grams: grams,
          filamentType: type,
          filamentLabel: 'Generic $type',
          layerHeight: 0.2,
          processLabel: 'Standard',
        );

    test('Summen zählen nur fertige Drucke', () {
      final stats = PrintStats.from([
        rec(PrintResult.finished, day: 1, seconds: 3600, grams: 10),
        rec(PrintResult.finished, day: 2, seconds: 30000, grams: 200, type: 'petg'),
        rec(PrintResult.failed, day: 3, grams: 999),
        rec(PrintResult.sent, day: 4, grams: 999),
      ]);
      expect(stats.finished, 2);
      expect(stats.failed, 1);
      expect(stats.sent, 4);
      expect(stats.grams, 210);
      expect(stats.hours, closeTo(9.33, 0.01));
      expect(stats.longestSeconds, 30000);
      expect(stats.filamentTypes, {'PLA', 'PETG'});
      expect(stats.successRate, closeTo(2 / 3, 1e-9));
    });

    test('Serien: Abbruch setzt zurück, offene Drucke zählen nicht', () {
      final stats = PrintStats.from([
        rec(PrintResult.finished, day: 1),
        rec(PrintResult.finished, day: 2),
        rec(PrintResult.finished, day: 3),
        rec(PrintResult.failed, day: 4),
        rec(PrintResult.finished, day: 5),
        rec(PrintResult.sent, day: 6),
      ]);
      expect(stats.bestStreak, 3);
      expect(stats.currentStreak, 1);
      expect(stats.favoriteFilament, 'Generic PLA');
    });

    test('leer', () {
      final stats = PrintStats.from(const []);
      expect(stats.finished, 0);
      expect(stats.successRate, 0);
      expect(stats.favoriteFilament, isNull);
    });
  });
}
