import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/data/print_history.dart';
import 'package:mobile_slice/engine/slicer_channel.dart';
import 'package:mobile_slice/model/stl_reader.dart';
import 'package:mobile_slice/printer/printer_status.dart';
import 'package:mobile_slice/screens/model_screen.dart';
import 'package:mobile_slice/ui/pixel_button.dart';

import '../data/history_test.dart' show outcome;
import '../model/model_test.dart' show box;
import '../support/fake_platform.dart';

void main() {
  late FakePlatform platform;
  setUp(() {
    platform = FakePlatform();
    platform.onJob = (job) {
      final stl = File('${job['outputDir']}/preview.stl')..writeAsBytesSync(writeBinaryStl(box(118, 118, 0, 138, 138, 20)));
      return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': true}};
    };
  });
  tearDown(() => platform.dispose());

  testWidgets('Verlauf und Trophäen zeigen abgeschlossene Drucke', (tester) async {
    final services = await pumpApp(tester, platform);
    await tester.runAsync(() async {
      final t = DateTime(2026, 11, 21, 3);
      await services.history.recordSent(outcome(name: '3DBenchy.stl', grams: 14.2), '3DBenchy', now: t);
      await services.history.applyStatus(
        const PrinterStatus().merge({'print': {'gcode_state': 'RUNNING', 'subtask_name': '3DBenchy'}}),
        now: t,
      );
      await services.history.applyStatus(
        const PrinterStatus().merge({'print': {'gcode_state': 'FINISH', 'subtask_name': '3DBenchy'}}),
        now: t.add(const Duration(hours: 1)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    await tester.tap(find.text('Verlauf').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3DBenchy.stl'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    // 14,2 g at the default 25 €/kg.
    expect(find.text('0,35 €'), findsOneWidget);

    await tester.tap(find.text('Trophäen').last);
    await tester.pump(const Duration(milliseconds: 500));
    // Erster Druck, Kapitän (Benchy) and Nachteule (3 Uhr).
    expect(find.text('3 von 14 freigeschaltet'), findsOneWidget);
    expect(find.text('Kapitän'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('Offener Druck lässt sich im Verlauf als fertig markieren und bringt die Trophäe', (tester) async {
    final services = await pumpApp(tester, platform);
    await tester.runAsync(() async {
      await services.history.recordSent(outcome(name: 'teil.stl'), 'teil', now: DateTime(2026, 11, 21, 12));
    });
    await tester.pump();
    await tester.tap(find.text('Verlauf').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Gesendet'), findsOneWidget);

    await tester.tap(find.text('Gesendet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig gedruckt'));
    await settle(tester, until: () => services.trophies.unlocked.value.containsKey('first_print'));
    expect(services.history.records.value.single.result, PrintResult.finished);
    await settleFinder(tester, find.text('Erster Druck'));
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('Werkstatt: Testwürfel, zuletzt geöffnet, Einstellungen', (tester) async {
    useLargeScreen(tester);
    final services = await pumpApp(tester, platform);
    await tester.tap(find.text('Testwürfel ausprobieren'));
    await settleFinder(tester, find.byType(ModelScreen));
    await settle(tester, until: () => platform.jobs.isNotEmpty);
    expect(platform.jobs.last['model'], endsWith('engine/models/test_cube.stl'));
    expect(services.recent.models.value, isEmpty, reason: 'Beispielmodell nicht in der Liste');
    Navigator.of(tester.element(find.byType(ModelScreen))).pop();
    await settle(tester, until: () => find.byType(ModelScreen, skipOffstage: false).evaluate().isEmpty);

    final dir = Directory('${platform.appDir.path}/models')..createSync();
    final file = File('${dir.path}/1_teil.stl')..writeAsBytesSync(writeBinaryStl(box(0, 0, 0, 5, 5, 5)));
    platform.nextPick = {'path': file.path, 'name': 'teil.stl', 'bytes': 84 + 12 * 50};
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelScreen));
    expect(services.recent.models.value.single.name, 'teil.stl');
    Navigator.of(tester.element(find.byType(ModelScreen))).pop();
    await settle(tester, until: () => find.byType(ModelScreen, skipOffstage: false).evaluate().isEmpty);
    expect(find.text('teil.stl'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Einstellungen'));
    await settleFinder(tester, find.text('Diagnose-Log teilen'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Diagnose-Log teilen'));
    await tester.pump();
    expect(platform.calls.map((c) => c.method), contains('shareLog'));
    expect(find.text('Slicer-Engine installiert'), findsOneWidget);
  });

  test('Ergebnis-Felder aus dem Kanal', () {
    final result = EngineResult.fromMap({'ok': true, 'engine': {'fits': false}});
    expect(result.fits, isFalse);
  });
}
