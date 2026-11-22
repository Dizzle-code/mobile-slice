import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/model/stl_reader.dart';
import 'package:mobile_slice/preview/plate_viewer.dart';
import 'package:mobile_slice/screens/preset_widgets.dart';
import 'package:mobile_slice/screens/workspace_screen.dart';
import 'package:mobile_slice/ui/pixel_button.dart';
import 'package:mobile_slice/ui/pixel_icons.dart';
import 'package:mobile_slice/ui/pixel_progress.dart';
import 'package:mobile_slice/ui/pixel_stepper.dart';
import 'package:mobile_slice/ui/pixel_text_field.dart';
import 'package:mobile_slice/ui/pixel_toggle.dart';

import '../model/model_test.dart' show box;
import '../support/fake_platform.dart';

/// Phone-sized but tall, so the whole workspace list is laid out.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(480, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

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

  Future<void> openModel(WidgetTester tester) async {
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(PlateViewer));
    await settle(tester, until: () => find.text('Modell wird geladen …').evaluate().isEmpty && find.text('3DBenchy.stl').evaluate().isNotEmpty);
  }

  Map<String, Object?> plateOf(Map<Object?, Object?> job) =>
      (jsonDecode(File(job['plate'] as String).readAsStringSync()) as Map).cast<String, Object?>();

  testWidgets('Handy: Öffnen, Einstellungen ändern, Slicen der Platte, Ergebnis', (tester) async {
    usePhoneScreen(tester);
    final services = await pumpApp(tester, platform);
    await openModel(tester);
    expect(find.byType(WorkspaceScreen), findsOneWidget);
    expect(find.textContaining('20,0 × 20,0 × 20,0 mm'), findsOneWidget);

    await tester.ensureVisible(find.text('Baum'));
    await tester.pump();
    await tester.tap(find.text('Baum'));
    await tester.pump();
    expect(services.settings.value.values, {'enable_support': true, 'support_type': 'tree(auto)'});

    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Fertig gesliced!'));
    expect(find.text('1 h 02 min'), findsOneWidget);
    expect(find.text('3DBenchy.gcode.3mf'), findsOneWidget);

    final slice = platform.jobs.last;
    expect(slice['type'], 'slice');
    expect(slice['baseName'], '3DBenchy');
    expect(slice['modelId'], 'C12');
    expect(jsonDecode(slice['overrides'] as String), {'enable_support': '1', 'support_type': 'tree(auto)'});
    final plate = plateOf(slice);
    expect(plate['objects'], [
      {'model': platform.nextPick!['path'], 'x': 128.0, 'y': 128.0},
    ]);
  });

  testWidgets('Desktop: Seitenleiste, mehrere Objekte, Kopie, zweite Platte, Slicen pro Platte', (tester) async {
    useLargeScreen(tester);
    final services = await pumpApp(tester, platform);
    expect(find.text('Vorbereiten'), findsOneWidget, reason: 'Desktop-Seitenleiste');
    await openModel(tester);
    final project = services.project;
    expect(project.plate.objects, hasLength(1));

    await tester.tap(find.text('Kopie'));
    await tester.pump();
    expect(project.plate.objects, hasLength(2));
    final a = project.plate.objects[0].footprint, b = project.plate.objects[1].footprint;
    expect(a.maxX <= b.minX || b.maxX <= a.minX || a.maxY <= b.minY || b.maxY <= a.minY, isTrue, reason: 'Kopie überlappt nicht');

    // The copy goes to a new plate.
    await tester.ensureVisible(find.text('Neue Platte'));
    await tester.pump();
    await tester.tap(find.text('Neue Platte'));
    await tester.pump();
    expect(project.plates, hasLength(2));
    expect(project.plateIndex, 1);
    expect(find.text('Platte 2 slicen'), findsOneWidget);

    await tester.tap(find.text('Platte 2 slicen'));
    await settleFinder(tester, find.text('Fertig gesliced!'));
    final slice = platform.jobs.last;
    expect(slice['baseName'], '3DBenchy_Platte_2');
    expect((plateOf(slice)['objects'] as List), hasLength(1));
    expect(project.plates[0].objects, hasLength(1));
  });

  testWidgets('Desktop: Objekt per Ziehen verschieben, Pfeiltasten, Rückgängig', (tester) async {
    useLargeScreen(tester);
    final services = await pumpApp(tester, platform);
    await openModel(tester);
    final project = services.project;
    final viewer = find.byType(PlateViewer);
    await settle(tester, until: () => tester.state<PlateViewerState>(viewer).frame?.triangleCount != null && tester.state<PlateViewerState>(viewer).frame!.triangleCount > 0);

    // Top view makes screen movement map straight onto the bed.
    tester.state<PlateViewerState>(viewer).resetView(top: true);
    await settle(tester, until: () => tester.state<PlateViewerState>(viewer).camera.pitch > 1.5 && tester.state<PlateViewerState>(viewer).frame!.view.camera.pitch > 1.5);
    final frame = tester.state<PlateViewerState>(viewer).frame!;
    final (sx, sy, _) = frame.view.toScreen(128, 128, 20);
    final origin = tester.getTopLeft(viewer);
    project.select(null);
    await tester.pump();
    final gesture = await tester.startGesture(origin + Offset(sx, sy));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    final moved = project.selected!;
    expect(moved.x, greaterThan(140), reason: 'nach rechts gezogen');
    expect(moved.y, closeTo(128, 2));

    final focus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(project.selected!.y, closeTo(moved.y + 1, 0.01), reason: 'Fokus: $focus');

    project.undo();
    project.undo();
    await tester.pump();
    expect([project.selected!.x, project.selected!.y], [128, 128], reason: 'Ziehen ist ein Schritt');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Slicen zeigt Fortschritt und lässt sich abbrechen', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, platform);
    await openModel(tester);
    platform.autoFinish = false;
    await tester.tap(find.text('Slicen'));
    await settle(tester, until: () => platform.runningJob != null);
    platform.progress(-1, 'process');
    platform.progress(42, 'Generating perimeters');
    await settleFinder(tester, find.text('42 %'));
    expect(find.text('Schichten berechnen'), findsOneWidget);
    expect(find.byType(PixelProgressBar), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settleFinder(tester, find.text('Slicen abgebrochen'));
    expect(find.text('Slicen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Fehler beim Slicen erscheint als Dialog', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, platform);
    await openModel(tester);
    platform.onJob = (job) => {'ok': false, 'error': 'Validierung: zu groß'};
    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Slicen fehlgeschlagen'));
    expect(find.text('Validierung: zu groß'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
  });

  testWidgets('Zu großes Objekt: Hinweis, Slicen gesperrt, Einpassen hilft', (tester) async {
    usePhoneScreen(tester);
    platform.onJob = (job) {
      final stl = File('${job['outputDir']}/preview.stl')..writeAsBytesSync(writeBinaryStl(box(0, 0, 0, 400, 30, 20)));
      return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': false}};
    };
    final services = await pumpApp(tester, platform);
    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.textContaining('größer als das Druckbett'));
    await settle(tester, until: () => find.text('Modell wird geladen …').evaluate().isEmpty);
    expect(services.project.plateFits(0), isFalse);
    final slice = find.widgetWithText(PixelButton, 'Slicen');
    expect(tester.widget<PixelButton>(slice).onPressed, isNull);

    await tester.ensureVisible(find.text('Auf Bett einpassen'));
    await tester.pump();
    await tester.tap(find.text('Auf Bett einpassen'));
    await tester.pump();
    expect(services.project.plateFits(0), isTrue);
    expect(services.project.selected!.footprint.sizeX, closeTo(256, 0.5));
    expect(tester.widget<PixelButton>(find.widgetWithText(PixelButton, 'Slicen')).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Objekt: Position per Feld, Drehen, Größe landen im Plattenauftrag', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, platform);
    await openModel(tester);
    final x = find.byWidgetPredicate((w) => w is PixelTextField && w.label == 'X in mm');
    await tester.ensureVisible(x);
    await tester.pump();
    await tester.enterText(find.descendant(of: x, matching: find.byType(EditableText)), '60');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    Finder plusOf(String label) => find.descendant(
          of: find.byWidgetPredicate((w) => w is PixelStepper && w.label == label),
          matching: find.byWidgetPredicate((w) => w is PixelIconButton && w.icon == PixelIcons.plus),
        );
    await tester.ensureVisible(plusOf('Um Z'));
    await tester.pump();
    await tester.tap(plusOf('Um Z'));
    await tester.pump();
    await tester.ensureVisible(find.text('Umdrehen'));
    await tester.pump();
    await tester.tap(find.text('Umdrehen'));
    await tester.pump();

    await tester.ensureVisible(plusOf('Größe'));
    await tester.pump();
    await tester.tap(plusOf('Größe'));
    await tester.pump();

    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Fertig gesliced!'));
    final object = (plateOf(platform.jobs.last)['objects'] as List).single as Map;
    expect(object['x'], 60.0);
    expect(object['rotZ'], 15.0);
    expect(object['rotX'], 180.0);
    expect(object['scale'], 1.05);
  });

  testWidgets('Preset-Kacheln, Fuzzy Skin und Weg zu allen Einstellungen', (tester) async {
    useLargeScreen(tester);
    final services = await pumpApp(tester, platform);
    await openModel(tester);
    // The preset strip scrolls sideways; bring the tile into view first.
    final tile = find.bySemanticsLabel('Preset Fuzzy-Optik', skipOffstage: false);
    await tester.scrollUntilVisible(tile, 120, scrollable: find.descendant(of: find.byType(PresetStrip), matching: find.byType(Scrollable)));
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    expect(services.settings.value.presetId, 'fuzzy');
    final fuzzy = find.byWidgetPredicate((w) => w is PixelToggle && w.label == 'Fuzzy Skin');
    expect(tester.widget<PixelToggle>(fuzzy).value, isTrue);
    await tester.ensureVisible(fuzzy);
    await tester.pump();
    await tester.tap(fuzzy);
    await tester.pump();
    expect(services.settings.value.values['fuzzy_skin'], isNull, reason: 'aus = Profilwert');

    final all = find.text('Alle Einstellungen · 1 geändert');
    await tester.ensureVisible(all);
    await tester.pump();
    await tester.tap(all);
    await settleFinder(tester, find.text('Kategorien'));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Überhang ohne Stützen zeigt eine Warnung, die Stützen einschaltet', (tester) async {
    usePhoneScreen(tester);
    platform.onJob = (job) {
      final mesh = Float32List.fromList([...box(123, 123, 0, 133, 133, 10), ...box(118, 118, 10, 138, 138, 12)]);
      final stl = File('${job['outputDir']}/preview.stl')..writeAsBytesSync(writeBinaryStl(mesh));
      return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': true}};
    };
    final services = await pumpApp(tester, platform);
    await openModel(tester);
    expect(find.text('Überhänge: braucht wahrscheinlich Stützen.'), findsOneWidget);
    await tester.ensureVisible(find.text('Stützen aktivieren'));
    await tester.tap(find.text('Stützen aktivieren'));
    await tester.pump();
    expect(services.settings.value.values['enable_support'], true);
    expect(find.text('Überhänge: braucht wahrscheinlich Stützen.'), findsNothing);
  });

  testWidgets('Würfel ohne Überhang zeigt keine Stützen-Warnung', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, platform);
    await openModel(tester);
    expect(find.text('Überhänge: braucht wahrscheinlich Stützen.'), findsNothing);
  });
}
