import 'profile_catalog.dart';
import 'profile_values.dart';
import 'slice_settings.dart';
import 'slicer_channel.dart';

/// A finished slice: the ready-to-print file plus what the result screen and history need.
class SliceOutcome {
  const SliceOutcome({
    required this.modelName,
    required this.archivePath,
    required this.printSeconds,
    required this.grams,
    required this.meters,
    required this.layers,
    required this.supportUsed,
    required this.layerHeight,
    required this.processLabel,
    required this.filamentLabel,
    required this.filamentType,
    required this.infill,
    required this.walls,
    required this.warnings,
    required this.slicedAt,
  });

  factory SliceOutcome.from({
    required String modelName,
    required EngineResult result,
    required SliceSettings settings,
    required ProfileCatalog catalog,
    required ProfileValues profile,
    DateTime? now,
  }) {
    final process = catalog.process(settings.processId);
    final filament = catalog.filament(settings.filamentId);
    return SliceOutcome(
      modelName: modelName,
      archivePath: result.archivePath ?? '',
      printSeconds: result.printSeconds,
      grams: result.filamentGrams,
      meters: result.filamentMm / 1000,
      layers: result.layers,
      supportUsed: result.supportUsed,
      layerHeight: process.layerHeight,
      processLabel: process.label,
      filamentLabel: filament.label,
      filamentType: filament.type,
      infill: (settings.effectiveKey('sparse_infill_density', profile) as num).round(),
      walls: settings.effectiveKey('wall_loops', profile) as int,
      warnings: result.warnings,
      slicedAt: now ?? DateTime.now(),
    );
  }

  final String modelName;
  final String archivePath;
  final int printSeconds;
  final double grams;
  final double meters;
  final int layers;
  final bool supportUsed;
  final double layerHeight;
  final String processLabel;
  final String filamentLabel;
  final String filamentType;
  final int infill;
  final int walls;
  final List<String> warnings;
  final DateTime slicedAt;

  /// File name on the printer's SD card, e.g. `benchy.gcode.3mf`.
  String get remoteName => archivePath.split(RegExp(r'[\\/]')).last;
}

/// "3DBenchy.stl" -> "3DBenchy"; only characters that are safe on the printer's SD card.
String baseNameOf(String fileName) {
  final withoutExt = fileName.replaceFirst(RegExp(r'\.(stl|3mf)$', caseSensitive: false), '');
  final safe = withoutExt.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  final short = safe.length > 60 ? safe.substring(0, 60) : safe;
  return short.isEmpty ? 'modell' : short;
}
