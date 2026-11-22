import 'package:flutter/foundation.dart';

import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import 'profile_catalog.dart';
import 'profile_values.dart';
import 'setting_defs.dart';
import 'slice_settings.dart';

/// A starting point for the settings: layer height, individual values and speed. The filament stays.
class SlicePreset {
  const SlicePreset({
    required this.id,
    required this.name,
    required this.description,
    this.glyphName = 'save',
    this.processId,
    this.values = const {},
    this.speedPercent = 100,
    this.builtIn = false,
  });

  /// Reads a saved custom preset; values the app no longer knows are dropped. Null when unusable.
  static SlicePreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) return null;
    final values = <String, Object>{};
    final stored = json['values'];
    if (stored is Map) {
      for (final MapEntry(:key, :value) in stored.entries) {
        final def = settingDef('$key');
        final typed = def == null ? null : normalizeSettingValue(def, value);
        if (typed != null) values['$key'] = typed;
      }
    }
    final speed = json['speedPercent'];
    final process = json['processId'];
    return SlicePreset(
      id: id,
      name: name.trim(),
      description: json['description'] as String? ?? '',
      processId: process is String ? process : null,
      values: Map.unmodifiable(values),
      speedPercent: speed is num ? speed.round().clamp(SliceSettings.minSpeed, SliceSettings.maxSpeed) : 100,
    );
  }

  final String id;
  final String name;
  final String description;
  final String glyphName;

  /// Process profile (layer height); null keeps the current one.
  final String? processId;
  final Map<String, Object> values;
  final int speedPercent;
  final bool builtIn;

  PixelGlyph get glyph => PixelIcons.all.firstWhere((g) => g.name == glyphName, orElse: () => PixelIcons.save);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'processId': processId,
        'values': values,
        'speedPercent': speedPercent,
      };

  SlicePreset renamed(String name) => SlicePreset(
        id: id,
        name: name,
        description: description,
        glyphName: glyphName,
        processId: processId,
        values: values,
        speedPercent: speedPercent,
        builtIn: builtIn,
      );

  /// Replaces layer height, values and speed; the filament is kept.
  SliceSettings applyTo(SliceSettings settings, ProfileCatalog catalog) => settings.copyWith(
        processId: processId == null ? null : catalog.process(processId!).id,
        values: values,
        speedPercent: speedPercent,
        presetId: () => id,
      );

  /// True while [settings] still look exactly like this preset.
  bool matches(SliceSettings settings) =>
      (processId == null || settings.processId == processId) &&
      settings.speedPercent == speedPercent &&
      mapEquals(settings.values, values);

  /// Short German summary of what the preset changes, e.g. "0,12 mm · 2 Änderungen · 80 %".
  String summary(ProfileCatalog catalog) => [
        if (processId != null) '${catalog.process(processId!).layerHeight.toStringAsFixed(2).replaceAll('.', ',')} mm',
        if (values.isNotEmpty) values.length == 1 ? '1 Änderung' : '${values.length} Änderungen',
        if (speedPercent != 100) 'Tempo $speedPercent %',
      ].join(' · ');
}

/// Presets that ship with the app.
const builtInPresets = <SlicePreset>[
  SlicePreset(
    id: 'standard',
    name: 'Standard',
    description: 'Die Werte des Profils ohne Änderungen. Guter Ausgangspunkt für fast alles.',
    glyphName: 'cube',
    processId: '0.20',
    builtIn: true,
  ),
  SlicePreset(
    id: 'draft',
    name: 'Schneller Entwurf',
    description: 'Dicke Schichten, wenig Füllung, höheres Tempo. Zum Testen von Form und Passung.',
    glyphName: 'speed',
    processId: '0.28',
    values: {'sparse_infill_density': 10.0, 'wall_loops': 2},
    speedPercent: 130,
    builtIn: true,
  ),
  SlicePreset(
    id: 'fine',
    name: 'Fein und detailliert',
    description: 'Feine Schichten und eine langsamere Außenwand für sichtbare Details, Naht hinten.',
    glyphName: 'star',
    processId: '0.12',
    values: {'outer_wall_speed': 120.0, 'seam_position': 'back'},
    builtIn: true,
  ),
  SlicePreset(
    id: 'thin_walls',
    name: 'Feine dünne Wände',
    description: 'Arachne passt die Linienbreite an, dünne Stellen werden gedruckt statt ausgelassen.',
    glyphName: 'feather',
    processId: '0.12',
    values: {'wall_generator': 'arachne', 'detect_thin_wall': true},
    speedPercent: 80,
    builtIn: true,
  ),
  SlicePreset(
    id: 'technical',
    name: 'Technisch und stabil',
    description: 'Vier Wände, 40 % Gyroid und dicke Deckschichten für belastete Teile.',
    glyphName: 'wrench',
    processId: '0.20',
    values: {
      'wall_loops': 4,
      'sparse_infill_density': 40.0,
      'sparse_infill_pattern': 'gyroid',
      'top_shell_layers': 5,
      'bottom_shell_layers': 5,
    },
    builtIn: true,
  ),
  SlicePreset(
    id: 'smooth_top',
    name: 'Glatte Oberseite',
    description: 'Bügelt die oberste Fläche glatt und druckt sie monoton. Dauert etwas länger.',
    glyphName: 'iron',
    values: {'ironing_type': 'topmost', 'top_surface_pattern': 'monotonic'},
    builtIn: true,
  ),
  SlicePreset(
    id: 'vase',
    name: 'Vase',
    description: 'Eine durchgehende Spiralwand ohne Füllung und Deckel. Für Vasen, Becher und Lampenschirme.',
    glyphName: 'vase',
    values: {'spiral_mode': true, 'sparse_infill_density': 0.0, 'wall_loops': 1, 'top_shell_layers': 0},
    builtIn: true,
  ),
  SlicePreset(
    id: 'miniature',
    name: 'Miniatur',
    description: 'Hauchdünne Schichten, Baumstützen und ein kleiner Brim für Figuren.',
    glyphName: 'figure',
    processId: '0.08',
    values: {'enable_support': true, 'support_type': 'tree(auto)', 'brim_type': 'outer_only', 'brim_width': 3.0},
    speedPercent: 70,
    builtIn: true,
  ),
  SlicePreset(
    id: 'fuzzy',
    name: 'Fuzzy-Optik',
    description: 'Raue, griffige Außenwand, die Schichtlinien versteckt.',
    glyphName: 'fuzzy',
    values: {'fuzzy_skin': 'external', 'fuzzy_skin_thickness': 0.3},
    builtIn: true,
  ),
];

SlicePreset? builtInPreset(String? id) {
  for (final preset in builtInPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
