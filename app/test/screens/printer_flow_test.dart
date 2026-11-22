import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/app_services.dart';
import 'package:mobile_slice/engine/slicer_channel.dart';
import 'package:mobile_slice/main.dart';
import 'package:mobile_slice/model/stl_reader.dart';
import 'package:mobile_slice/preview/plate_viewer.dart';
import 'package:mobile_slice/printer/bambu_printer.dart';
import 'package:mobile_slice/printer/ftps_client.dart';
import 'package:mobile_slice/printer/printer_discovery.dart';
import 'package:mobile_slice/screens/printer_setup_screen.dart';
import 'package:mobile_slice/ui/pixel_route.dart';

import '../model/model_test.dart' show box;
import '../printer/fakes.dart';
import '../printer/printer_test.dart' show config, fullReport, push;
import '../support/fake_platform.dart';

class _Uploads implements FtpsClient {
  final files = <String, int>{};

  @override
  Future<void> upload(String remoteName, Uint8List data, {void Function(int sent, int total)? onProgress}) async {
    files[remoteName] = data.length;
    onProgress?.call(data.length, data.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakePlatform platform;
  late FakeBroker broker;
  late _Uploads uploads;

  setUp(() {
    platform = FakePlatform();
    broker = FakeBroker();
    uploads = _Uploads();
  });
  tearDown(() => platform.dispose());

  Future<AppServices> start(WidgetTester tester) async {
    platform.install();
    rootBundle.clear();
    final services = AppServices(
      slicer: SlicerChannel(),
      printerFactory: (config, onPins) => BambuPrinter(
        config: config,
        onPinsChanged: onPins,
        mqttConnector: (c, p) => broker.connect(),
        uploader: (c, p) => uploads,
      ),
    );
    await tester.pumpWidget(MobileSliceApp(services: services));
    await settle(tester, until: () => find.text('Werkstatt').evaluate().isNotEmpty);
    return services;
  }

  test('SSDP-Ankündigung des P1S wird erkannt', () {
    const notify = 'NOTIFY * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'Server: UPnP/1.0\r\n'
        'Location: 192.168.1.50\r\n'
        'NT: urn:bambulab-com:device:3dprinter:1\r\n'
        'USN: 01P00A000000001\r\n'
        'DevModel.bambu.com: C12\r\n'
        'DevName.bambu.com: Werkbank\r\n'
        'DevConnect.bambu.com: lan\r\n\r\n';
    final printer = parseSsdp(notify)!;
    expect(printer.ip, '192.168.1.50');
    expect(printer.serial, '01P00A000000001');
    expect(printer.modelName, 'P1S');
    expect(printer.name, 'Werkbank');
    expect(printer.lanMode, isTrue);
    expect(parseSsdp('NOTIFY * HTTP/1.1\r\nNT: upnp:rootdevice\r\nUSN: x\r\n'), isNull);
    expect(parseSsdp(notify.replaceFirst('Location: 192.168.1.50', 'Location: kaputt'), senderIp: null), isNull);
  });

  testWidgets('Einrichten per Suche, Live-Status, Pause', (tester) async {
    final services = await start(tester);
    await tester.tap(find.text('Drucker').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Noch kein Drucker'), findsOneWidget);

    // Open the setup with a fake discovery result.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator, skipOffstage: false).at(2));
    navigator.push(PixelRoute<void>(
      builder: (_) => PrinterSetupScreen(
        discovery: () => Stream.value(const DiscoveredPrinter(
          ip: '192.168.1.50',
          serial: '01P00A000000001',
          model: 'C12',
          name: 'Werkbank',
          lanMode: true,
        )),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drucker im WLAN suchen'));
    await settleFinder(tester, find.text('Werkbank · 192.168.1.50'));
    await tester.tap(find.text('Werkbank · 192.168.1.50'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).at(2), '12345678');
    await tester.scrollUntilVisible(
      find.text('Verbinden und speichern'),
      200,
      scrollable: find.descendant(of: find.byType(PrinterSetupScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Verbinden und speichern'));
    await settle(tester, until: () => services.printer.value?.online == true);
    await tester.pump(const Duration(seconds: 1));
    expect(File('${platform.appDir.path}/data/printer.json').existsSync(), isTrue);

    broker.report(fullReport());
    broker.report(push({'gcode_state': 'RUNNING', 'mc_percent': 37, 'layer_num': 88, 'total_layer_num': 240, 'subtask_name': 'benchy'}));
    await settleFinder(tester, find.text('37 %'));
    expect(find.text('Druckt'), findsOneWidget);
    expect(find.text('Schicht 88 / 240'), findsOneWidget);
    expect(find.text('Verbunden'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect((broker.requests.last['print'] as Map)['command'], 'pause');
    await services.printer.value!.disconnect();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Slicen und an den Drucker senden', (tester) async {
    final model = File('${platform.appDir.path}/cube.stl')..writeAsBytesSync(writeBinaryStl(box(0, 0, 0, 20, 20, 20)));
    platform.nextPick = {'path': model.path, 'name': 'cube.stl', 'bytes': model.lengthSync()};
    platform.onJob = (job) {
      final out = job['outputDir'] as String;
      if (job['type'] == 'preview') {
        final stl = File('$out/preview.stl')..writeAsBytesSync(writeBinaryStl(box(118, 118, 0, 138, 138, 20)));
        return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': true}};
      }
      final archive = File('$out/${job['baseName']}.gcode.3mf')..writeAsBytesSync(Uint8List(321));
      return {'ok': true, 'archivePath': archive.path, 'engine': {'printSeconds': 600.0, 'filamentGrams': 3.0, 'layers': 100}};
    };
    final services = await start(tester);
    await tester.runAsync(() => services.setPrinter(config()));
    await settle(tester, until: () => services.printer.value?.online == true);
    broker.report(fullReport());

    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(PlateViewer));
    await settle(tester, until: () => services.project.plate.objects.length == 1);
    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Fertig gesliced!'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('An P1S senden'));
    await settleFinder(tester, find.text('Druck gestartet!'));
    expect(uploads.files, {'cube.gcode.3mf': 321});
    final command = broker.requests.firstWhere((r) => (r['print'] as Map?)?['command'] == 'project_file')['print'] as Map;
    expect(command['subtask_name'], 'cube');

    // History: entry on send, closed by the printer's reports.
    expect(services.history.records.value.single.result.name, 'sent');
    broker.report(push({'gcode_state': 'RUNNING', 'subtask_name': 'cube'}));
    broker.report(push({'gcode_state': 'FINISH', 'subtask_name': 'cube'}));
    await settle(tester, until: () => services.history.records.value.single.result.name == 'finished');
    await settleFinder(tester, find.text('TROPHÄE FREIGESCHALTET!'));
    expect(find.text('Erster Druck'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await services.printer.value!.disconnect();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('abgelehnter Druckstart: Hinweis im Dialog und im Diagnose-Log', (tester) async {
    broker
      ..startResult = 'fail'
      ..startReason = 'mqtt message verify failed';
    final model = File('${platform.appDir.path}/cube.stl')..writeAsBytesSync(writeBinaryStl(box(0, 0, 0, 20, 20, 20)));
    platform.nextPick = {'path': model.path, 'name': 'cube.stl', 'bytes': model.lengthSync()};
    platform.onJob = (job) {
      final out = job['outputDir'] as String;
      if (job['type'] == 'preview') {
        final stl = File('$out/preview.stl')..writeAsBytesSync(writeBinaryStl(box(118, 118, 0, 138, 138, 20)));
        return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': true}};
      }
      final archive = File('$out/${job['baseName']}.gcode.3mf')..writeAsBytesSync(Uint8List(321));
      return {'ok': true, 'archivePath': archive.path, 'engine': {'printSeconds': 600.0, 'filamentGrams': 3.0, 'layers': 100}};
    };
    final services = await start(tester);
    await tester.runAsync(() => services.setPrinter(config()));
    await settle(tester, until: () => services.printer.value?.online == true);
    broker.report(fullReport());

    await tester.tap(find.text('Modell öffnen'));
    await settleFinder(tester, find.byType(PlateViewer));
    await settle(tester, until: () => services.project.plate.objects.length == 1);
    await tester.tap(find.text('Slicen'));
    await settleFinder(tester, find.text('Fertig gesliced!'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('An P1S senden'));
    await settleFinder(tester, find.text('Senden fehlgeschlagen'));
    expect(find.textContaining('Entwicklermodus'), findsOneWidget);
    final log = platform.calls.lastWhere((c) => c.method == 'appendLog').arguments as Map;
    expect(log['text'], contains('mqtt message verify failed'));
    expect(services.history.records.value, isEmpty);
    await services.printer.value!.disconnect();
    await tester.pump(const Duration(seconds: 3));
  });
}

