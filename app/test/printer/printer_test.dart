import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/printer/bambu_printer.dart';
import 'package:mobile_slice/printer/connection.dart';
import 'package:mobile_slice/printer/ftps_client.dart';
import 'package:mobile_slice/printer/mqtt_client.dart';
import 'package:mobile_slice/printer/printer_config.dart';
import 'package:mobile_slice/printer/printer_status.dart';
import 'package:mobile_slice/util/sha256.dart';

import 'fakes.dart';

/// Recorded-style P1S reports: one full "pushall" answer, then partial pushes.
Map<String, Object?> fullReport() => {
  'print': {
    'command': 'push_status',
    'msg': 0,
    'sequence_id': '20',
    'gcode_state': 'IDLE',
    'mc_percent': 0,
    'mc_remaining_time': 0,
    'layer_num': 0,
    'total_layer_num': 0,
    'nozzle_temper': 25.9,
    'nozzle_target_temper': 0,
    'bed_temper': 23.1,
    'bed_target_temper': 0,
    'chamber_temper': 5,
    'subtask_name': '',
    'print_error': 0,
    'wifi_signal': '-42dBm',
    'sdcard': true,
    'stg_cur': 255,
    'spd_lvl': 2,
    'lights_report': [
      {'node': 'chamber_light', 'mode': 'on'},
    ],
    'upgrade_state': {'status': 'UPGRADE_SUCCESS', 'progress': '100'},
  },
};

Map<String, Object?> push(Map<String, Object?> fields) => {
  'print': {'command': 'push_status', 'msg': 1, 'sequence_id': '21', ...fields},
};

PrinterConfig config() => const PrinterConfig(ip: '192.168.1.50', serial: '01P00A000000001', accessCode: '12345678');

void main() {
  group('SHA-256', () {
    test('Prüfvektoren', () {
      expect(hex(sha256(const [])), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(hex(sha256(utf8.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
        hex(sha256(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      expect(
        hex(sha256(List.filled(1000000, 0x61))),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });

  group('Zertifikats-Pinning', () {
    test('erstes Zertifikat wird gemerkt, danach nur noch dieses', () {
      Map<String, String>? saved;
      final pins = CertificatePins({}, (p) => saved = p);
      expect(pins.check('192.168.1.50:8883', 'aa'), isTrue);
      expect(saved, {'192.168.1.50:8883': 'aa'});
      expect(pins.check('192.168.1.50:8883', 'aa'), isTrue);
      expect(pins.accepts('192.168.1.50:8883', 'bb'), isFalse);
      expect(pins.check('192.168.1.50:8883', 'bb'), isFalse);
      // Other address: its own first use.
      expect(pins.check('192.168.1.51:8883', 'bb'), isTrue);
      pins.clear();
      expect(saved, isEmpty);
    });

    test('neue IP vergisst die alten Zertifikate', () {
      final c = config().copyWith(pins: {'192.168.1.50:8883': 'aa'});
      expect(c.copyWith(accessCode: 'x').pins, isNotEmpty);
      expect(c.copyWith(ip: '192.168.1.60').pins, isEmpty);
    });
  });

  group('MQTT-Kodierung', () {
    test('Restlänge', () {
      expect(MqttCodec.remainingLength(0), [0]);
      expect(MqttCodec.remainingLength(127), [0x7F]);
      expect(MqttCodec.remainingLength(128), [0x80, 0x01]);
      expect(MqttCodec.remainingLength(16383), [0xFF, 0x7F]);
      expect(MqttCodec.remainingLength(16384), [0x80, 0x80, 0x01]);
      expect(MqttCodec.remainingLength(2097152), [0x80, 0x80, 0x80, 0x01]);
    });

    test('CONNECT mit Benutzer und Passwort', () {
      final packet = MqttCodec.encodeConnect(clientId: 'c', username: 'bblp', password: 'pw', keepAliveSeconds: 30);
      expect(packet, [
        0x10, 23, //
        0, 4, ...ascii.encode('MQTT'), 4, 0xC2, 0, 30,
        0, 1, ...ascii.encode('c'),
        0, 4, ...ascii.encode('bblp'),
        0, 2, ...ascii.encode('pw'),
      ]);
    });

    test('SUBSCRIBE und PUBLISH', () {
      expect(MqttCodec.encodeSubscribe(1, 'a/b'), [0x82, 8, 0, 1, 0, 3, ...ascii.encode('a/b'), 0]);
      expect(MqttCodec.encodePublish('t', ascii.encode('{}')), [
        0x30,
        5,
        0,
        1,
        ...ascii.encode('t'),
        ...ascii.encode('{}'),
      ]);
    });

    test('Leser setzt zerstückelte und zusammenhängende Pakete richtig zusammen', () {
      final big = MqttCodec.encodePublish('device/x/report', List.filled(20000, 0x41));
      final both = [...big, 0xD0, 0x00];
      final reader = MqttPacketReader();
      final packets = <MqttPacket>[];
      for (var i = 0; i < both.length; i += 333) {
        packets.addAll(reader.add(both.sublist(i, i + 333 > both.length ? both.length : i + 333)));
      }
      expect(packets.map((p) => p.type), [MqttCodec.publish, MqttCodec.pingresp]);
      expect(packets.first.body.length, 2 + 15 + 20000);
    });
  });

  group('MQTT-Client', () {
    test('verbindet, abonniert und empfängt Nachrichten (auch QoS 1)', () async {
      final broker = FakeBroker();
      final client = MqttClient(connector: broker.connect, clientId: 'x', username: 'bblp', password: '12345678');
      await client.connect();
      await client.subscribe('device/01P00A000000001/report');
      final received = client.messages.first;
      // QoS 1 publish: header 0x32 and a packet id before the payload.
      final topic = ascii.encode('device/01P00A000000001/report');
      broker.current!.reply([0x32, 2 + topic.length + 2 + 2, 0, topic.length, ...topic, 0, 7, ...ascii.encode('{}')]);
      final message = await received;
      expect(message.text, '{}');
      await client.disconnect();
      expect(await client.done, isNull);
      expect(broker.current!.written.sublist(broker.current!.written.length - 2), [0xE0, 0]);
    });

    test('falscher Zugangscode ergibt verständlichen Fehler', () async {
      final broker = FakeBroker();
      final client = MqttClient(connector: broker.connect, clientId: 'x', username: 'bblp', password: 'falsch');
      await expectLater(
        client.connect(),
        throwsA(isA<MqttException>().having((e) => e.message, 'message', contains('Zugangscode'))),
      );
    });

    testWidgets('Keepalive sendet PINGREQ', (tester) async {
      final broker = FakeBroker();
      final client = MqttClient(connector: broker.connect, clientId: 'x', username: 'bblp', password: '12345678', keepAlive: const Duration(seconds: 5));
      await client.connect();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(broker.current!.written.contains(0xC0), isTrue);
      client.disconnect();
      await tester.pump();
    });

    test('Abbruch durch den Drucker beendet done mit Fehler', () async {
      final broker = FakeBroker();
      final client = MqttClient(connector: broker.connect, clientId: 'x', password: '12345678', username: 'bblp');
      await client.connect();
      broker.current!.hangUp();
      expect(await client.done, isA<MqttException>());
      expect(client.isConnected, isFalse);
    });
  });

  group('FTPS', () {
    /// Scripted control server; records commands and answers like the printer.
    ({FakeConnection control, List<String> commands, FakeConnection data}) server({
      bool requireReuse = false,
      bool wrongCode = false,
    }) {
      final commands = <String>[];
      final data = FakeConnection();
      var protP = true;
      final buffer = StringBuffer();
      final control = FakeConnection(
        onWrite: (c, bytes) {
          buffer.write(latin1.decode(bytes));
          while (buffer.toString().contains('\r\n')) {
            final all = buffer.toString();
            final line = all.substring(0, all.indexOf('\r\n'));
            buffer
              ..clear()
              ..write(all.substring(all.indexOf('\r\n') + 2));
            commands.add(line);
            final reply = switch (line.split(' ').first) {
              'USER' => '331 Password required\r\n',
              'PASS' => wrongCode ? '530 Login incorrect.\r\n' : '230 User logged in\r\n',
              'TYPE' => '200 Switching to Binary mode.\r\n',
              'PBSZ' => '200 PBSZ set to 0.\r\n',
              'PROT' => () {
                protP = line == 'PROT P';
                return '200 PROT now ${protP ? 'Private' : 'Clear'}.\r\n';
              }(),
              'PASV' => '227 Entering Passive Mode (10,0,0,9,7,233).\r\n',
              'STOR' =>
                requireReuse && protP
                    ? '150 Ok to send data.\r\n522 SSL connection failed: session reuse required\r\n'
                    : '150 Ok to send data.\r\n',
              'QUIT' => '221 Goodbye.\r\n',
              _ => '500 Unknown\r\n',
            };
            scheduleMicrotask(() => c.replyText(reply));
          }
        },
      );
      scheduleMicrotask(() => control.replyText('220-Bambu FTP\r\n220 ready\r\n'));
      return (control: control, commands: commands, data: data);
    }

    test('Ablauf: Anmelden, PASV, STOR, Daten, QUIT', () async {
      final s = server();
      final ports = <int>[];
      var secured = 0;
      final client = FtpsClient(
        controlConnector: () async => s.control,
        dataConnector: (port) async {
          ports.add(port);
          return _confirmOnClose(s.data, s.control);
        },
        secureData: (raw) async {
          secured++;
          return raw;
        },
        username: 'bblp',
        password: '12345678',
      );
      final payload = Uint8List.fromList(List.generate(200000, (i) => i % 251));
      final progress = <double>[];
      await client.upload('benchy.gcode.3mf', payload, onProgress: (sent, total) => progress.add(sent / total));
      expect(s.commands, [
        'USER bblp',
        'PASS 12345678',
        'TYPE I',
        'PBSZ 0',
        'PROT P',
        'PASV',
        'STOR benchy.gcode.3mf',
        'QUIT',
      ]);
      expect(ports, [7 * 256 + 233]);
      expect(secured, 1);
      expect(s.data.written, payload);
      expect(progress.last, 1);
    });

    test('verlangt der Server TLS-Wiederverwendung (522), geht es unverschlüsselt weiter', () async {
      final s = server(requireReuse: true);
      final client = FtpsClient(
        controlConnector: () async => s.control,
        dataConnector: (port) async => _confirmOnClose(FakeConnection(), s.control, record: s.data),
        secureData: (raw) async => throw const HandshakeException('reuse'),
        username: 'bblp',
        password: '12345678',
      );
      await client.upload('a.gcode.3mf', Uint8List.fromList([1, 2, 3]));
      expect(
        s.commands,
        containsAllInOrder(['PROT P', 'PASV', 'STOR a.gcode.3mf', 'PROT C', 'PASV', 'STOR a.gcode.3mf', 'QUIT']),
      );
      expect(s.data.written, [1, 2, 3]);
    });

    test('falscher Zugangscode', () async {
      final s = server(wrongCode: true);
      final client = FtpsClient(
        controlConnector: () async => s.control,
        dataConnector: (port) async => s.data,
        secureData: (raw) async => raw,
        username: 'bblp',
        password: 'x',
      );
      await expectLater(
        client.upload('a.gcode.3mf', Uint8List(1)),
        throwsA(isA<FtpException>().having((e) => e.code, 'code', 530)),
      );
    });

    test('PASV-Port und Dateinamen-Prüfung', () {
      expect(FtpsClient.parsePasvPort('Entering Passive Mode (192,168,1,50,195,80).'), 195 * 256 + 80);
      expect(() => FtpsClient.parsePasvPort('kaputt'), throwsA(isA<FtpException>()));
      final client = FtpsClient(
        controlConnector: () async => FakeConnection(),
        dataConnector: (port) async => FakeConnection(),
        secureData: (raw) async => raw,
        username: 'u',
        password: 'p',
      );
      expect(client.upload('../x', Uint8List(1)), throwsA(isA<FtpException>()));
    });
  });

  group('Status-Zusammenführung', () {
    test('Teil-Updates ergänzen den vollen Bericht', () {
      var status = const PrinterStatus().merge(fullReport());
      expect(status.state, PrintState.idle);
      expect(status.nozzle, closeTo(25.9, 1e-9));
      expect(status.hasSdCard, isTrue);

      status = status.merge(
        push({'gcode_state': 'PREPARE', 'stg_cur': 2, 'subtask_name': 'benchy', 'bed_target_temper': 55}),
      );
      expect(status.state, PrintState.preparing);
      expect(status.stageLabel, 'Heizbett wärmt vor');
      expect(status.nozzle, closeTo(25.9, 1e-9), reason: 'nicht gesendete Felder bleiben');

      status = status.merge(
        push({
          'gcode_state': 'RUNNING',
          'mc_percent': 37,
          'mc_remaining_time': 41,
          'layer_num': 88,
          'total_layer_num': 240,
        }),
      );
      expect(status.state, PrintState.printing);
      expect(status.percent, 37);
      expect(status.layer, 88);
      expect(status.bedTarget, 55);
      expect(status.subtaskName, 'benchy');

      status = status.merge(
        push({
          'upgrade_state': {'progress': '0'},
        }),
      );
      expect((status.raw['upgrade_state'] as Map)['status'], 'UPGRADE_SUCCESS', reason: 'verschachtelt zusammenführen');

      status = status.merge(push({'gcode_state': 'FINISH', 'mc_percent': 100}));
      expect(status.state, PrintState.finished);
      expect(status.state.busy, isFalse);
    });

    test('Fremde Nachrichten und Zahlen als Text', () {
      final status = const PrinterStatus().merge({
        'info': {'command': 'get_version'},
      });
      expect(status.isEmpty, isTrue);
      expect(const PrinterStatus().merge(push({'mc_percent': '42', 'gcode_state': 'pause'})).percent, 42);
      expect(PrintState.parse('pause'), PrintState.paused);
      expect(PrintState.parse(null), PrintState.unknown);
    });
  });

  group('BambuPrinter', () {
    test('verbindet, holt vollen Status und folgt Updates', () async {
      final broker = FakeBroker();
      final printer = BambuPrinter(config: config(), mqttConnector: (c, p) => broker.connect());
      await printer.connect();
      expect(printer.link.value.state, LinkState.online);
      expect((broker.requests.single['pushing'] as Map)['command'], 'pushall');
      final next = printer.reports.first;
      broker.report(fullReport());
      await next;
      expect(printer.status.value.state, PrintState.idle);
      broker.report(push({'gcode_state': 'RUNNING', 'mc_percent': 5}));
      await printer.reports.first;
      expect(printer.status.value.percent, 5);
      printer.pause();
      printer.resume();
      printer.stop();
      expect(broker.requests.skip(1).map((r) => (r['print'] as Map)['command']), ['pause', 'resume', 'stop']);
      await printer.disconnect();
      expect(printer.link.value.state, LinkState.off);
    });

    test('Senden lädt hoch und startet den Druck von der SD-Karte', () async {
      final broker = FakeBroker();
      final uploads = <String, int>{};
      final printer = BambuPrinter(
        config: config(),
        mqttConnector: (c, p) => broker.connect(),
        uploader: (c, p) => _RecordingUploader(uploads),
      );
      await printer.connect();
      broker.report(fullReport());
      await printer.reports.first;
      final file = File('${Directory.systemTemp.createTempSync().path}/benchy.gcode.3mf')
        ..writeAsBytesSync(List.filled(1234, 1));
      final progress = <double>[];
      await printer.sendAndPrint(file, 'benchy.gcode.3mf', 'benchy', onProgress: progress.add);
      expect(uploads, {'benchy.gcode.3mf': 1234});
      expect(progress.last, 1);
      final start =
          broker.requests.firstWhere((r) => (r['print'] as Map?)?['command'] == 'project_file')['print'] as Map;
      expect(start['url'], 'file:///sdcard/benchy.gcode.3mf');
      expect(start['param'], 'Metadata/plate_1.gcode');
      expect(start['subtask_name'], 'benchy');
      expect(start['use_ams'], false);
      await printer.disconnect();
    });

    test('Senden während eines Drucks wird abgelehnt', () async {
      final broker = FakeBroker();
      final printer = BambuPrinter(config: config(), mqttConnector: (c, p) => broker.connect());
      await expectLater(printer.sendAndPrint(File('x'), 'a', 'a'), throwsA(isA<PrinterException>()));
      await printer.connect();
      broker.report(push({'gcode_state': 'RUNNING'}));
      await printer.reports.first;
      await expectLater(
        printer.sendAndPrint(File('x'), 'a', 'a'),
        throwsA(isA<PrinterException>().having((e) => e.message, 'message', contains('beschäftigt'))),
      );
      await printer.disconnect();
    });

    Future<BambuPrinter> readyPrinter(FakeBroker broker) async {
      final printer = BambuPrinter(
        config: config(),
        mqttConnector: (c, p) => broker.connect(),
        uploader: (c, p) => _RecordingUploader({}),
        startTimeout: const Duration(milliseconds: 200),
      );
      await printer.connect();
      broker.report(fullReport());
      await printer.reports.first;
      return printer;
    }

    File archive() => File('${Directory.systemTemp.createTempSync().path}/a.gcode.3mf')..writeAsBytesSync([1, 2, 3]);

    test('abgelehnter Druckstart wird gemeldet, mit Hinweis auf den Entwicklermodus', () async {
      final broker = FakeBroker()
        ..startResult = 'fail'
        ..startReason = 'mqtt message verify failed';
      final printer = await readyPrinter(broker);
      await expectLater(
        printer.sendAndPrint(archive(), 'a.gcode.3mf', 'a'),
        throwsA(isA<PrinterException>()
            .having((e) => e.message, 'message', allOf(contains('abgelehnt'), contains('mqtt message verify failed'), contains('Entwicklermodus')))
            .having((e) => e.details, 'details', contains('"result":"fail"'))),
      );
      await printer.disconnect();
    });

    test('keine Antwort auf den Druckstart wird gemeldet', () async {
      final broker = FakeBroker()..startResult = null;
      final printer = await readyPrinter(broker);
      await expectLater(
        printer.sendAndPrint(archive(), 'a.gcode.3mf', 'a'),
        throwsA(isA<PrinterException>().having((e) => e.message, 'message', contains('nicht reagiert'))),
      );
      await printer.disconnect();
    });

    test('ohne Antwort, aber mit startendem Druck gilt der Start als erfolgreich', () async {
      final broker = FakeBroker()..startResult = null;
      final printer = await readyPrinter(broker);
      final sending = printer.sendAndPrint(archive(), 'a.gcode.3mf', 'a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      broker.report(push({'gcode_state': 'PREPARE'}));
      await sending;
      await printer.disconnect();
    });

    testWidgets('verbindet nach Abbruch neu, aber nicht bei falschem Code', (tester) async {
      final broker = FakeBroker();
      final printer = BambuPrinter(
        config: config(),
        mqttConnector: (c, p) => broker.connect(),
        reconnectDelays: const [Duration(seconds: 1)],
      );
      printer.connect();
      await tester.pump();
      expect(printer.online, isTrue);
      broker.current!.hangUp();
      await tester.pump();
      expect(printer.link.value.state, LinkState.error);
      await tester.pump(const Duration(seconds: 2));
      expect(printer.online, isTrue);
      expect(broker.connections, hasLength(2));
      printer.disconnect();
      await tester.pump();

      final wrong = BambuPrinter(
        config: config().copyWith(accessCode: 'falsch00'),
        mqttConnector: (c, p) => broker.connect(),
        reconnectDelays: const [Duration(seconds: 1)],
      );
      wrong.connect();
      await tester.pump();
      expect(wrong.link.value.message, contains('Zugangscode'));
      await tester.pump(const Duration(seconds: 5));
      expect(broker.connections, hasLength(3));
    });
  });

  group('Konfiguration', () {
    test('Eingaben prüfen', () {
      expect(PrinterConfig.validateIp('192.168.1.50'), isNull);
      expect(PrinterConfig.validateIp('192.168.1'), isNotNull);
      expect(PrinterConfig.validateIp('300.1.1.1'), isNotNull);
      expect(PrinterConfig.validateSerial('01P00A000000001'), isNull);
      expect(PrinterConfig.validateSerial('abc'), isNotNull);
      expect(PrinterConfig.validateAccessCode('12345678'), isNull);
      expect(PrinterConfig.validateAccessCode('12 34'), isNotNull);
      expect(config().isValid, isTrue);
    });

    test('JSON hin und zurück', () {
      final c = config().copyWith(pins: {'a': 'b'}, name: 'Werkbank');
      final back = PrinterConfig.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
      expect(back.toJson(), c.toJson());
    });
  });
}

FakeConnection _confirmOnClose(FakeConnection data, FakeConnection control, {FakeConnection? record}) {
  final target = record ?? data;
  return _CloseHook(target, () => scheduleMicrotask(() => control.replyText('226 Transfer complete.\r\n')));
}

class _CloseHook extends FakeConnection {
  _CloseHook(this.target, this.onClose);

  final FakeConnection target;
  final void Function() onClose;

  @override
  void add(List<int> bytes) => target.add(bytes);

  @override
  Future<void> close() async {
    onClose();
  }
}

class _RecordingUploader implements FtpsClient {
  _RecordingUploader(this.uploads);

  final Map<String, int> uploads;

  @override
  Future<void> upload(String remoteName, Uint8List data, {void Function(int sent, int total)? onProgress}) async {
    uploads[remoteName] = data.length;
    onProgress?.call(data.length, data.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
