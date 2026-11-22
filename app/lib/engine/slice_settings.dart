import 'package:flutter/foundation.dart';

import 'profile_catalog.dart';
import 'profile_values.dart';
import 'setting_defs.dart';

/// Engine text for a typed value, e.g. `15%`, `0.2`, `1`, `tree(auto)`.
String engineValue(SettingDef def, Object value) => switch (def.kind) {
      SettingKind.integer => '${(value as num).round()}',
      SettingKind.decimal => _plain((value as num).toDouble()),
      SettingKind.percent => '${_plain((value as num).toDouble())}%',
      SettingKind.toggle => value == true ? '1' : '0',
      SettingKind.choice => '$value',
    };

String _plain(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
}

/// What the user picked: process and filament profile plus individual changes on top of them.
class SliceSettings {
  const SliceSettings({
    required this.processId,
    required this.filamentId,
    this.values = const {},
    this.speedPercent = 100,
    this.presetId,
  });

  factory SliceSettings.defaults(ProfileCatalog catalog) =>
      SliceSettings(processId: catalog.defaultProcess, filamentId: catalog.defaultFilament, presetId: 'standard');

  factory SliceSettings.fromJson(Map<String, Object?> json, ProfileCatalog catalog) {
    final values = <String, Object>{};
    final stored = json['values'];
    if (stored is Map) {
      for (final MapEntry(:key, :value) in stored.entries) {
        final def = settingDef('$key');
        final typed = def == null ? null : normalizeSettingValue(def, value);
        if (typed != null) values['$key'] = typed;
      }
    } else {
      values.addAll(_migrate(json));
    }
    final speed = json['speedPercent'];
    final preset = json['presetId'];
    return SliceSettings(
      processId: catalog.process(json['processId'] as String? ?? '').id,
      filamentId: catalog.filament(json['filamentId'] as String? ?? '').id,
      values: Map.unmodifiable(values),
      speedPercent: speed is num ? speed.round().clamp(minSpeed, maxSpeed) : 100,
      presetId: preset is String ? preset : (stored is! Map && values.isEmpty ? 'standard' : null),
    );
  }

  /// Settings saved before the full settings list (infill, walls, support, brim).
  static Map<String, Object> _migrate(Map<String, Object?> json) {
    final infill = json['infill'];
    final walls = json['walls'];
    final support = json['support'];
    return {
      if (infill is num) 'sparse_infill_density': infill.clamp(0, 100).toDouble(),
      if (walls is num) 'wall_loops': walls.round().clamp(1, 10),
      if (support == 'normal' || support == 'tree') ...{
        'enable_support': true,
        'support_type': support == 'tree' ? 'tree(auto)' : 'normal(auto)',
        if (json['supportOnPlateOnly'] == true) 'support_on_build_plate_only': true,
      },
      if (json['brim'] == 'off') 'brim_type': 'no_brim',
      if (json['brim'] == 'outer') 'brim_type': 'outer_only',
    };
  }

  static const minSpeed = 50;
  static const maxSpeed = 200;

  final String processId;
  final String filamentId;

  /// Values the user set, by engine key; everything else comes from the profiles.
  final Map<String, Object> values;

  /// Scales every print speed of the profile that the user did not set individually.
  final int speedPercent;

  /// The preset these settings started from.
  final String? presetId;

  /// Number of individual changes (the speed slider counts as one).
  int get changedCount => values.length + (speedPercent == 100 ? 0 : 1);

  Map<String, Object?> toJson() => {
        'processId': processId,
        'filamentId': filamentId,
        'values': values,
        'speedPercent': speedPercent,
        'presetId': presetId,
      };

  SliceSettings copyWith({
    String? processId,
    String? filamentId,
    Map<String, Object>? values,
    int? speedPercent,
    String? Function()? presetId,
  }) =>
      SliceSettings(
        processId: processId ?? this.processId,
        filamentId: filamentId ?? this.filamentId,
        values: values == null ? this.values : Map.unmodifiable(values),
        speedPercent: speedPercent ?? this.speedPercent,
        presetId: presetId == null ? this.presetId : presetId(),
      );

  /// Sets [key]; a null value or one equal to [profileValue] goes back to the profile.
  SliceSettings withValue(String key, Object? value, {Object? profileValue}) {
    final next = Map.of(values);
    if (value == null || value == profileValue) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return copyWith(values: next);
  }

  /// Everything back to the profiles (layer height and filament stay).
  SliceSettings reset() => copyWith(values: const {}, speedPercent: 100, presetId: () => null);

  bool isChanged(String key) => values.containsKey(key);

  Object profileValue(SettingDef def, ProfileValues profile) =>
      profile.valueOf(def, processId: processId, filamentId: filamentId);

  /// The value the engine will use for [def].
  Object effective(SettingDef def, ProfileValues profile) => values[def.key] ?? profileValue(def, profile);

  Object effectiveKey(String key, ProfileValues profile) => effective(settingDef(key)!, profile);

  bool isVisible(SettingDef def, ProfileValues profile) {
    final showIf = def.showIf;
    return showIf == null || showIf.test(effectiveKey(showIf.key, profile));
  }

  /// Engine config keys (`--overrides`) on top of the selected process and filament profiles.
  Map<String, Object> overrides(ProfileValues profile) {
    final out = <String, Object>{};
    for (final MapEntry(:key, :value) in values.entries) {
      final def = settingDef(key);
      if (def != null) out[key] = engineValue(def, value);
    }
    if (speedPercent != 100) {
      for (final def in settingDefs.where((d) => d.scalesWithSpeed && !values.containsKey(d.key))) {
        final base = (profileValue(def, profile) as num).toDouble();
        if (base <= 0) continue;
        out[def.key] = engineValue(def, (base * speedPercent / 100 * 10).round() / 10);
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is SliceSettings &&
      other.processId == processId &&
      other.filamentId == filamentId &&
      mapEquals(other.values, values) &&
      other.speedPercent == speedPercent &&
      other.presetId == presetId;

  @override
  int get hashCode => Object.hash(processId, filamentId, Object.hashAllUnordered(values.entries.map((e) => Object.hash(e.key, e.value))), speedPercent, presetId);
}
