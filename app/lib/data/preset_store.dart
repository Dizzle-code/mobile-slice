import 'package:flutter/foundation.dart';

import '../engine/presets.dart';
import '../engine/slice_settings.dart';
import 'json_store.dart';

/// The user's own presets, next to the built-in ones.
class PresetStore {
  PresetStore(this.store);

  final JsonStore store;
  final custom = ValueNotifier<List<SlicePreset>>(const []);
  static const _name = 'presets';
  static const maxName = 40;

  List<SlicePreset> get all => [...builtInPresets, ...custom.value];

  SlicePreset? byId(String? id) {
    if (id == null) return null;
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  Future<void> load() async {
    final json = await store.read(_name);
    if (json is! List) return;
    final seen = <String>{for (final p in builtInPresets) p.id};
    custom.value = List.unmodifiable([
      for (final item in json)
        if (SlicePreset.fromJson(item) case final preset? when seen.add(preset.id)) preset,
    ]);
  }

  /// Saves the current settings as a new preset.
  Future<SlicePreset> save(String name, SliceSettings settings) async {
    final preset = SlicePreset(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: _clean(name),
      description: 'Eigenes Preset',
      processId: settings.processId,
      values: settings.values,
      speedPercent: settings.speedPercent,
    );
    await _write([...custom.value, preset]);
    return preset;
  }

  Future<void> rename(String id, String name) =>
      _write([for (final p in custom.value) p.id == id ? p.renamed(_clean(name)) : p]);

  Future<void> delete(String id) => _write([for (final p in custom.value) if (p.id != id) p]);

  String _clean(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Name fehlt');
    return trimmed.length > maxName ? trimmed.substring(0, maxName) : trimmed;
  }

  Future<void> _write(List<SlicePreset> next) async {
    custom.value = List.unmodifiable(next);
    await store.write(_name, [for (final p in next) p.toJson()]);
  }
}

/// "Technisch und stabil", "Technisch und stabil · angepasst" or "Eigene Einstellungen".
String presetLabel(SliceSettings settings, PresetStore presets) {
  final preset = presets.byId(settings.presetId);
  if (preset == null) return 'Eigene Einstellungen';
  return preset.matches(settings) ? preset.name : '${preset.name} · angepasst';
}
