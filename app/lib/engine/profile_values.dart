import 'dart:convert';

import 'package:flutter/services.dart';

import 'profile_catalog.dart';
import 'setting_defs.dart';

typedef ProfileMap = Map<String, Object?>;

/// Turns a raw profile entry (`"15%"`, `["220"]`, `"1"`, `"nil"`) into the typed value of [def]; null when unset.
Object? parseSettingValue(SettingDef def, Object? raw) {
  if (raw is List) raw = raw.isEmpty ? null : raw.first;
  if (raw == null) return null;
  if (raw is bool) return def.kind == SettingKind.toggle ? raw : null;
  final text = raw.toString().trim();
  if (text.isEmpty || text == 'nil') return null;
  double? number() => double.tryParse(text.endsWith('%') ? text.substring(0, text.length - 1) : text);
  return switch (def.kind) {
    SettingKind.integer => number()?.round(),
    SettingKind.decimal || SettingKind.percent => number(),
    SettingKind.toggle => switch (text) { '1' || 'true' => true, '0' || 'false' => false, _ => null },
    SettingKind.choice => text,
  };
}

/// Brings a stored or default value into the type [def] expects; null when it does not fit.
Object? normalizeSettingValue(SettingDef def, Object? value) => switch (def.kind) {
      SettingKind.integer => value is num ? value.round() : null,
      SettingKind.decimal || SettingKind.percent => value is num ? value.toDouble() : null,
      SettingKind.toggle => value is bool ? value : null,
      SettingKind.choice => value is String ? value : null,
    };

/// The flattened process, filament and printer profiles, so every setting can show what the profile uses.
class ProfileValues {
  ProfileValues({required this.processes, required this.filaments, required this.printer});

  static Future<ProfileValues> load(ProfileCatalog catalog, [AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    Future<ProfileMap> read(String file) async =>
        (jsonDecode(await assets.loadString('assets/engine/profiles/$file')) as Map).cast<String, Object?>();
    return ProfileValues(
      processes: {for (final p in catalog.processes) p.id: await read(p.file)},
      filaments: {for (final f in catalog.filaments) f.id: await read(f.file)},
      printer: await read('printer.json'),
    );
  }

  final Map<String, ProfileMap> processes;
  final Map<String, ProfileMap> filaments;
  final ProfileMap printer;

  /// The value the bundled profiles (or the engine default) give [def]; null if none of them knows it.
  Object? profileValue(SettingDef def, {required String processId, required String filamentId}) {
    final profile = def.source == SettingSource.process ? processes[processId] : filaments[filamentId];
    final fallback = def.printerFallback;
    return parseSettingValue(def, profile?[def.key]) ??
        (fallback == null ? null : parseSettingValue(def, printer[fallback])) ??
        normalizeSettingValue(def, def.engineDefault);
  }

  /// Like [profileValue], with a type-safe last resort so the UI always has something to show.
  Object valueOf(SettingDef def, {required String processId, required String filamentId}) =>
      profileValue(def, processId: processId, filamentId: filamentId) ??
      switch (def.kind) {
        SettingKind.integer => def.min.round(),
        SettingKind.decimal || SettingKind.percent => def.min.toDouble(),
        SettingKind.toggle => false,
        SettingKind.choice => def.choices.first.value,
      };
}
