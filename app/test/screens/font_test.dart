import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/data/app_settings.dart';
import 'package:mobile_slice/data/json_store.dart';
import 'package:mobile_slice/ui/pixel_button.dart';
import 'package:mobile_slice/ui/pixel_theme.dart';

import '../support/fake_platform.dart';

void main() {
  late FakePlatform platform;
  setUp(() => platform = FakePlatform());
  tearDown(() {
    PixelTheme.font.value = AppFont.pixelify;
    platform.dispose();
  });

  test('Schriftgröße und Familie folgen der gewählten Schrift', () {
    expect(PixelTheme.text(PixelTextKind.body).fontFamily, 'PixelifySans');
    expect(PixelTheme.text(PixelTextKind.body).fontSize, 16);
    PixelTheme.font.value = AppFont.atkinson;
    expect(PixelTheme.text(PixelTextKind.heading).fontFamily, 'AtkinsonHyperlegible');
    expect(PixelTheme.text(PixelTextKind.heading).fontSize, closeTo(20 * AppFont.atkinson.scale, 1e-9));
    PixelTheme.font.value = AppFont.system;
    expect(PixelTheme.text(PixelTextKind.body).fontFamily, isNull);
  });

  test('Schriftwahl wird gespeichert und geladen, Unbekanntes fällt auf Pixelify zurück', () async {
    final dir = Directory.systemTemp.createTempSync('app_settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = JsonStore(dir);
    await AppSettings(store).setFont(AppFont.atkinson);
    PixelTheme.font.value = AppFont.pixelify;
    await AppSettings(store).load();
    expect(PixelTheme.font.value, AppFont.atkinson);
    await store.write('app_settings', {'font': 'comic'});
    await AppSettings(store).load();
    expect(PixelTheme.font.value, AppFont.pixelify);
  });

  test('Filamentpreis wird gespeichert, Unsinn fällt auf den Standard zurück', () async {
    final dir = Directory.systemTemp.createTempSync('app_settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = JsonStore(dir);
    final settings = AppSettings(store);
    await settings.load();
    expect(settings.pricePerKg.value, AppSettings.defaultPricePerKg);
    await settings.setFont(AppFont.atkinson);
    await settings.setPricePerKg(32);
    final again = AppSettings(store);
    await again.load();
    expect(again.pricePerKg.value, 32);
    expect(again.font, AppFont.atkinson);
    await store.write('app_settings', {'pricePerKg': -3});
    await again.load();
    expect(again.pricePerKg.value, AppSettings.defaultPricePerKg);
    expect(filamentCost(250, 32), 8);
  });

  testWidgets('Wechsel im Einstellungsbildschirm baut die ganze App mit neuer Schrift auf', (tester) async {
    useLargeScreen(tester);
    await pumpApp(tester, platform);
    await tester.tap(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Einstellungen'));
    await settleFinder(tester, find.text('Darstellung'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('Darstellung')).style!.fontFamily, 'PixelifySans');

    await tester.tap(find.text('Atkinson Hyperlegible'));
    await tester.pump();
    expect(PixelTheme.font.value, AppFont.atkinson);
    final heading = tester.widget<Text>(find.text('Darstellung'));
    expect(heading.style!.fontFamily, 'AtkinsonHyperlegible');
    expect(heading.style!.fontSize, closeTo(20 * AppFont.atkinson.scale, 1e-9));
    // Screens below the current route are rebuilt too.
    await tester.tap(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Zurück'));
    await tester.pumpAndSettle();
    for (final text in tester.widgetList<Text>(find.text('Werkstatt'))) {
      expect(text.style!.fontFamily, 'AtkinsonHyperlegible');
    }

    final file = File('${platform.appDir.path}/data/app_settings.json');
    await settle(tester, until: () => file.existsSync() && file.readAsStringSync().contains('atkinson'));
    expect(jsonDecode(file.readAsStringSync())['font'], 'atkinson');

    await tester.tap(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Einstellungen'));
    await settleFinder(tester, find.text('System (Roboto)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System (Roboto)'));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Darstellung')).style!.fontFamily, isNull);
    await tester.ensureVisible(find.text('Schrift: Atkinson Hyperlegible (OFL)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schrift: Atkinson Hyperlegible (OFL)'));
    await settleFinder(tester, find.textContaining('Braille Institute'));
  });
}
