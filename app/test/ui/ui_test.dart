import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/ui/pixel_button.dart';
import 'package:mobile_slice/ui/pixel_choice.dart';
import 'package:mobile_slice/ui/pixel_frame.dart';
import 'package:mobile_slice/ui/pixel_icon.dart';
import 'package:mobile_slice/ui/pixel_icons.dart';
import 'package:mobile_slice/ui/pixel_overlay.dart';
import 'package:mobile_slice/ui/pixel_progress.dart';
import 'package:mobile_slice/ui/pixel_route.dart';
import 'package:mobile_slice/ui/pixel_scaffold.dart';
import 'package:mobile_slice/ui/pixel_slider.dart';
import 'package:mobile_slice/ui/pixel_tab_bar.dart';
import 'package:mobile_slice/ui/pixel_text.dart';
import 'package:mobile_slice/ui/pixel_text_field.dart';
import 'package:mobile_slice/ui/pixel_theme.dart';
import 'package:mobile_slice/ui/pixel_toggle.dart';
import 'package:mobile_slice/ui/stat_tile.dart';
import 'package:mobile_slice/ui/trophy_badge.dart';

Widget host(Widget child) => WidgetsApp(
      color: PixelColors.accent,
      textStyle: PixelTheme.body,
      pageRouteBuilder: <T>(settings, builder) => PixelRoute<T>(settings: settings, builder: builder),
      home: PixelScaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  group('Theme', () {
    test('Schriftgrößen sind Vielfache von 4', () {
      for (final kind in PixelTextKind.values) {
        expect(PixelTheme.fontSize(kind) % 4, 0, reason: kind.name);
      }
    });

    testWidgets('PixelText nutzt Pixelify Sans', (tester) async {
      await tester.pumpWidget(host(const PixelText.title('Hallo')));
      final text = tester.widget<Text>(find.text('Hallo'));
      expect(text.style!.fontFamily, PixelTheme.fontFamily);
      expect(text.style!.fontSize, 24);
    });
  });

  group('Icons', () {
    test('alle Glyphen passen in 16x16 und sind nicht leer', () {
      for (final glyph in PixelIcons.all) {
        expect(glyph.rows.length, lessThanOrEqualTo(16), reason: glyph.name);
        expect(glyph.main.length + glyph.second.length, greaterThan(10), reason: glyph.name);
      }
    });

    test('zu große Glyphe wird abgelehnt', () {
      expect(() => PixelGlyph('x', ['#' * 17]), throwsArgumentError);
    });

    testWidgets('PixelIcon hat Größe 16 × scale', (tester) async {
      await tester.pumpWidget(host(Center(child: PixelIcon(PixelIcons.cube, scale: 3, semanticLabel: 'Würfel'))));
      expect(tester.getSize(find.byType(CustomPaint).last), const Size(48, 48));
      expect(find.bySemanticsLabel('Würfel'), findsOneWidget);
    });
  });

  group('Rahmen', () {
    test('Treppenrahmen spart die Ecken aus', () {
      final path = steppedRect(const Rect.fromLTWH(0, 0, 40, 40));
      expect(path.contains(const Offset(1, 1)), isFalse);
      expect(path.contains(const Offset(20, 1)), isTrue);
      expect(path.contains(const Offset(1, 20)), isTrue);
    });

    testWidgets('PixelPanel reserviert Platz für den Schatten', (tester) async {
      await tester.pumpWidget(host(const Center(
        child: PixelPanel(padding: EdgeInsets.zero, child: SizedBox(width: 40, height: 40)),
      )));
      // 4 px border on each side plus 4 px shadow below.
      expect(tester.getSize(find.byType(PixelPanel)), const Size(48, 52));
    });
  });

  group('PixelButton', () {
    testWidgets('löst aus und sinkt beim Drücken ein', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(Center(child: PixelButton(label: 'Slicen', onPressed: () => taps++))));
      final gesture = await tester.startGesture(tester.getCenter(find.text('Slicen')));
      await tester.pump();
      expect(tester.widget<PixelPanel>(find.byType(PixelPanel).last).pressed, isTrue);
      await gesture.up();
      await tester.pump();
      expect(taps, 1);
      expect(tester.widget<PixelPanel>(find.byType(PixelPanel).last).pressed, isFalse);
    });

    testWidgets('deaktiviert reagiert nicht und ist als solcher markiert', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const Center(child: PixelButton(label: 'Senden', onPressed: null))));
      await tester.tap(find.text('Senden'));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Senden')),
        matchesSemantics(label: 'Senden', isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets('PixelIconButton hat Mindestgröße 48', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(Center(child: PixelIconButton(icon: PixelIcons.back, label: 'Zurück', onPressed: () => taps++))));
      expect(tester.getSize(find.byType(PixelIconButton)).width, greaterThanOrEqualTo(48));
      await tester.tap(find.byType(PixelIconButton));
      expect(taps, 1);
    });
  });

  group('PixelProgressBar', () {
    testWidgets('zeigt Prozent in der Semantik', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const PixelProgressBar(value: 0.42, semanticLabel: 'Slicen')));
      expect(tester.getSemantics(find.bySemanticsLabel('Slicen')).value, '42 %');
      handle.dispose();
    });

    testWidgets('unbestimmt animiert', (tester) async {
      await tester.pumpWidget(host(const PixelProgressBar(value: null)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(host(const PixelProgressBar(value: 1)));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('PixelSlider', () {
    testWidgets('rastet auf Stufen ein und zeigt den Wert', (tester) async {
      double value = 15;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => PixelSlider(
          label: 'Füllung',
          value: value,
          min: 0,
          max: 100,
          divisions: 20,
          format: (v) => '${v.round()} %',
          onChanged: (v) => setState(() => value = v),
        ),
      )));
      expect(find.text('15'), findsOneWidget);
      final box = tester.getRect(find.byType(GestureDetector).last);
      await tester.tapAt(Offset(box.right - 1, box.center.dy));
      await tester.pump();
      expect(value, 100);
      await tester.tapAt(Offset(box.left + box.width * 0.52, box.center.dy));
      await tester.pump();
      expect(value % 5, 0);
    });

    testWidgets('Bedienhilfe kann erhöhen', (tester) async {
      final handle = tester.ensureSemantics();
      double? changed;
      await tester.pumpWidget(host(PixelSlider(
        label: 'Wände',
        value: 2,
        min: 1,
        max: 6,
        divisions: 5,
        onChanged: (v) => changed = v,
      )));
      expect(tester.getSemantics(find.bySemanticsLabel('Wände')).value, '2');
      tester.semantics.increase(find.semantics.byLabel('Wände'));
      expect(changed, 3);
      handle.dispose();
    });

    testWidgets('Zahl lässt sich eintippen und wird begrenzt', (tester) async {
      double value = 15;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => PixelSlider(
          label: 'Füllung',
          value: value,
          min: 0,
          max: 100,
          divisions: 20,
          unit: '%',
          onChanged: (v) => setState(() => value = v),
        ),
      )));
      final field = find.byType(EditableText);
      await tester.tap(field);
      await tester.enterText(field, '17');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 17);
      expect(find.text('17'), findsOneWidget);

      await tester.tap(field);
      await tester.enterText(field, '250');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 100);
      expect(find.text('100'), findsOneWidget);

      await tester.tap(field);
      await tester.enterText(field, ',');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 100);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('Eingabe mit Komma und eigener Umrechnung', (tester) async {
      double? changed;
      const heights = [0.08, 0.12, 0.2, 0.28];
      await tester.pumpWidget(host(PixelSlider(
        label: 'Schichthöhe',
        value: 2,
        min: 0,
        max: 3,
        divisions: 3,
        inputDigits: 2,
        toInput: (v) => heights[v.round()],
        fromInput: (mm) => heights.indexWhere((h) => h >= mm - 0.03).toDouble(),
        onChanged: (v) => changed = v,
      )));
      expect(find.text('0,20'), findsOneWidget);
      final field = find.byType(EditableText);
      await tester.tap(field);
      await tester.enterText(field, '0,12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changed, 1);
    });
  });

  group('PixelToggle', () {
    testWidgets('schaltet über die ganze Zeile um', (tester) async {
      var value = false;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) =>
            PixelToggle(label: 'Stützen', value: value, onChanged: (v) => setState(() => value = v)),
      )));
      await tester.tap(find.text('Stützen'));
      await tester.pump();
      expect(value, isTrue);
    });
  });

  group('Auswahl', () {
    testWidgets('Segmente wählen genau einen Wert', (tester) async {
      var value = 'a';
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => PixelSegmented<String>(
          options: const [PixelOption('a', 'Aus'), PixelOption('b', 'Normal'), PixelOption('c', 'Baum')],
          value: value,
          onChanged: (v) => setState(() => value = v),
        ),
      )));
      await tester.tap(find.text('Baum'));
      await tester.pump();
      expect(value, 'c');
    });

    testWidgets('Liste zeigt Untertitel und wählt', (tester) async {
      var value = 1;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => PixelChoiceList<int>(
          options: const [
            PixelOption(1, 'Generic PLA', subtitle: '220 °C', swatch: Color(0xFFFFFFFF)),
            PixelOption(2, 'Generic PETG', subtitle: '255 °C'),
          ],
          value: value,
          onChanged: (v) => setState(() => value = v),
        ),
      )));
      expect(find.text('255 °C'), findsOneWidget);
      await tester.tap(find.text('Generic PETG'));
      await tester.pump();
      expect(value, 2);
    });
  });

  group('PixelTextField', () {
    testWidgets('nimmt Text an und zeigt Hinweis nur wenn leer', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(PixelTextField(controller: controller, label: 'IP-Adresse', hint: '192.168.1.50')));
      expect(find.text('192.168.1.50'), findsOneWidget);
      await tester.tap(find.byType(EditableText));
      await tester.enterText(find.byType(EditableText), '10.0.0.7');
      await tester.pump();
      expect(controller.text, '10.0.0.7');
      expect(find.text('192.168.1.50'), findsNothing);
    });

    testWidgets('zeigt Fehlertext', (tester) async {
      await tester.pumpWidget(host(PixelTextField(controller: TextEditingController(), label: 'Code', errorText: 'Fehlt')));
      expect(find.text('Fehlt'), findsOneWidget);
    });
  });

  group('Overlay', () {
    testWidgets('Dialog liefert gewählte Aktion', (tester) async {
      await tester.pumpWidget(host(const SizedBox()));
      final context = tester.element(find.byType(SizedBox).last);
      final result = showPixelDialog<bool>(
        context,
        title: 'Druck abbrechen?',
        message: 'Der Druck wird gestoppt.',
        actions: const [PixelDialogAction('Nein', false), PixelDialogAction('Ja', true)],
      );
      await tester.pumpAndSettle();
      expect(find.text('Druck abbrechen?'), findsOneWidget);
      await tester.tap(find.text('Ja'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('Toast verschwindet von selbst', (tester) async {
      await tester.pumpWidget(host(const SizedBox()));
      PixelToast.show(tester.element(find.byType(SizedBox).last), 'Gespeichert');
      await tester.pump();
      expect(find.text('Gespeichert'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Gespeichert'), findsNothing);
    });

    testWidgets('Trophäen-Pop-ups kommen nacheinander', (tester) async {
      TrophyPopup.reset();
      await tester.pumpWidget(host(const SizedBox()));
      final context = tester.element(find.byType(SizedBox).last);
      TrophyPopup.show(context, TrophyPopupData(glyph: PixelIcons.star, name: 'Erster Druck', description: 'a'));
      TrophyPopup.show(context, TrophyPopupData(glyph: PixelIcons.star, name: 'Fünferpack', description: 'b'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Erster Druck'), findsOneWidget);
      expect(find.text('Fünferpack'), findsNothing);
      await tester.tap(find.text('Erster Druck'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Fünferpack'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Fünferpack'), findsNothing);
    });
  });

  group('Navigation', () {
    testWidgets('Tab-Leiste meldet Auswahl', (tester) async {
      var index = 0;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => Align(
          alignment: Alignment.bottomCenter,
          child: PixelTabBar(
            items: [PixelTabItem(PixelIcons.hammer, 'Werkstatt'), PixelTabItem(PixelIcons.printer, 'Drucker')],
            index: index,
            onSelected: (i) => setState(() => index = i),
          ),
        ),
      )));
      await tester.tap(find.text('Drucker'));
      await tester.pumpAndSettle();
      expect(index, 1);
    });

    testWidgets('Scaffold zeigt Titel und Zurück', (tester) async {
      var back = 0;
      await tester.pumpWidget(WidgetsApp(
        color: PixelColors.accent,
        textStyle: PixelTheme.body,
        pageRouteBuilder: <T>(settings, builder) => PixelRoute<T>(settings: settings, builder: builder),
        home: PixelScaffold(title: 'Modell', onBack: () => back++, body: const SizedBox()),
      ));
      expect(find.text('Modell'), findsOneWidget);
      await tester.tap(find.byType(PixelIconButton));
      expect(back, 1);
    });

    test('Wisch-Übergang deckt am Anfang nichts und am Ende alles auf', () {
      const size = Size(320, 640);
      expect(PixelWipeClipper(0).getClip(size).contains(const Offset(300, 600)), isFalse);
      expect(PixelWipeClipper(0.5).getClip(size).contains(const Offset(4, 4)), isTrue);
      expect(PixelWipeClipper(1).getClip(size).contains(const Offset(319, 639)), isTrue);
    });

    testWidgets('PixelRoute öffnet neue Seite', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(WidgetsApp(
        navigatorKey: key,
        color: PixelColors.accent,
        textStyle: PixelTheme.body,
        pageRouteBuilder: <T>(settings, builder) => PixelRoute<T>(settings: settings, builder: builder),
        home: const PixelText('Start'),
      ));
      key.currentState!.push(PixelRoute<void>(builder: (_) => const PixelText('Zweite')));
      await tester.pumpAndSettle();
      expect(find.text('Zweite'), findsOneWidget);
    });
  });

  group('Kacheln', () {
    testWidgets('StatTile zeigt Wert und Beschriftung', (tester) async {
      await tester.pumpWidget(host(StatTile(glyph: PixelIcons.clock, value: '12 h', label: 'Druckzeit')));
      expect(find.text('12 h'), findsOneWidget);
      expect(find.text('Druckzeit'), findsOneWidget);
    });

    testWidgets('gesperrte Trophäe zeigt Fortschritt, freigeschaltete nicht', (tester) async {
      await tester.pumpWidget(host(Column(children: [
        TrophyBadge(glyph: PixelIcons.star, name: 'Fünferpack', description: '5 Drucke', unlocked: false, progress: 0.4, progressLabel: '2 / 5'),
        TrophyBadge(glyph: PixelIcons.star, name: 'Erster Druck', description: '1 Druck', unlocked: true),
      ])));
      expect(find.text('2 / 5'), findsOneWidget);
      expect(find.byType(PixelProgressBar), findsOneWidget);
    });
  });
}
