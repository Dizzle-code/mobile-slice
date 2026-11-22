import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

int _int(Object? value) => value is num ? value.toInt() : 0;
double _double(Object? value) => value is num ? value.toDouble() : 0;

Map<String, Object?> _stringMap(Object? value) => value is Map
    ? value.map((key, v) => MapEntry(key.toString(), v))
    : const {};

/// German label for an engine stage event.
String stageLabel(String stage) => switch (stage) {
      'start' => 'Engine startet',
      'profiles' => 'Profile laden',
      'load_model' => 'Modell laden',
      'validate' => 'Einstellungen prüfen',
      'process' => 'Schichten berechnen',
      'export' => 'G-Code schreiben',
      'export_3mf' => 'Druckdatei packen',
      _ => stage,
    };

class DeviceInfo {
  const DeviceInfo({required this.appDir, required this.engineDir, required this.engineInstalled, required this.summary});

  factory DeviceInfo.fromMap(Map<Object?, Object?> map) => DeviceInfo(
        appDir: map['appDir']?.toString() ?? '',
        engineDir: map['engineDir']?.toString() ?? '',
        engineInstalled: map['engineInstalled'] == true,
        summary: map['os'] != null
            ? '${map['os']} · ${map['cores'] ?? '?'} Kerne'
            : '${map['model'] ?? '?'} · Android ${map['android'] ?? '?'} · ${map['cores'] ?? '?'} Kerne',
      );

  final String appDir;
  final String engineDir;
  final bool engineInstalled;
  final String summary;
}

class PickedModel {
  const PickedModel({required this.path, required this.name, required this.bytes});

  final String path;
  final String name;
  final int bytes;
}

enum EngineJobType { preview, slice }

class EngineJob {
  EngineJob({
    required this.type,
    required this.model,
    required this.label,
    required this.outputDir,
    this.baseName = 'modell',
    this.process,
    this.filament,
    this.overrides = const {},
    this.modelId,
    this.scale = 1.0,
  }) : id = '${type.name}-${DateTime.now().microsecondsSinceEpoch}';

  final String id;
  final EngineJobType type;
  final String model;
  final String label;
  final String outputDir;
  final String baseName;
  final String? process;
  final String? filament;
  final Map<String, Object> overrides;
  final String? modelId;

  /// Uniform model scale factor applied by the engine before placing the model.
  final double scale;

  Map<String, Object?> toMap() => {
        'jobId': id,
        'type': type.name,
        'model': model,
        'label': label,
        'outputDir': outputDir,
        'baseName': baseName,
        'process': process,
        'filament': filament,
        if (overrides.isNotEmpty) 'overrides': jsonEncode(overrides),
        'modelId': modelId,
        if (scale != 1.0) 'scale': scale,
      };
}

class EngineProgress {
  const EngineProgress(this.jobId, this.percent, this.message);

  final String jobId;

  /// -1 when only the stage changed.
  final int percent;
  final String message;

  bool get isStage => percent < 0;
}

class EngineResult {
  EngineResult(this.raw);

  factory EngineResult.fromMap(Map<Object?, Object?> map) => EngineResult(_stringMap(map));

  final Map<String, Object?> raw;

  bool get ok => raw['ok'] == true;
  bool get cancelled => raw['cancelled'] == true;
  String get jobId => raw['jobId']?.toString() ?? '';
  String? get error => raw['error']?.toString();
  String get stage => raw['stage']?.toString() ?? '';
  int get wallMs => _int(raw['wallMs']);
  int get peakRssKb => _int(raw['peakRssKb']);
  String? get signal => raw['signal']?.toString();
  String get output => raw['output']?.toString() ?? '';
  List<String> get warnings => (raw['warnings'] as List?)?.map((w) => w.toString()).toList() ?? const [];
  Map<String, Object?> get engine => _stringMap(raw['engine']);

  String? get previewPath => raw['previewPath']?.toString();
  String? get archivePath => raw['archivePath']?.toString();
  String? get gcodePath => raw['gcodePath']?.toString();

  int get printSeconds => _double(engine['printSeconds']).round();
  double get filamentGrams => _double(engine['filamentGrams']);
  double get filamentMm => _double(engine['filamentMm']);
  int get layers => _int(engine['layers']);
  int get triangles => _int(engine['triangles']);
  bool get supportUsed => engine['supportUsed'] == true;
  bool get fits => engine['fits'] != false;

  /// Short German failure text for the UI.
  String get failure {
    if (cancelled) return 'Abgebrochen';
    final signal = this.signal;
    final error = this.error ?? 'Unbekannter Fehler';
    return signal == null ? error : '$error ($signal)';
  }
}

/// Bridge to MainActivity/SlicerService. Only one engine job runs at a time.
class SlicerChannel {
  SlicerChannel({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('mobile_slice/slicer') {
    _channel.setMethodCallHandler(_onCall);
  }

  /// For implementations without a native side (see DesktopSlicer).
  @protected
  SlicerChannel.base() : _channel = const MethodChannel('mobile_slice/slicer');

  final MethodChannel _channel;
  final _progress = StreamController<EngineProgress>.broadcast();
  final _launches = StreamController<void>.broadcast();
  final _running = <String, Completer<EngineResult>>{};

  Stream<EngineProgress> get progress => _progress.stream;

  bool get busy => _running.isNotEmpty;

  /// True on Windows/macOS: files are saved instead of shared, and there are no home screen widgets.
  bool get desktop => false;

  @protected
  void emitProgress(EngineProgress event) => _progress.add(event);

  Future<DeviceInfo> prepare() async =>
      DeviceInfo.fromMap((await _channel.invokeMethod<Map<Object?, Object?>>('prepare')) ?? const {});

  /// Null when the user closes the picker.
  Future<PickedModel?> pickModel() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('pickModel');
    if (map == null) return null;
    return PickedModel(path: map['path'].toString(), name: map['name'].toString(), bytes: _int(map['bytes']));
  }

  /// Fires when Android has a new [LaunchRequest] waiting (shortcut, widget, shared file).
  Stream<void> get launches => _launches.stream;

  /// The pending launch request, taken only once.
  Future<LaunchRequest?> takeLaunch() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('takeLaunch');
    return map == null ? null : LaunchRequest.fromMap(map);
  }

  Future<void> openUrl(String url) => _channel.invokeMethod('openUrl', {'url': url});

  /// Texts for the home screen widgets (see HomeWidgets.kt).
  Future<void> updateWidgets(Map<String, String> data) => _channel.invokeMethod('updateWidgets', data);

  Future<EngineResult> run(EngineJob job) async {
    final completer = Completer<EngineResult>();
    _running[job.id] = completer;
    try {
      await _channel.invokeMethod('runJob', job.toMap());
    } catch (_) {
      _running.remove(job.id);
      rethrow;
    }
    return completer.future;
  }

  Future<bool> cancel() async => await _channel.invokeMethod<bool>('cancelJob') ?? false;

  Future<void> shareFile(String path, {String mime = 'application/octet-stream', String title = 'Teilen'}) =>
      _channel.invokeMethod('shareFile', {'path': path, 'mime': mime, 'title': title});

  Future<void> shareLog() => _channel.invokeMethod('shareLog');

  Future<void> appendLog(String title, String text) => _channel.invokeMethod('appendLog', {'title': title, 'text': text});

  Future<void> setMulticast(bool on) => _channel.invokeMethod('multicastLock', {'on': on});

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'launch') {
      _launches.add(null);
      return;
    }
    final args = call.arguments;
    if (args is! Map) return;
    final jobId = args['jobId']?.toString() ?? '';
    if (call.method == 'progress') {
      _progress.add(EngineProgress(jobId, _int(args['percent']), args['message']?.toString() ?? ''));
    } else if (call.method == 'finished') {
      _running.remove(jobId)?.complete(EngineResult.fromMap(args));
    }
  }
}

/// Why Android opened the app: a shortcut or widget [action], a shared/opened [model], or an [error].
class LaunchRequest {
  const LaunchRequest({this.action, this.model, this.error});

  factory LaunchRequest.fromMap(Map<Object?, Object?> map) => switch (map['type']) {
        'file' => LaunchRequest(
            model: PickedModel(path: map['path'].toString(), name: map['name'].toString(), bytes: _int(map['bytes'])),
          ),
        'error' => LaunchRequest(error: map['message']?.toString() ?? 'Datei konnte nicht geöffnet werden'),
        _ => LaunchRequest(action: map['action']?.toString()),
      };

  /// One of home, open_model, printer, history, trophies.
  final String? action;
  final PickedModel? model;
  final String? error;
}
