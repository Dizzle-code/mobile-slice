import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/data/home_widgets.dart';
import 'package:mobile_slice/data/print_history.dart';
import 'package:mobile_slice/printer/bambu_printer.dart';
import 'package:mobile_slice/printer/printer_config.dart';
import 'package:mobile_slice/printer/printer_status.dart';
import 'package:mobile_slice/trophies/trophy_catalog.dart';

PrintRecord record(String id, {PrintResult result = PrintResult.finished, double grams = 100, int seconds = 3600}) => PrintRecord(
      id: id,
      modelName: '$id.stl',
      subtaskName: id,
      sentAt: DateTime(2026, 11, 20, 12),
      result: result,
      printSeconds: seconds,
      grams: grams,
      filamentType: 'PLA',
      filamentLabel: 'Generic PLA',
      layerHeight: 0.2,
      processLabel: 'Standard',
    );

PrinterStatus printing({int percent = 42, int minutes = 65}) => const PrinterStatus().merge({
      'print': {
        'gcode_state': 'RUNNING',
        'subtask_name': 'Benchy',
        'mc_percent': percent,
        'mc_remaining_time': minutes,
        'nozzle_temper': 219.6,
        'bed_temper': 60.2,
      },
    });

Map<String, String> data({
  String? name = 'P1S',
  PrinterLink? link = const PrinterLink(LinkState.online),
  PrinterStatus status = const PrinterStatus(),
  List<PrintRecord> records = const [],
  Set<String> unlocked = const {},
}) =>
    homeWidgetData(
      printerName: name,
      link: link,
      status: status,
      records: records,
      unlocked: unlocked,
      catalog: trophyCatalog,
      now: DateTime(2026, 11, 21, 14, 35),
    );

void main() {
  group('Widget-Texte', () {
    test('ohne Drucker', () {
      final d = data(name: null, link: null);
      expect(d['p_state'], 'Nicht eingerichtet');
      expect(d['p_percent'], '');
      expect(d['p_updated'], '');
    });

    test('nicht verbunden zeigt keinen alten Auftrag', () {
      final d = data(link: const PrinterLink(LinkState.error, 'weg'), status: printing());
      expect(d['p_state'], 'Nicht verbunden');
      expect(d['p_state_color'], 'red');
      expect(d['p_job'], '');
    });

    test('Druck läuft: Fortschritt, Restzeit, Fertig-Uhrzeit, Temperaturen, Stand', () {
      final d = data(status: printing());
      expect(d['p_state'], 'Druckt');
      expect(d['p_state_color'], 'accent');
      expect(d['p_job'], 'Benchy');
      expect(d['p_percent'], '42');
      expect(d['p_line'], '42 % · noch 1 h 05 min · fertig ~15:40');
      expect(d['p_temps'], 'Düse 220° · Bett 60°');
      expect(d['p_updated'], 'Stand 14:35');
    });

    test('fertig und bereit', () {
      final done = data(status: const PrinterStatus().merge({'print': {'gcode_state': 'FINISH', 'subtask_name': 'Benchy'}}));
      expect(done['p_state'], 'Fertig');
      expect(done['p_state_color'], 'green');
      expect(done['p_percent'], '', reason: 'kein Balken nach dem Druck');
      expect(done['p_job'], 'Benchy');
      final idle = data(status: const PrinterStatus().merge({'print': {'gcode_state': 'IDLE'}}));
      expect(idle['p_job'], '');
      expect(idle['p_line'], 'Bereit für den nächsten Druck');
    });

    test('Werkstatt: Summen, Trophäen und die nächste erreichbare Trophäe', () {
      final records = [record('a'), record('b'), record('c', result: PrintResult.failed)];
      final d = data(records: records, unlocked: {'first_print'});
      expect(d['w_prints'], '2');
      expect(d['w_grams'], '200,0 g');
      expect(d['w_hours'], '2 h');
      expect(d['w_trophies'], 'Trophäen 1 / 14');
      expect(d['w_next'], 'Nächste: Fünferpack · 2 / 5');
    });

    test('alle Trophäen', () {
      final d = data(unlocked: {for (final t in trophyCatalog) t.id});
      expect(d['w_next'], 'Alle Trophäen geschafft!');
      expect(d['w_trophies'], 'Trophäen 14 / 14');
    });
  });

  group('Abgleich', () {
    late List<Map<String, String>> sent;
    late DateTime now;
    late ValueNotifier<BambuPrinter?> printer;
    late ValueNotifier<List<PrintRecord>> history;
    late ValueNotifier<Map<String, DateTime>> unlocked;
    late HomeWidgetSync sync;

    setUp(() {
      sent = [];
      now = DateTime(2026, 11, 21, 14);
      printer = ValueNotifier(null);
      history = ValueNotifier(const []);
      unlocked = ValueNotifier(const {});
      sync = HomeWidgetSync(
        send: (d) async => sent.add(d),
        printer: printer,
        history: history,
        unlocked: unlocked,
        catalog: trophyCatalog,
        clock: () => now,
      )..start();
    });
    tearDown(() => sync.dispose());

    test('sendet sofort, Doppeltes nie, Kleinkram gedrosselt, Wichtiges sofort', () {
      expect(sent, hasLength(1));
      expect(sent.last['p_state'], 'Nicht eingerichtet');
      sync.update();
      expect(sent, hasLength(1), reason: 'unverändert');

      final p1s = BambuPrinter(config: const PrinterConfig(ip: '1.2.3.4', serial: 's', accessCode: 'a'));
      printer.value = p1s;
      p1s.link.value = const PrinterLink(LinkState.online);
      p1s.status.value = printing();
      expect(sent.last['p_percent'], '42');
      final count = sent.length;

      // Only the temperature moves: waits for the quiet interval.
      now = now.add(const Duration(seconds: 5));
      p1s.status.value = p1s.status.value.merge({'print': {'nozzle_temper': 215}});
      expect(sent, hasLength(count));
      now = now.add(const Duration(minutes: 1));
      sync.update();
      expect(sent, hasLength(count + 1));
      expect(sent.last['p_temps'], startsWith('Düse 215°'));

      // Progress counts as important.
      now = now.add(const Duration(seconds: 5));
      p1s.status.value = p1s.status.value.merge({'print': {'mc_percent': 43}});
      expect(sent, hasLength(count + 2));
      expect(sent.last['p_line'], startsWith('43 %'));

      history.value = [record('a')];
      expect(sent.last['w_prints'], '1');
      p1s.dispose();
    });
  });
}
