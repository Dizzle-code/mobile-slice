import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/engine/slicer_channel.dart';
import 'package:mobile_slice/util/format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/slicer');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> fromPlatform(String method, Map<String, Object?> args) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Slice-Auftrag übergibt Overrides als JSON und liefert das Ergebnis', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final slicer = SlicerChannel(channel: channel);
    final job = EngineJob(
      type: EngineJobType.slice,
      model: '/m/benchy.stl',
      label: 'benchy.stl',
      outputDir: '/files/jobs/1',
      baseName: 'benchy',
      process: 'process/0.20.json',
      filament: 'filament/generic-pla.json',
      overrides: {'sparse_infill_density': '20%', 'enable_support': true},
      modelId: 'C12',
      scale: 1.5,
    );
    final progress = <EngineProgress>[];
    final sub = slicer.progress.listen(progress.add);
    final future = slicer.run(job);
    await Future<void>.delayed(Duration.zero);
    final args = calls.single.arguments as Map;
    expect(calls.single.method, 'runJob');
    expect(args['type'], 'slice');
    expect(args['scale'], 1.5);
    expect(jsonDecode(args['overrides'] as String), {'sparse_infill_density': '20%', 'enable_support': true});
    expect(slicer.busy, isTrue);

    await fromPlatform('progress', {'jobId': job.id, 'percent': 40, 'message': 'Generating perimeters'});
    await fromPlatform('progress', {'jobId': job.id, 'percent': -1, 'message': 'export'});
    await fromPlatform('finished', {
      'jobId': job.id,
      'ok': true,
      'archivePath': '/files/jobs/1/benchy.gcode.3mf',
      'engine': {'printSeconds': 3725.4, 'filamentGrams': 14.2, 'layers': 240, 'supportUsed': false},
    });
    final result = await future;
    await sub.cancel();
    expect(result.ok, isTrue);
    expect(result.archivePath, '/files/jobs/1/benchy.gcode.3mf');
    expect(result.printSeconds, 3725);
    expect(result.layers, 240);
    expect(progress.first.percent, 40);
    expect(progress.last.isStage, isTrue);
    expect(slicer.busy, isFalse);
  });

  test('Fehler und Abbruch ergeben verständliche Texte', () {
    expect(EngineResult.fromMap({'ok': false, 'cancelled': true, 'error': 'Abgebrochen'}).failure, 'Abgebrochen');
    expect(
      EngineResult.fromMap({'ok': false, 'error': 'Engine beendet mit Exit-Code 137', 'signal': 'SIGKILL'}).failure,
      'Engine beendet mit Exit-Code 137 (SIGKILL)',
    );
    final empty = EngineResult.fromMap({});
    expect(empty.ok, isFalse);
    expect(empty.printSeconds, 0);
    expect(empty.fits, isTrue);
  });

  test('Plattformfehler beim Start räumt den Auftrag auf', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'busy'));
    final slicer = SlicerChannel(channel: channel);
    await expectLater(
      slicer.run(EngineJob(type: EngineJobType.preview, model: 'a', label: 'a', outputDir: 'b')),
      throwsA(isA<PlatformException>()),
    );
    expect(slicer.busy, isFalse);
  });

  test('Phasen haben deutsche Namen', () {
    expect(stageLabel('process'), 'Schichten berechnen');
    expect(stageLabel('unbekannt'), 'unbekannt');
  });

  group('Format', () {
    test('Dauer', () {
      expect(formatDuration(850), '850 ms');
      expect(formatDuration(12345), '12,3 s');
      expect(formatDuration(83400), '1 min 23 s');
    });

    test('Druckzeit', () {
      expect(formatPrintTime(30), '< 1 min');
      expect(formatPrintTime(45 * 60), '45 min');
      expect(formatPrintTime(2 * 3600 + 5 * 60), '2 h 05 min');
      expect(formatPrintTime(76 * 3600), '3 T 4 h');
    });

    test('Gewicht und Speicher', () {
      expect(formatGrams(12.44), '12,4 g');
      expect(formatGrams(1250), '1,25 kg');
      expect(formatKb(1536 * 1024), '1,50 GB');
      expect(formatBytes(900), '900 B');
    });
  });
}
