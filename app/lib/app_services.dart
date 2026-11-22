import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'data/app_settings.dart';
import 'data/home_widgets.dart';
import 'data/preset_store.dart';
import 'data/print_history.dart';
import 'data/recent_models.dart';
import 'data/json_store.dart';
import 'engine/profile_catalog.dart';
import 'engine/profile_values.dart';
import 'engine/slice_settings.dart';
import 'engine/slicer_channel.dart';
import 'model/mesh.dart';
import 'model/plate_project.dart';
import 'model/stl_reader.dart';
import 'printer/bambu_printer.dart';
import 'printer/printer_config.dart';
import 'trophies/trophy_catalog.dart';
import 'trophies/trophy_engine.dart';

typedef PrinterFactory = BambuPrinter Function(PrinterConfig config, void Function(PrinterConfig) onPinsChanged);

/// Everything the screens share. Created once; [init] loads it in the background.
class AppServices {
  AppServices({SlicerChannel? slicer, this.bundle, PrinterFactory? printerFactory})
      : slicer = slicer ?? SlicerChannel(),
        _printerFactory = printerFactory ?? ((config, onPins) => BambuPrinter(config: config, onPinsChanged: onPins));

  final SlicerChannel slicer;
  final AssetBundle? bundle;
  final PrinterFactory _printerFactory;

  late DeviceInfo device;
  late ProfileCatalog catalog;
  late ProfileValues profile;
  late JsonStore store;
  late ValueNotifier<SliceSettings> settings;
  late PrinterConfigStore printerStore;
  late PresetStore presets;
  late AppSettings appSettings;

  /// The configured printer, null until set up.
  final printer = ValueNotifier<BambuPrinter?>(null);

  late PrintHistory history;

  /// Prints that just finished or failed, as seen in the printer's reports.
  final closedPrints = StreamController<PrintRecord>.broadcast();
  StreamSubscription<Object?>? _reportSub;

  late TrophyEngine trophies;
  HomeWidgetSync? _widgets;
  late RecentModels recent;

  /// The open slicer project (plates and objects); lives as long as the app.
  late final PlateProject project = PlateProject(
    bed: PlateSize(catalog.printer.bedX, catalog.printer.bedY, catalog.printer.height),
  );

  final _sources = <String, Future<ModelSource>>{};

  /// Loads a model once through the engine's preview (geometry as the engine places it), cached by path.
  Future<ModelSource> loadSource(PickedModel model) async {
    final pending = _sources[model.path] ??= _loadSource(model);
    try {
      return await pending;
    } catch (_) {
      // A failed load must be retryable.
      _sources.remove(model.path);
      rethrow;
    }
  }

  Future<ModelSource> _loadSource(PickedModel model) async {
    final dir = await newJobDir('preview-${DateTime.now().microsecondsSinceEpoch}');
    try {
      final result = await slicer.run(EngineJob(type: EngineJobType.preview, model: model.path, label: model.name, outputDir: dir.path));
      final path = result.previewPath;
      if (!result.ok || path == null) throw Exception(result.failure);
      final triangles = await readStlInBackground(await File(path).readAsBytes());
      return ModelSource(path: model.path, name: model.name, mesh: Mesh(triangles), bytes: model.bytes);
    } finally {
      unawaited(dir.delete(recursive: true).then((_) {}, onError: (Object _) {}));
    }
  }

  /// Trophies earned just now (for the pop-up).
  final newTrophies = StreamController<Trophy>.broadcast();

  Directory get jobsDir => Directory('${device.appDir}/jobs');

  /// The bundled 20 mm test cube.
  PickedModel get sampleModel => PickedModel(path: '${device.engineDir}/models/test_cube.stl', name: 'Testwürfel 20 mm.stl', bytes: 0);

  Future<void>? _init;
  Future<void> init() => _init ??= _load();

  Future<void> retryInit() {
    _init = null;
    return init();
  }

  Future<void> _load() async {
    device = await slicer.prepare();
    catalog = await ProfileCatalog.load(bundle);
    profile = await ProfileValues.load(catalog, bundle);
    store = JsonStore(Directory('${device.appDir}/data'));
    appSettings = AppSettings(store);
    await appSettings.load();
    final saved = await store.readMap('settings');
    settings = ValueNotifier(saved == null ? SliceSettings.defaults(catalog) : SliceSettings.fromJson(saved, catalog));
    settings.addListener(() => store.write('settings', settings.value.toJson()));
    presets = PresetStore(store);
    await presets.load();
    history = PrintHistory(store);
    await history.load();
    recent = RecentModels(store, modelsDir: Directory('${device.appDir}/models'));
    await recent.load();
    trophies = TrophyEngine(store);
    await trophies.load();
    // Silently catch up on anything earned before (e.g. after an update).
    await trophies.check(history.records.value);
    history.records
      ..removeListener(_checkTrophies)
      ..addListener(_checkTrophies);
    printer
      ..removeListener(_watchPrinter)
      ..addListener(_watchPrinter);
    _widgets?.dispose();
    _widgets = HomeWidgetSync(
      send: slicer.updateWidgets,
      printer: printer,
      history: history.records,
      unlocked: trophies.unlocked,
      catalog: trophies.catalog,
    )..start();
    printerStore = PrinterConfigStore(store);
    final config = await printerStore.load();
    if (config != null && config.isValid && printer.value == null) {
      printer.value = _printerFactory(config, printerStore.save);
      unawaited(printer.value!.connect());
    }
  }

  Future<void> _checkTrophies() async {
    for (final trophy in await trophies.check(history.records.value)) {
      newTrophies.add(trophy);
    }
  }

  void _watchPrinter() {
    _reportSub?.cancel();
    _reportSub = printer.value?.reports.asyncMap(history.applyStatus).listen((closed) {
      if (closed != null) closedPrints.add(closed);
    });
  }

  /// A printer object that is not (yet) the app's printer, e.g. for a connection test.
  BambuPrinter makePrinter(PrinterConfig config, void Function(PrinterConfig) onPinsChanged) => _printerFactory(config, onPinsChanged);

  /// Saves [config] (null removes the printer) and connects to it.
  Future<void> setPrinter(PrinterConfig? config) async {
    final old = printer.value;
    printer.value = null;
    old?.dispose();
    if (config == null) {
      await printerStore.clear();
      return;
    }
    await printerStore.save(config);
    final next = _printerFactory(config, printerStore.save);
    printer.value = next;
    unawaited(next.connect());
  }

  /// Fresh output folder for one engine job; old slice results beyond [keep] are removed.
  Future<Directory> newJobDir(String jobId, {int keep = 8}) async {
    final dir = Directory('${jobsDir.path}/$jobId');
    await dir.create(recursive: true);
    final all = jobsDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(keep)) {
      try {
        await old.delete(recursive: true);
      } on FileSystemException {
        // A file still being uploaded may be locked; it goes next time.
      }
    }
    return dir;
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
