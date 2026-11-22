import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/engine/desktop_slicer.dart';
import 'package:mobile_slice/engine/slicer_channel.dart';

/// Engine process stand-in: the test writes output lines and decides the exit code.
class FakeProcess implements Process {
  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool killed = false;

  void line(String text) => _out.add(utf8.encode('$text\n'));

  void finish(int code) {
    if (_exit.isCompleted) return;
    _out.close();
    _err.close();
    _exit.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(1);
    return true;
  }

  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 42;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;
  late File exe;
  late List<String> startedArgs;
  late Map<String, String>? startedEnv;
  late FakeProcess process;
  late Completer<void> started;

  DesktopSlicer make({List<String> args = const [], String? savePath, String? pickPath}) => DesktopSlicer(
        args,
        appDir: appDir.path,
        engineExe: exe.path,
        assetVersion: 'v1',
        os: 'Windows 11',
        openDialog: () async => pickPath,
        saveDialog: (_) async => savePath,
        startProcess: (executable, arguments, {workingDirectory, environment}) async {
          startedArgs = arguments;
          startedEnv = environment;
          process = FakeProcess();
          started.complete();
          return process;
        },
      );

  String sep(String path) => path.replaceAll('/', Platform.pathSeparator);

  setUp(() {
    started = Completer<void>();
    appDir = Directory.systemTemp.createTempSync('desktop_slicer');
    exe = File('${appDir.path}${Platform.pathSeparator}slicer_cli.exe')..writeAsStringSync('x');
  });

  tearDown(() {
    try {
      appDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle.
    }
  });

  EngineJob sliceJob(DesktopSlicer slicer) => EngineJob(
        type: EngineJobType.slice,
        model: '${appDir.path}/models/a.stl',
        label: 'Würfel',
        outputDir: '${appDir.path}/jobs/1',
        baseName: 'wuerfel',
        process: 'process/0.12.json',
        overrides: const {'wall_loops': 3},
        modelId: 'm1',
      );

  test('prepare copies the engine assets once per version and reports the device', () async {
    final slicer = make();
    final info = await slicer.prepare();
    expect(info.engineInstalled, isTrue);
    expect(info.summary, 'Windows 11 · ${Platform.numberOfProcessors} Kerne');
    final printer = File(sep('${slicer.engineDir}/profiles/printer.json'));
    expect(printer.existsSync(), isTrue);
    expect(File(sep('${slicer.engineDir}/models/test_cube.stl')).existsSync(), isTrue);
    expect(File(sep('${slicer.engineDir}/.version')).readAsStringSync(), 'v1');

    printer.writeAsStringSync('changed');
    await slicer.prepare();
    expect(printer.readAsStringSync(), 'changed', reason: 'same version is not copied again');
  });

  test('run passes the Android arguments and reads @@ events', () async {
    final slicer = make();
    final job = sliceJob(slicer);
    final progress = <EngineProgress>[];
    final sub = slicer.progress.listen(progress.add);
    final future = slicer.run(job);
    await started.future;
    expect(slicer.busy, isTrue);

    final profiles = sep('${appDir.path}/engine/profiles');
    final out = sep('${appDir.path}/jobs/1');
    expect(startedArgs, [
      '--resources', sep('${appDir.path}/engine/resources'),
      '--printer', '$profiles${Platform.pathSeparator}printer.json',
      '--model', job.model,
      '--process', '$profiles${Platform.pathSeparator}process/0.12.json',
      '--filament', '$profiles${Platform.pathSeparator}filament/generic-pla.json',
      '--output', '${job.outputDir}${Platform.pathSeparator}plate_1.gcode',
      '--export-3mf', '${job.outputDir}${Platform.pathSeparator}wuerfel.gcode.3mf',
      '--model-id', 'm1',
      '--overrides', '{"wall_loops":3}',
    ]);
    expect(startedEnv!['TMPDIR'], sep('${appDir.path}/engine-tmp'));
    expect(Directory(out).existsSync(), isTrue);

    process
      ..line('engine log line')
      ..line('@@{"stage":"process"}')
      ..line('@@{"progress":40,"message":"Schichten"}')
      ..line('@@{"warning":"dünne Wand"}')
      ..line('@@{"result":{"printSeconds":600,"filamentGrams":3.5,"layers":100,"maxRssKb":2048}}')
      ..line('@@kaputt')
      ..finish(0);
    final result = await future;
    await sub.cancel();

    expect(result.ok, isTrue);
    expect(result.stage, 'process');
    expect(result.warnings, ['dünne Wand']);
    expect(result.printSeconds, 600);
    expect(result.layers, 100);
    expect(result.peakRssKb, 2048);
    expect(result.archivePath, endsWith('wuerfel.gcode.3mf'));
    expect(result.output, contains('engine log line'));
    expect(progress.map((p) => '${p.percent}:${p.message}'), ['-1:process', '40:Schichten']);
    expect(slicer.busy, isFalse);
    expect(slicer.logFile.readAsStringSync(), allOf(contains('===== slice'), contains('--- Engine-Ausgabe ---')));
  });

  test('a failed run reports the engine error and the crash cause', () async {
    final slicer = make();
    final future = slicer.run(EngineJob(type: EngineJobType.preview, model: 'm.stl', label: 'm', outputDir: '${appDir.path}/jobs/p'));
    await started.future;
    expect(startedArgs, containsAllInOrder(['--preview', '${appDir.path}/jobs/p${Platform.pathSeparator}preview.stl']));
    process
      ..line('@@{"error":"Modell leer"}')
      ..finish(0xC0000005 - 0x100000000);
    final result = await future;
    expect(result.ok, isFalse);
    expect(result.error, 'Modell leer');
    expect(result.signal, contains('Access Violation'));
    expect(result.previewPath, isNull);
  });

  test('cancel kills the process and reports Abgebrochen', () async {
    final slicer = make();
    final future = slicer.run(sliceJob(slicer));
    await started.future;
    expect(await slicer.cancel(), isTrue);
    final result = await future;
    expect(process.killed, isTrue);
    expect(result.cancelled, isTrue);
    expect(result.failure, 'Abgebrochen');
    expect(await slicer.cancel(), isFalse);
  });

  test('a second job while busy is refused', () async {
    final slicer = make();
    final first = slicer.run(sliceJob(slicer));
    await started.future;
    await expectLater(slicer.run(sliceJob(slicer)), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'busy')));
    process.finish(1);
    expect((await first).ok, isFalse);
  });

  test('profiles and outputs outside the app folder are refused', () async {
    final slicer = make();
    final outside = EngineJob(type: EngineJobType.slice, model: 'm', label: 'm', outputDir: '${appDir.path}/../elsewhere');
    final badProfile = EngineJob(
        type: EngineJobType.slice, model: 'm', label: 'm', outputDir: '${appDir.path}/jobs/x', process: '../../../secret.json');
    for (final job in [outside, badProfile]) {
      await expectLater(slicer.run(job), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'invalid')));
    }
    expect(slicer.busy, isFalse);
  });

  test('a missing engine fails without starting a process', () async {
    exe.deleteSync();
    final slicer = make();
    final result = await slicer.run(sliceJob(slicer));
    expect(result.ok, isFalse);
    expect(result.error, startsWith('Engine fehlt'));
  });

  test('a model from the start arguments is copied and taken once', () async {
    final source = File(sep('${appDir.path}/download/Boot.3mf'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final slicer = make(args: [source.path]);
    final launch = await slicer.takeLaunch();
    expect(launch!.model!.name, 'Boot.3mf');
    expect(launch.model!.bytes, 3);
    expect(launch.model!.path, startsWith(sep('${appDir.path}/models')));
    expect(await slicer.takeLaunch(), isNull);
  });

  test('sliced files and other types are rejected as models', () async {
    final gcode = File(sep('${appDir.path}/x.gcode.3mf'))..writeAsStringSync('g');
    final launch = await make(args: [gcode.path]).takeLaunch();
    expect(launch!.error, contains('.stl- oder .3mf'));
    final text = File(sep('${appDir.path}/x.txt'))..writeAsStringSync('t');
    await expectLater(make(pickPath: text.path).pickModel(), throwsA(isA<PlatformException>()));
    expect(await make().pickModel(), isNull);
  });

  test('shareFile saves a copy of an app file where the user chose', () async {
    final target = sep('${appDir.path}/../saved_${DateTime.now().microsecondsSinceEpoch}.gcode.3mf');
    final slicer = make(savePath: target);
    final archive = File(sep('${appDir.path}/jobs/1/a.gcode.3mf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('data');
    await slicer.shareFile(archive.path);
    expect(File(target).readAsStringSync(), 'data');
    File(target).deleteSync();

    final foreign = File(target)..writeAsStringSync('x');
    await expectLater(slicer.shareFile(foreign.path), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'invalid')));
    foreign.deleteSync();
    await expectLater(slicer.shareLog(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'empty')));
    await slicer.appendLog('Drucker', 'verbunden');
    expect(slicer.logFile.readAsStringSync(), contains('===== Drucker'));
  });

  test('openUrl only accepts https', () async {
    await expectLater(make().openUrl('file:///c:/windows'), throwsA(isA<PlatformException>()));
  });

  test('desktop flag switches the labels', () {
    expect(make().desktop, isTrue);
    expect(SlicerChannel().desktop, isFalse);
  });

  final realExe = File(Platform.isWindows ? 'windows/engine/slicer_cli.exe' : 'macos/engine/slicer_cli');
  test('the real engine slices the test cube', () async {
    final slicer = DesktopSlicer(const [], appDir: appDir.path, engineExe: realExe.absolute.path, assetVersion: 'real');
    final info = await slicer.prepare();
    expect(info.engineInstalled, isTrue);
    final cube = '${slicer.engineDir}${Platform.pathSeparator}models${Platform.pathSeparator}test_cube.stl';
    final result = await slicer.run(EngineJob(
      type: EngineJobType.slice,
      model: cube,
      label: 'Testwürfel',
      outputDir: '${appDir.path}${Platform.pathSeparator}jobs${Platform.pathSeparator}real',
      baseName: 'wuerfel',
    ));
    expect(result.ok, isTrue, reason: '${result.failure}\n${result.output}');
    expect(result.layers, 100);
    expect(result.filamentGrams, greaterThan(1));
    expect(File(result.archivePath!).lengthSync(), greaterThan(1000));
  }, skip: realExe.existsSync() ? false : 'slicer_cli fehlt (engine/build-windows.ps1 bzw. build-macos.sh)');
}
