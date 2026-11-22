import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/engine/presets.dart';
import 'package:mobile_slice/engine/setting_defs.dart';
import 'package:mobile_slice/engine/setting_search.dart';

void main() {
  List<String> keys(String query) => searchSettings(query).map((d) => d.key).toList();

  test('Umlaute und Großschreibung spielen keine Rolle', () {
    expect(foldText('Füllung ÜBERHANG Größe'), 'fullung uberhang grosse');
    expect(keys('fullung').first, 'sparse_infill_density');
    expect(keys('FUELLUNG'), keys('füllung'));
    expect(keys('Füllmuster'), contains('sparse_infill_pattern'));
  });

  test('Treffer im Namen zuerst, Hilfetext, Suchbegriffe und Schlüssel zählen auch', () {
    expect(keys('wände').first, 'wall_loops');
    expect(keys('stringing'), contains('filament_retraction_length'), reason: 'Suchbegriff');
    expect(keys('sparse_infill_density'), ['sparse_infill_density'], reason: 'Schlüssel');
    expect(keys('Schichtlinien'), contains('fuzzy_skin'), reason: 'Hilfetext');
    expect(keys('fuzzy'), containsAll(['fuzzy_skin', 'fuzzy_skin_thickness']));
  });

  test('alle Wörter müssen passen, leere Suche findet nichts', () {
    expect(keys('fuzzy dicke'), ['fuzzy_skin_thickness']);
    expect(keys('   '), isEmpty);
    expect(keys('xyzzy'), isEmpty);
  });

  test('Presets sind suchbar', () {
    expect(searchPresets('technisch', builtInPresets).map((p) => p.id), ['technical']);
    expect(searchPresets('dunne wande', builtInPresets).map((p) => p.id), ['thin_walls']);
    expect(searchPresets('', builtInPresets), isEmpty);
  });

  test('Werte werden deutsch formatiert', () {
    expect(formatSettingValue(settingDef('initial_layer_print_height')!, 0.2), '0,20 mm');
    expect(formatSettingValue(settingDef('sparse_infill_density')!, 15.0), '15 %');
    expect(formatSettingValue(settingDef('wall_loops')!, 3), '3');
    expect(formatSettingValue(settingDef('enable_support')!, true), 'An');
    expect(formatSettingValue(settingDef('support_type')!, 'tree(auto)'), 'Baum');
    expect(formatSettingValue(settingDef('nozzle_temperature')!, 220), '220 °C');
    expect(formatSettingValue(settingDef('filament_flow_ratio')!, 0.98), '0,98');
  });
}
