import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/model/stl_reader.dart';
import 'package:mobile_slice/preview/model_viewer.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_slice/ui/pixel_progress.dart';
import 'package:mobile_slice/ui/pixel_text_field.dart';
import 'package:mobile_slice/ui/pixel_toggle.dart';

import '../model/model_test.dart' show box;
import '../support/fake_platform.dart';

void main() {
  late FakePlatform platform;

  setUp(() {
    platform = FakePlatform();
    final model = File('${platform.appDir.path}/benchy.stl')..writeAsBytesSync(writeBinaryStl(box(0, 0, 0, 20, 20, 20)));
    platform.nextPick = {'path': model.path, 'name': '3DBenchy.stl', 'bytes': model.lengthSync()};
    platform.onJob = (job) {
      final out = job['outputDir'] as String;
      if (job['type'] == 'preview') {
        final stl = File('$out/preview.stl')..writeAsBytesSync(writeBinaryStl(box(118, 118, 0, 138, 138, 20)));
        return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': true, 'triangles': 12}};
      }
      final archive = File('$out/${job['baseName']}.gcode.3mf')..writeAsBytesSync(Uint8List(10));
      return {
        'ok': true,
        'archivePath': archive.path,
        'engine': {'printSeconds': 3725.0, 'filamentGrams': 14.25, 'filamentMm': 4780.0, 'layers': 240, 'supportUsed': true},
      };
    };
  });

  tearDown(() => platform.dispose());

  testWidgets('Öffnen, Vorschau, Einstellungen ändern, Slicen, Ergebnis', (tester) async {
    useLargeScreen(tester);
    final services = await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    expect(find.text('3DBenchy.stl'), findsOneWidget);
    expect(find.textContaining('20,0 × 20,0 × 20,0 mm'), findsOneWidget);

    await tester.ensureVisible(find.text('Baum'));
    await tester.pump();
    await tester.tap(find.text('Baum'));
    await tester.pump();
    expect(services.settings.value.values, {'enable_support': true, 'support_type': 'tree(auto)'});
    expect(find.text('Aktiv: Standard · angepasst'), findsOneWidget);

    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Fertig gesliced!'));
    expect(find.text('1 h 02 min'), findsOneWidget);
    expect(find.text('14,3 g'), findsOneWidget);
    expect(find.text('3DBenchy.gcode.3mf'), findsOneWidget);

    final slice = platform.jobs.last;
    expect(slice['type'], 'slice');
    expect(slice['baseName'], '3DBenchy');
    expect(slice['modelId'], 'C12');
    expect(slice['process'], 'process/0.20.json');
    expect(jsonDecode(slice['overrides'] as String), {'enable_support': '1', 'support_type': 'tree(auto)'});
    expect(slice.containsKey('scale'), isFalse);

    // Settings survive a restart.
    final file = File('${platform.appDir.path}/data/settings.json');
    await settle(tester, until: () => file.existsSync() && file.readAsStringSync().contains('tree(auto)'));
    final saved = jsonDecode(File('${platform.appDir.path}/data/settings.json').readAsStringSync());
    expect(saved['values']['support_type'], 'tree(auto)');
  });

  testWidgets('Slicen zeigt Fortschritt und lässt sich abbrechen', (tester) async {
    useLargeScreen(tester);
    await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    platform.autoFinish = false;
    await tester.tap(find.text('Slicen'));
    await settle(tester, until: () => platform.runningJob != null);
    platform.progress(-1, 'process');
    platform.progress(42, 'Generating perimeters');
    await settleFinder(tester, find.text('42 %'));
    expect(find.text('Schichten berechnen'), findsOneWidget);
    expect(find.text('42 %'), findsOneWidget);
    expect(find.byType(PixelProgressBar), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settleFinder(tester, find.text('Slicen abgebrochen'));
    expect(find.text('Slicen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Fehler beim Slicen erscheint als Dialog', (tester) async {
    useLargeScreen(tester);
    await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    platform.onJob = (job) => {'ok': false, 'error': 'Validierung: zu groß'};
    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Slicen fehlgeschlagen'));
    expect(find.text('Validierung: zu groß'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
  });

  testWidgets('Modell zu groß: Slicen gesperrt', (tester) async {
    useLargeScreen(tester);
    final original = platform.onJob;
    platform.onJob = (job) {
      final result = original(job);
      return {...result, 'engine': {'fits': false}};
    };
    await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    expect(find.textContaining('passt nicht'), findsOneWidget);
    await tester.tap(find.text('Slicen'));
    await tester.pump();
    expect(platform.jobs.where((j) => j['type'] == 'slice'), isEmpty);
  });

  testWidgets('Preset-Kacheln, Geschwindigkeit, Fuzzy Skin und Weg zu allen Einstellungen', (tester) async {
    useLargeScreen(tester);
    final services = await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    await tester.tap(find.bySemanticsLabel('Preset Fuzzy-Optik'));
    await tester.pump();
    expect(services.settings.value.presetId, 'fuzzy');
    expect(services.settings.value.values['fuzzy_skin'], 'external');
    final fuzzy = find.byWidgetPredicate((w) => w is PixelToggle && w.label == 'Fuzzy Skin');
    expect(tester.widget<PixelToggle>(fuzzy).value, isTrue);
    await tester.ensureVisible(fuzzy);
    await tester.pump();
    await tester.tap(fuzzy);
    await tester.pump();
    expect(services.settings.value.values['fuzzy_skin'], isNull, reason: 'aus = Profilwert');
    expect(find.text('Aktiv: Fuzzy-Optik · angepasst'), findsOneWidget);

    final all = find.text('Alle Einstellungen · 1 geändert');
    await tester.ensureVisible(all);
    await tester.pump();
    await tester.tap(all);
    await settleFinder(tester, find.text('Kategorien'));
    expect(find.text('Presets'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Größe: Prozent, mm-Felder, Einpassen, Passt-Prüfung und Slice-Auftrag', (tester) async {
    useLargeScreen(tester);
    await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    final x = find.byWidgetPredicate((w) => w is PixelTextField && w.label == 'X in mm');
    await tester.ensureVisible(x);
    await tester.pump();
    await tester.enterText(find.descendant(of: x, matching: find.byType(EditableText)), '30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('150 %'), findsOneWidget);
    expect(find.textContaining('30,0 × 30,0 × 30,0 mm'), findsOneWidget);
    final z = find.descendant(of: find.byWidgetPredicate((w) => w is PixelTextField && w.label == 'Z in mm'), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(z).controller.text, '30,0');

    await tester.enterText(find.descendant(of: x, matching: find.byType(EditableText)), '400');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.textContaining('passt nicht'), findsOneWidget);
    await tester.tap(find.text('Slicen'));
    await tester.pump();
    expect(platform.jobs.where((j) => j['type'] == 'slice'), isEmpty);

    final fit = find.text('Auf Bett einpassen');
    await tester.ensureVisible(fit);
    await tester.pump();
    await tester.tap(fit);
    await tester.pump();
    expect(find.text('1250 %'), findsOneWidget, reason: 'Z 20 mm -> 250 mm Bauhöhe');
    expect(find.textContaining('passt nicht'), findsNothing);

    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Fertig gesliced!'));
    expect(platform.jobs.last['scale'], 12.5);
  });

  testWidgets('Überhang ohne Stützen zeigt eine Warnung, die Stützen einschaltet', (tester) async {
    useLargeScreen(tester);
    final onJob = platform.onJob;
    platform.onJob = (job) {
      if (job['type'] != 'preview') return onJob(job);
      final mesh = Float32List.fromList([...box(123, 123, 0, 133, 133, 10), ...box(118, 118, 10, 138, 138, 12)]);
      final stl = File('${job['outputDir']}/preview.stl')..writeAsBytesSync(writeBinaryStl(mesh));
      return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': true}};
    };
    final services = await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    expect(find.text('Dein Modell braucht wahrscheinlich Stützen'), findsOneWidget);
    await tester.ensureVisible(find.text('Stützen aktivieren'));
    await tester.tap(find.text('Stützen aktivieren'));
    await tester.pump();
    expect(services.settings.value.values['enable_support'], true);
    expect(find.text('Dein Modell braucht wahrscheinlich Stützen'), findsNothing);
  });

  testWidgets('Würfel ohne Überhang zeigt keine Stützen-Warnung', (tester) async {
    await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(ModelViewer));
    expect(find.text('Dein Modell braucht wahrscheinlich Stützen'), findsNothing);
  });
}
