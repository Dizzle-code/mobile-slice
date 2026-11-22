import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'slicer_channel.dart';

typedef ProcessStarter = Future<Process> Function(String executable, List<String> arguments,
    {String? workingDirectory, Map<String, String>? environment});

/// Returns the chosen file path, or null when the user closes the dialog.
typedef OpenDialog = Future<String?> Function();
typedef SaveDialog = Future<String?> Function(String suggestedName);

const _maxLogLines = 400;
const _maxLogBytes = 2 * 1024 * 1024;

/// Windows/macOS counterpart of MainActivity/SlicerService: runs the bundled engine as a child process.
class DesktopSlicer extends SlicerChannel {
  DesktopSlicer(
    List<String> args, {
    String? appDir,
    String? engineExe,
    AssetBundle? bundle,
    this.assetVersion,
    ProcessStarter? startProcess,
    OpenDialog? openDialog,
    SaveDialog? saveDialog,
    String? os,
  })  : _args = args,
        appDir = appDir ?? _defaultAppDir(),
        engineExe = engineExe ?? _defaultEngineExe(),
        _bundle = bundle ?? rootBundle,
        _startProcess = startProcess ?? Process.start,
        _openDialog = openDialog ?? _pickWithDialog,
        _saveDialog = saveDialog ?? _saveWithDialog,
        os = os ?? osName(),
        super.base();

  final List<String> _args;
  final String appDir;
  final String engineExe;
  final AssetBundle _bundle;
  final String? assetVersion;
  final ProcessStarter _startProcess;
  final OpenDialog _openDialog;
  final SaveDialog _saveDialog;
  final String os;

  bool _launchTaken = false;
  Process? _process;
  bool _running = false;
  bool _cancelled = false;

  String get engineDir => _join(appDir, 'engine');
  File get logFile => File(_join(appDir, 'slice-log.txt'));

  @override
  bool get desktop => true;

  @override
  bool get busy => _running;

  static String _defaultAppDir() {
    final env = Platform.environment;
    if (Platform.isWindows) return _join(env['APPDATA'] ?? env['USERPROFILE'] ?? '.', 'MobileSlice');
    return '${env['HOME'] ?? '.'}/Library/Application Support/MobileSlice';
  }

  static String _defaultEngineExe() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    if (Platform.isWindows) return _join(exeDir.path, 'engine', 'slicer_cli.exe');
    // Mobile Slice.app/Contents/MacOS/<exe> -> Contents/Resources/engine
    return '${exeDir.parent.path}/Resources/engine/slicer_cli';
  }

  /// For example "Windows 11" or "macOS 15.1".
  static String osName() {
    final version = Platform.operatingSystemVersion;
    if (Platform.isWindows) {
      final build = int.tryParse(RegExp(r'Build (\d+)').firstMatch(version)?.group(1) ?? '') ?? 0;
      return build >= 22000 ? 'Windows 11' : 'Windows 10';
    }
    if (Platform.isMacOS) {
      final number = RegExp(r'(\d+(\.\d+)*)').firstMatch(version)?.group(1);
      return number == null ? 'macOS' : 'macOS $number';
    }
    return Platform.operatingSystem;
  }

  static Future<String?> _pickWithDialog() async {
    const group = XTypeGroup(label: '3D-Modelle', extensions: ['stl', '3mf']);
    return (await openFile(acceptedTypeGroups: const [group], confirmButtonText: 'Öffnen'))?.path;
  }

  static Future<String?> _saveWithDialog(String suggestedName) async =>
      (await getSaveLocation(suggestedName: suggestedName, confirmButtonText: 'Speichern'))?.path;

  @override
  Future<DeviceInfo> prepare() async {
    await Directory(appDir).create(recursive: true);
    await _copyAssets();
    return DeviceInfo.fromMap({
      'appDir': appDir,
      'engineDir': engineDir,
      'engineInstalled': File(engineExe).existsSync(),
      'os': os,
      'cores': Platform.numberOfProcessors,
    });
  }

  // Copies the bundled engine data once per app build, like MainActivity.prepareAssets.
  Future<void> _copyAssets() async {
    final root = Directory(engineDir);
    final stamp = File(_join(root.path, '.version'));
    final version = assetVersion ?? File(Platform.resolvedExecutable).statSync().modified.millisecondsSinceEpoch.toString();
    if (stamp.existsSync() && stamp.readAsStringSync() == version) return;
    if (root.existsSync()) await root.delete(recursive: true);
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    const prefix = 'assets/engine/';
    for (final key in manifest.listAssets().where((k) => k.startsWith(prefix))) {
      final target = File(_join(root.path, key.substring(prefix.length)));
      await target.parent.create(recursive: true);
      final data = await _bundle.load(key);
      await target.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    await stamp.writeAsString(version);
  }

  @override
  Future<PickedModel?> pickModel() async {
    final path = await _openDialog();
    if (path == null) return null;
    return _copyModel(path);
  }

  @override
  Future<LaunchRequest?> takeLaunch() async {
    if (_launchTaken) return null;
    _launchTaken = true;
    final path = _args.where((a) => !a.startsWith('-')).firstOrNull;
    if (path == null) return null;
    try {
      return LaunchRequest(model: await _copyModel(path));
    } on PlatformException catch (e) {
      return LaunchRequest(error: e.message ?? 'Datei konnte nicht geöffnet werden');
    }
  }

  // Copies a picked or opened model into app storage, like MainActivity.copyModel.
  Future<PickedModel> _copyModel(String path) async {
    final source = File(path);
    final shown = source.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'modell');
    final lower = shown.toLowerCase();
    // Sliced Bambu files also end in .3mf but hold G-code, not a model.
    if (lower.endsWith('.gcode.3mf') || !(lower.endsWith('.stl') || lower.endsWith('.3mf'))) {
      throw PlatformException(code: 'failed', message: 'Bitte eine .stl- oder .3mf-Datei wählen (gewählt: $shown)');
    }
    if (!source.existsSync()) throw PlatformException(code: 'failed', message: 'Datei nicht lesbar: $shown');
    final dir = Directory(_join(appDir, 'models'));
    await dir.create(recursive: true);
    final target = File(_join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_${safeName(shown)}'));
    try {
      await source.copy(target.path);
    } on FileSystemException catch (e) {
      throw PlatformException(code: 'failed', message: 'Datei nicht lesbar: ${e.message}');
    }
    return PickedModel(path: target.path, name: shown, bytes: target.lengthSync());
  }

  @override
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') throw PlatformException(code: 'invalid', message: 'Nur https-Adressen');
    final text = uri.toString();
    final result = Platform.isWindows
        ? await Process.run('rundll32', ['url.dll,FileProtocolHandler', text])
        : await Process.run('open', [text]);
    if (result.exitCode != 0) throw PlatformException(code: 'no_browser', message: 'Browser konnte nicht geöffnet werden');
  }

  @override
  Future<void> updateWidgets(Map<String, String> data) async {}

  @override
  Future<void> setMulticast(bool on) async {}

  @override
  Future<void> shareFile(String path, {String mime = 'application/octet-stream', String title = 'Teilen'}) async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) throw PlatformException(code: 'empty', message: 'Datei nicht vorhanden');
    if (!_inside(path, appDir)) throw PlatformException(code: 'invalid', message: 'Nur App-Dateien können gespeichert werden');
    final target = await _saveDialog(file.uri.pathSegments.last);
    if (target == null) return;
    try {
      await file.copy(target);
    } on FileSystemException catch (e) {
      throw PlatformException(code: 'failed', message: 'Speichern fehlgeschlagen: ${e.message}');
    }
  }

  @override
  Future<void> shareLog() => shareFile(logFile.path, mime: 'text/plain', title: 'Diagnose-Log speichern');

  @override
  Future<void> appendLog(String title, String text) async => _appendEntry('===== $title ${_timestamp()} =====\n$text\n\n');

  void _appendEntry(String text) {
    final log = logFile;
    log.parent.createSync(recursive: true);
    // Keeps the diagnostics log from growing without bound.
    if (log.existsSync() && log.lengthSync() > _maxLogBytes) {
      final old = log.readAsStringSync();
      log.writeAsStringSync(old.substring(old.length - _maxLogBytes ~/ 2));
    }
    log.writeAsStringSync(text, mode: FileMode.append, flush: true);
  }

  @override
  Future<bool> cancel() async {
    if (!_running) return false;
    _cancelled = true;
    _process?.kill();
    return true;
  }

  @override
  Future<EngineResult> run(EngineJob job) async {
    if (_running) throw PlatformException(code: 'busy', message: 'Die Engine rechnet bereits');
    // Profiles and outputs must stay inside the app's own storage.
    final profiles = _join(engineDir, 'profiles');
    final allowedProfile = [job.process, job.filament].nonNulls.every((p) => _inside(_join(profiles, p), engineDir));
    final plate = job.plate;
    if (!allowedProfile || !_inside(job.outputDir, appDir) || (plate != null && !_inside(plate, appDir))) {
      throw PlatformException(code: 'invalid', message: 'Ungültiger Pfad im Auftrag');
    }
    _running = true;
    _cancelled = false;
    Map<String, Object?> result;
    try {
      result = await _runEngine(job);
    } catch (e) {
      result = {'ok': false, 'jobId': job.id, 'type': job.type.name, 'label': job.label, 'error': 'App-Fehler: $e'};
    }
    try {
      _appendResult(result);
    } catch (_) {
      // The log is diagnostics only.
    }
    _process = null;
    _running = false;
    return EngineResult(result);
  }

  /// Engine arguments, the same as SlicerService.runEngine.
  List<String> engineArgs(EngineJob job, Map<String, Object?> outputs) {
    final profiles = _join(engineDir, 'profiles');
    final args = [
      '--resources', _join(engineDir, 'resources'),
      '--printer', _join(profiles, 'printer.json'),
    ];
    final plate = job.plate;
    if (plate != null) {
      args.addAll(['--plate', plate]);
    } else {
      args.addAll(['--model', job.model]);
      if (job.scale != 1.0) args.addAll(['--scale', job.scale.toString()]);
    }
    if (job.type == EngineJobType.preview) {
      final stl = _join(job.outputDir, 'preview.stl');
      args.addAll(['--preview', stl]);
      outputs['previewPath'] = stl;
    } else {
      final gcode = _join(job.outputDir, 'plate_1.gcode');
      final archive = _join(job.outputDir, '${safeName(job.baseName)}.gcode.3mf');
      args.addAll([
        '--process', _join(profiles, job.process ?? 'process/0.20.json'),
        '--filament', _join(profiles, job.filament ?? 'filament/generic-pla.json'),
        '--output', gcode,
        '--export-3mf', archive,
      ]);
      if (job.modelId != null) args.addAll(['--model-id', job.modelId!]);
      if (job.overrides.isNotEmpty) args.addAll(['--overrides', jsonEncode(job.overrides)]);
      outputs['gcodePath'] = gcode;
      outputs['archivePath'] = archive;
    }
    return args;
  }

  Future<Map<String, Object?>> _runEngine(EngineJob job) async {
    final base = {'jobId': job.id, 'type': job.type.name, 'label': job.label};
    if (!File(engineExe).existsSync()) return {'ok': false, ...base, 'error': 'Engine fehlt: $engineExe'};
    await Directory(job.outputDir).create(recursive: true);
    final temp = Directory(_join(appDir, 'engine-tmp'));
    if (temp.existsSync()) await temp.delete(recursive: true);
    await temp.create(recursive: true);

    final outputs = <String, Object?>{};
    final args = engineArgs(job, outputs);
    final started = Stopwatch()..start();
    final process = await _startProcess(engineExe, args,
        workingDirectory: temp.path, environment: {'TMPDIR': temp.path, 'TMP': temp.path, 'TEMP': temp.path});
    _process = process;
    if (_cancelled) process.kill();
    unawaited(process.stdin.close().catchError((Object _) {}));

    final tail = <String>[];
    Map<String, Object?>? engineResult;
    String? engineError;
    var stage = 'start';
    final warnings = <String>[];

    void onLine(String line) {
      tail.add(line);
      if (tail.length > _maxLogLines) tail.removeAt(0);
      if (!line.startsWith('@@')) return;
      final Object? decoded;
      try {
        decoded = jsonDecode(line.substring(2));
      } on FormatException {
        return;
      }
      if (decoded is! Map) return;
      final event = decoded.cast<String, Object?>();
      if (event['result'] is Map) {
        engineResult = (event['result'] as Map).cast<String, Object?>();
      } else if (event.containsKey('error')) {
        engineError = event['error']?.toString();
      } else if (event.containsKey('warning')) {
        warnings.add(event['warning'].toString());
      } else if (event['progress'] is num) {
        emitProgress(EngineProgress(job.id, (event['progress'] as num).toInt(), event['message']?.toString() ?? ''));
      }
      if (event.containsKey('stage')) {
        stage = event['stage'].toString();
        emitProgress(EngineProgress(job.id, -1, stage));
      }
    }

    Future<void> read(Stream<List<int>> stream) =>
        stream.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(onLine);

    final reading = Future.wait([read(process.stdout), read(process.stderr)]);
    final exitCode = await process.exitCode;
    final wallMs = started.elapsedMilliseconds;
    await reading.timeout(const Duration(seconds: 2), onTimeout: () => const []);

    final res = engineResult;
    final ok = exitCode == 0 && res != null && !_cancelled;
    final rss = res?['maxRssKb'];
    final result = <String, Object?>{
      'ok': ok,
      ...base,
      'cancelled': _cancelled,
      'exitCode': exitCode,
      'signal': _cancelled ? null : signalName(exitCode),
      'wallMs': wallMs,
      'peakRssKb': rss is num ? rss.toInt() : 0,
      'stage': stage,
      'warnings': warnings,
      'error': _cancelled
          ? 'Abgebrochen'
          : ok
              ? null
              : engineError ?? 'Engine beendet mit Exit-Code $exitCode',
      'device': {'os': os, 'cores': Platform.numberOfProcessors},
      'timestamp': _timestamp(),
    };
    if (ok) result.addAll(outputs);
    if (res != null) result['engine'] = res;
    result['output'] = tail.join('\n');
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle; the folder is cleared before the next run.
    }
    return result;
  }

  void _appendResult(Map<String, Object?> result) {
    final text = StringBuffer('===== ${result['type']} ${result['timestamp'] ?? ''} =====\n');
    for (final entry in result.entries) {
      if (entry.key != 'output') text.write('${entry.key}: ${entry.value}\n');
    }
    text
      ..write('--- Engine-Ausgabe ---\n')
      ..write('${result['output'] ?? ''}\n\n');
    _appendEntry(text.toString());
  }

  /// Readable cause for a crash exit code (Windows NTSTATUS or a negative Unix signal).
  static String? signalName(int exitCode) => switch (exitCode & 0xFFFFFFFF) {
        0xC0000005 => 'Speicherzugriffsfehler (Access Violation)',
        0xC00000FD => 'Stapelüberlauf',
        0xC0000017 || 0xE06D7363 => 'Absturz (vermutlich Speicher voll)',
        0xC0000409 => 'Absturz (abort)',
        0xC000001D => 'Ungültiger Befehl',
        _ => switch (exitCode) {
            -4 => 'SIGILL',
            -6 => 'SIGABRT (Absturz/abort)',
            -9 => 'SIGKILL (vermutlich Speicher voll, vom System beendet)',
            -10 => 'SIGBUS',
            -11 => 'SIGSEGV (Speicherzugriffsfehler)',
            _ => null,
          },
      };

  static String safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
    final short = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
    return short.isEmpty ? 'modell' : short;
  }
}

String _timestamp() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
}

String _join(String a, [String? b, String? c]) {
  final sep = Platform.pathSeparator;
  var path = a;
  for (final part in [b, c].nonNulls) {
    path = path.endsWith(sep) || path.endsWith('/') ? '$path$part' : '$path$sep$part';
  }
  return path;
}

String _normalize(String path) {
  final windows = Platform.isWindows;
  final normalized = Uri.file(File(path).absolute.path, windows: windows).normalizePath().toFilePath(windows: windows);
  return windows ? normalized.toLowerCase() : normalized;
}

/// Whether [path] lies strictly inside [dir], without following `..` out of it.
bool _inside(String path, String dir) {
  final sep = Platform.pathSeparator;
  final root = _normalize(dir);
  return _normalize(path).startsWith(root.endsWith(sep) ? root : '$root$sep');
}
