import '../util/format.dart';
import 'presets.dart';
import 'setting_defs.dart';

/// Lower case without umlauts, so "fullung", "fuellung" and "Füllung" all match.
String foldText(String text) => text
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ae', 'a')
    .replaceAll('oe', 'o')
    .replaceAll('ue', 'u')
    .replaceAll('ß', 'ss');

List<String> _tokens(String query) => foldText(query).split(RegExp(r'[\s_]+')).where((t) => t.isNotEmpty).toList();

final Map<SettingDef, String> _haystacks = {};

String _haystack(SettingDef def) => _haystacks[def] ??=
    foldText('${def.label} ${def.help} ${def.terms} ${def.key.replaceAll('_', ' ')} ${def.key} ${def.category.label} '
        '${def.choices.map((c) => c.label).join(' ')}');

/// Settings whose name, help, search words or key contain every word of [query]; name and category hits first.
List<SettingDef> searchSettings(String query, [Iterable<SettingDef>? defs]) {
  final tokens = _tokens(query);
  if (tokens.isEmpty) return const [];
  final hits = [
    for (final def in defs ?? settingDefs)
      if (tokens.every(_haystack(def).contains)) def,
  ];
  int rank(SettingDef def) {
    final name = foldText('${def.label} ${def.terms}');
    final category = foldText(def.category.label);
    return (tokens.every(name.contains) ? 0 : 4) + (tokens.any(category.contains) ? 0 : 2) + (def.advanced ? 1 : 0);
  }

  // List.sort is not stable; the original index keeps the display order within a rank.
  final order = {for (final (i, def) in hits.indexed) def: i};
  return hits..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : order[a]! - order[b]!);
}

List<SlicePreset> searchPresets(String query, List<SlicePreset> presets) {
  final tokens = _tokens(query);
  if (tokens.isEmpty) return const [];
  return [
    for (final preset in presets)
      if (tokens.every(foldText('${preset.name} ${preset.description} preset vorlage').contains)) preset,
  ];
}

int _digits(num step) {
  if (step >= 1) return 0;
  if (step >= 0.1) return 1;
  if (step >= 0.01) return 2;
  return 3;
}

/// The number part of a value, German style: "0,20", "15", "2".
String formatSettingNumber(SettingDef def, num value) => switch (def.kind) {
      SettingKind.integer => '${value.round()}',
      _ => decimal(value.toDouble(), _digits(def.step)),
    };

/// A value for display: "0,20 mm", "15 %", "An", "Baum".
String formatSettingValue(SettingDef def, Object value) {
  final text = switch (def.kind) {
    SettingKind.toggle => value == true ? 'An' : 'Aus',
    SettingKind.choice => def.choiceLabel('$value'),
    _ => formatSettingNumber(def, value as num),
  };
  if (def.kind == SettingKind.toggle || def.kind == SettingKind.choice || def.unit.isEmpty) return text;
  return '$text ${def.unit}';
}
