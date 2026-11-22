import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/app_services.dart';
import 'package:mobile_slice/engine/slicer_channel.dart';
import 'package:mobile_slice/screens/settings_browser_screen.dart';
import 'package:mobile_slice/ui/pixel_button.dart';
import 'package:mobile_slice/ui/pixel_route.dart';
import 'package:mobile_slice/ui/pixel_theme.dart';

import '../support/fake_platform.dart';

/// The browser on its own, with AppScope above the navigator so pushed pages see the services.
Future<AppServices> pumpBrowser(WidgetTester tester, FakePlatform platform) async {
  useLargeScreen(tester);
  platform.install();
  rootBundle.clear();
  final services = AppServices(slicer: SlicerChannel());
  await tester.runAsync(services.init);
  await tester.pumpWidget(WidgetsApp(
    color: PixelColors.accent,
    textStyle: PixelTheme.body,
    pageRouteBuilder: <T>(settings, builder) => PixelRoute<T>(settings: settings, builder: builder),
    builder: (context, child) => AppScope(services: services, child: child!),
    home: const SettingsBrowserScreen(),
  ));
  await tester.pumpAndSettle();
  return services;
}

Finder button(String label) => find.byWidgetPredicate((w) => (w is PixelIconButton && w.label == label) || (w is PixelButton && w.label == label));

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakePlatform platform;
  setUp(() => platform = FakePlatform());
  tearDown(() => platform.dispose());

  testWidgets('Presets oben, Kategorien darunter, Suche über alles', (tester) async {
    await pumpBrowser(tester, platform);
    expect(find.text('Presets'), findsOneWidget);
    expect(find.text('Kategorien'), findsOneWidget);
    expect(find.text('Technisch und stabil'), findsOneWidget);
    expect(find.text('Oberfläche und Spezial'), findsOneWidget);
    expect(find.text('Aktiv: Standard'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'technisch');
    await tester.pumpAndSettle();
    expect(find.text('PRESETS'), findsOneWidget);
    expect(find.text('Kategorien'), findsNothing);

    await tester.enterText(find.byType(EditableText), 'fuzzy dicke');
    await tester.pumpAndSettle();
    expect(find.text('Fuzzy-Dicke'), findsOneWidget);
    expect(find.text('Oberfläche und Spezial'), findsOneWidget, reason: 'Kategorie-Hinweis');

    await tester.enterText(find.byType(EditableText), 'xyzzy');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nichts gefunden'), findsOneWidget);
  });

  testWidgets('Kategorie, Editor, Profilwert, Mehr anzeigen', (tester) async {
    final services = await pumpBrowser(tester, platform);
    await tapVisible(tester, find.text('Wände'));
    expect(find.text('Anzahl Wände'), findsOneWidget);
    expect(find.text('Füllung vor Wänden'), findsNothing);

    await tapVisible(tester, find.text('Anzahl Wände'));
    expect(find.text('Profilwert'), findsOneWidget);
    await tester.tap(button('Anzahl Wände erhöhen'));
    await tester.pumpAndSettle();
    expect(services.settings.value.values['wall_loops'], 3);
    expect(services.settings.value.presetId, 'standard');
    expect(find.text('geändert'), findsOneWidget);
    await tester.tap(button('Auf Profilwert zurücksetzen'));
    await tester.pumpAndSettle();
    expect(services.settings.value.values, isEmpty);
    await tester.tap(button('Anzahl Wände erhöhen'));
    await tester.tap(button('Schließen').last);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Anzahl Wände: 3, geändert'), findsOneWidget);

    await tapVisible(tester, find.textContaining('Mehr anzeigen'));
    expect(find.text('Füllung vor Wänden'), findsOneWidget);
  });

  testWidgets('Abhängige Einstellungen erscheinen erst bei Bedarf', (tester) async {
    final services = await pumpBrowser(tester, platform);
    await tapVisible(tester, find.text('Oberfläche und Spezial'));
    expect(find.text('Fuzzy-Dicke'), findsNothing);
    await tapVisible(tester, find.text('Fuzzy Skin'));
    await tester.tap(find.text('Außenkontur'));
    await tester.pumpAndSettle();
    await tester.tap(button('Schließen').last);
    await tester.pumpAndSettle();
    expect(services.settings.value.values['fuzzy_skin'], 'external');
    expect(find.text('Fuzzy-Dicke'), findsOneWidget);
  });

  testWidgets('Preset anwenden, anpassen, wiederherstellen, eigenes speichern und löschen', (tester) async {
    final services = await pumpBrowser(tester, platform);
    await tapVisible(tester, find.text('Technisch und stabil'));
    expect(services.settings.value.presetId, 'technical');
    expect(services.settings.value.values['wall_loops'], 4);
    expect(find.text('Aktiv: Technisch und stabil'), findsOneWidget);

    services.settings.value = services.settings.value.withValue('wall_loops', 6);
    await tester.pumpAndSettle();
    expect(find.text('Aktiv: Technisch und stabil · angepasst'), findsOneWidget);
    await tapVisible(tester, button('Preset wiederherstellen'));
    expect(services.settings.value.values['wall_loops'], 4);

    services.settings.value = services.settings.value.withValue('wall_loops', 5);
    await tester.pumpAndSettle();
    await tapVisible(tester, button('Aktuelle Einstellungen als Preset speichern'));
    await tester.enterText(find.byType(EditableText).last, 'Halter');
    await tester.tap(button('Speichern'));
    await tester.pumpAndSettle();
    await settle(tester, until: () => services.settings.value.presetId != 'technical');
    expect(services.presets.custom.value.single.name, 'Halter');
    expect(services.settings.value.presetId, services.presets.custom.value.single.id);
    expect(find.text('Aktiv: Halter'), findsOneWidget);

    await tapVisible(tester, button('Halter umbenennen'));
    await tester.enterText(find.byType(EditableText).last, 'Halter v2');
    await tester.tap(button('Umbenennen'));
    await tester.pumpAndSettle();
    expect(find.text('Halter v2'), findsOneWidget);

    await tapVisible(tester, button('Halter v2 löschen'));
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(services.presets.custom.value, isEmpty);
    expect(find.text('Aktiv: Eigene Einstellungen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Nur geänderte und alles zurücksetzen', (tester) async {
    final services = await pumpBrowser(tester, platform);
    services.settings.value = services.settings.value.withValue('nozzle_temperature', 230).copyWith(speedPercent: 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur geänderte'));
    await tester.pumpAndSettle();
    expect(find.text('Düsentemperatur'), findsOneWidget);
    expect(find.text('Geschwindigkeit: 120 %'), findsOneWidget);
    expect(find.text('Kategorien'), findsNothing);

    await tester.tap(find.text('Nur geänderte'));
    await tester.pumpAndSettle();
    await tapVisible(tester, button('Alles zurücksetzen'));
    await tester.tap(find.text('Zurücksetzen'));
    await tester.pumpAndSettle();
    expect(services.settings.value.values, isEmpty);
    expect(services.settings.value.speedPercent, 100);
  });
}
