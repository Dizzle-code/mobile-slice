import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/ui/pixel_button.dart';
import 'package:mobile_slice/ui/pixel_search_field.dart';
import 'package:mobile_slice/ui/pixel_sheet.dart';
import 'package:mobile_slice/ui/pixel_stepper.dart';
import 'package:mobile_slice/ui/pixel_text.dart';

import 'ui_test.dart' show host;

void main() {
  group('PixelSearchField', () {
    testWidgets('Hinweis, Eingabe und Leeren', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(PixelSearchField(controller: controller, hint: 'Einstellung suchen')));
      expect(find.text('Einstellung suchen'), findsOneWidget);
      expect(find.bySemanticsLabel('Suche leeren'), findsNothing);

      await tester.enterText(find.byType(EditableText), 'füll');
      await tester.pump();
      expect(controller.text, 'füll');
      expect(find.text('Einstellung suchen'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Suche leeren'));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(find.text('Einstellung suchen'), findsOneWidget);
    });
  });

  group('PixelStepper', () {
    testWidgets('zählt in Schritten und bleibt in den Grenzen', (tester) async {
      var value = 0.2;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => PixelStepper(
          label: 'Abstand',
          value: value,
          min: 0,
          max: 0.3,
          step: 0.05,
          format: (v) => '${v.toStringAsFixed(2)} mm',
          onChanged: (v) => setState(() => value = v),
        ),
      )));
      expect(find.text('0.20 mm'), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Abstand erhöhen'));
      await tester.pump();
      expect(value, 0.25);
      await tester.tap(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Abstand erhöhen'));
      await tester.pump();
      expect(value, 0.3);
      final up = tester.widget<PixelIconButton>(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Abstand erhöhen'));
      expect(up.onPressed, isNull, reason: 'am Maximum gesperrt');
      await tester.tap(find.byWidgetPredicate((w) => w is PixelIconButton && w.label == 'Abstand verringern'));
      await tester.pump();
      expect(value, 0.25);
    });

    testWidgets('ohne onChanged gesperrt', (tester) async {
      await tester.pumpWidget(host(const PixelStepper(label: 'Wände', value: 2, min: 1, max: 10, step: 1, onChanged: null)));
      for (final button in tester.widgetList<PixelIconButton>(find.byType(PixelIconButton))) {
        expect(button.onPressed, isNull);
      }
    });
  });

  group('PixelSheet', () {
    testWidgets('öffnet von unten, liefert Ergebnis und schließt per X', (tester) async {
      await tester.pumpWidget(host(const SizedBox()));
      final context = tester.element(find.byType(SizedBox).last);
      final result = showPixelSheet<String>(
        context,
        title: 'Wände',
        builder: (context) => PixelButton(label: 'Übernehmen', onPressed: () => Navigator.of(context).pop('ok')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Wände'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(await result, 'ok');

      final closed = showPixelSheet<String>(context, title: 'Info', builder: (_) => const PixelText('Hilfe'));
      await tester.pumpAndSettle();
      expect(find.text('Hilfe'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Schließen').last);
      await tester.pumpAndSettle();
      expect(await closed, isNull);
      expect(find.text('Hilfe'), findsNothing);
    });
  });
}
