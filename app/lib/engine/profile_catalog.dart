import 'dart:convert';

import 'package:flutter/services.dart';

double _num(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

Color parseHexColor(String hex, {Color fallback = const Color(0xFFFFFFFF)}) {
  final digits = hex.replaceFirst('#', '');
  final value = int.tryParse(digits.length == 6 ? 'FF$digits' : digits, radix: 16);
  return value == null || (digits.length != 6 && digits.length != 8) ? fallback : Color(value);
}

class PrinterInfo {
  const PrinterInfo({required this.name, required this.modelId, required this.nozzle, required this.bedX, required this.bedY, required this.height});

  final String name;
  final String modelId;
  final double nozzle;
  final double bedX;
  final double bedY;
  final double height;
}

class ProcessProfile {
  const ProcessProfile({required this.id, required this.label, required this.name, required this.file, required this.layerHeight, required this.infill, required this.walls});

  final String id;
  final String label;
  final String name;
  final String file;
  final double layerHeight;
  final int infill;
  final int walls;
}

class FilamentProfile {
  const FilamentProfile({
    required this.id,
    required this.label,
    required this.name,
    required this.file,
    required this.type,
    required this.vendor,
    required this.color,
    required this.density,
    required this.nozzleTemp,
    required this.bedTemp,
  });

  final String id;
  final String label;
  final String name;
  final String file;
  final String type;
  final String vendor;
  final Color color;
  final double density;
  final int nozzleTemp;
  final int bedTemp;
}

/// The bundled profiles, read from `assets/engine/profiles/catalog.json` (written by flatten_profiles.py).
class ProfileCatalog {
  const ProfileCatalog({
    required this.printer,
    required this.processes,
    required this.filaments,
    required this.defaultProcess,
    required this.defaultFilament,
  });

  factory ProfileCatalog.fromJson(Map<String, Object?> json) {
    final printer = json['printer'] as Map<String, Object?>;
    final bed = (printer['bed'] as List?) ?? const [256, 256];
    final processes = [
      for (final p in (json['processes'] as List).cast<Map<String, Object?>>())
        ProcessProfile(
          id: p['id'] as String,
          label: p['label'] as String,
          name: p['name'] as String,
          file: p['file'] as String,
          layerHeight: _num(p['layerHeight'], 0.2),
          infill: _num(p['infill'], 15).round(),
          walls: _num(p['walls'], 2).round(),
        ),
    ];
    final filaments = [
      for (final f in (json['filaments'] as List).cast<Map<String, Object?>>())
        FilamentProfile(
          id: f['id'] as String,
          label: f['label'] as String,
          name: f['name'] as String,
          file: f['file'] as String,
          type: f['type'] as String? ?? 'PLA',
          vendor: f['vendor'] as String? ?? 'Generic',
          color: parseHexColor(f['color'] as String? ?? '#FFFFFF'),
          density: _num(f['density'], 1.24),
          nozzleTemp: _num(f['nozzleTemp'], 220).round(),
          bedTemp: _num(f['bedTemp'], 60).round(),
        ),
    ];
    if (processes.isEmpty || filaments.isEmpty) throw const FormatException('Katalog ohne Profile');
    return ProfileCatalog(
      printer: PrinterInfo(
        name: printer['name'] as String,
        modelId: printer['modelId'] as String? ?? '',
        nozzle: _num(printer['nozzle'], 0.4),
        bedX: _num(bed[0], 256),
        bedY: _num(bed[1], 256),
        height: _num(printer['height'], 256),
      ),
      processes: processes,
      filaments: filaments,
      defaultProcess: json['defaultProcess'] as String? ?? processes.first.id,
      defaultFilament: json['defaultFilament'] as String? ?? filaments.first.id,
    );
  }

  static Future<ProfileCatalog> load([AssetBundle? bundle]) async {
    final text = await (bundle ?? rootBundle).loadString('assets/engine/profiles/catalog.json');
    return ProfileCatalog.fromJson(jsonDecode(text) as Map<String, Object?>);
  }

  final PrinterInfo printer;
  final List<ProcessProfile> processes;
  final List<FilamentProfile> filaments;
  final String defaultProcess;
  final String defaultFilament;

  ProcessProfile process(String id) =>
      processes.firstWhere((p) => p.id == id, orElse: () => processes.firstWhere((p) => p.id == defaultProcess, orElse: () => processes.first));

  FilamentProfile filament(String id) =>
      filaments.firstWhere((f) => f.id == id, orElse: () => filaments.firstWhere((f) => f.id == defaultFilament, orElse: () => filaments.first));
}
