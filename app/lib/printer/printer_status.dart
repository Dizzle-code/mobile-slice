enum PrintState {
  idle('Bereit'),
  preparing('Bereitet vor'),
  printing('Druckt'),
  paused('Pausiert'),
  finished('Fertig'),
  failed('Abgebrochen'),
  unknown('Unbekannt');

  const PrintState(this.label);
  final String label;

  bool get busy => this == preparing || this == printing || this == paused;

  static PrintState parse(Object? value) => switch (value?.toString().toUpperCase()) {
        'IDLE' => idle,
        'PREPARE' || 'SLICING' || 'INIT' => preparing,
        'RUNNING' => printing,
        'PAUSE' => paused,
        'FINISH' => finished,
        'FAILED' => failed,
        _ => unknown,
      };
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

/// Recursively merges [update] into a copy of [base]. Lists and plain values are replaced.
Map<String, Object?> deepMerge(Map<String, Object?> base, Map<String, Object?> update) {
  final out = Map<String, Object?>.of(base);
  update.forEach((key, value) {
    final old = out[key];
    out[key] = value is Map && old is Map
        ? deepMerge(old.cast<String, Object?>(), value.cast<String, Object?>())
        : value;
  });
  return out;
}

/// The printer's state. The P1S sends one full report after "pushall" and then only
/// changed fields, so every report is merged into the previous state.
class PrinterStatus {
  const PrinterStatus([this.raw = const {}]);

  /// The merged `print` object of the reports.
  final Map<String, Object?> raw;

  bool get isEmpty => raw.isEmpty;

  PrinterStatus merge(Map<String, Object?> report) {
    final print = report['print'];
    if (print is! Map) return this;
    final update = Map<String, Object?>.of(print.cast<String, Object?>())
      ..remove('command')
      ..remove('sequence_id')
      ..remove('msg');
    return PrinterStatus(deepMerge(raw, update));
  }

  PrintState get state => PrintState.parse(raw['gcode_state']);
  int get percent => _i(raw['mc_percent']).clamp(0, 100);
  int get remainingMinutes => _i(raw['mc_remaining_time']);
  int get layer => _i(raw['layer_num']);
  int get totalLayers => _i(raw['total_layer_num']);
  double get nozzle => _d(raw['nozzle_temper']);
  double get nozzleTarget => _d(raw['nozzle_target_temper']);
  double get bed => _d(raw['bed_temper']);
  double get bedTarget => _d(raw['bed_target_temper']);
  double get chamber => _d(raw['chamber_temper']);
  String get subtaskName => raw['subtask_name']?.toString() ?? '';
  int get printError => _i(raw['print_error']);
  String get wifiSignal => raw['wifi_signal']?.toString() ?? '';
  bool get hasSdCard => raw['sdcard'] != false;
  int get stage => _i(raw['stg_cur']);
  int get speedLevel => _i(raw['spd_lvl']);

  /// Human readable sub-stage while preparing (bed leveling, heating, …).
  String? get stageLabel => switch (stage) {
        1 => 'Bett wird vermessen',
        2 => 'Heizbett wärmt vor',
        3 => 'Vibrationskompensation',
        4 => 'Filament wird gewechselt',
        7 => 'Düse heizt',
        8 => 'Extrusion wird kalibriert',
        9 => 'Druckbett wird gescannt',
        13 => 'Referenzfahrt',
        14 => 'Düse wird gereinigt',
        _ => null,
      };
}
