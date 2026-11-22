import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/data/json_store.dart';
import 'package:mobile_slice/data/preset_store.dart';
import 'package:mobile_slice/engine/presets.dart';
import 'package:mobile_slice/engine/slice_settings.dart';
import 'package:mobile_slice/ui/pixel_icons.dart';

import 'setting_defs_test.dart' show bundledCatalog, bundledValues, expectValidValue, orcaKeys;

void main() {
  final catalog = bundledCatalog();
  final profile = bundledValues(catalog);
  final keys = orcaKeys();
  final base = SliceSettings.defaults(catalog);

  test('eingebaute Presets nutzen nur gültige Schlüssel und Werte', () {
    expect(builtInPresets, hasLength(9));
    expect(builtInPresets.map((p) => p.id).toSet(), hasLength(9));
    for (final preset in builtInPresets) {
      for (final MapEntry(:key, :value) in preset.values.entries) {
        expectValidValue(keys, key, value);
      }
      if (preset.processId != null) expect(catalog.process(preset.processId!).id, preset.processId, reason: preset.id);
      expect(PixelIcons.all.map((g) => g.name), contains(preset.glyphName), reason: preset.id);
      // Overrides must convert cleanly as well.
      expect(() => preset.applyTo(base, catalog).overrides(profile), returnsNormally);
    }
  });

  test('Anwenden ersetzt Schichthöhe, Werte und Tempo, Filament bleibt', () {
    final start = base.copyWith(filamentId: 'generic-petg').withValue('nozzle_temperature', 250);
    final thin = builtInPreset('thin_walls')!.applyTo(start, catalog);
    expect(thin.processId, '0.12');
    expect(thin.filamentId, 'generic-petg');
    expect(thin.speedPercent, 80);
    expect(thin.values, {'wall_generator': 'arachne', 'detect_thin_wall': true});
    expect(thin.presetId, 'thin_walls');

    final fuzzy = builtInPreset('fuzzy')!.applyTo(thin, catalog);
    expect(fuzzy.processId, '0.12', reason: 'Fuzzy behält die Schichthöhe');
    expect(fuzzy.speedPercent, 100);
  });

  test('angepasst wird erkannt und lässt sich wiederherstellen', () {
    final presets = PresetStore(JsonStore(Directory.systemTemp.createTempSync('presets')));
    final technical = builtInPreset('technical')!;
    final applied = technical.applyTo(base, catalog);
    expect(presetLabel(applied, presets), 'Technisch und stabil');
    final tweaked = applied.withValue('wall_loops', 6);
    expect(technical.matches(tweaked), isFalse);
    expect(presetLabel(tweaked, presets), 'Technisch und stabil · angepasst');
    expect(technical.matches(technical.applyTo(tweaked, catalog)), isTrue);
    expect(presetLabel(tweaked.copyWith(presetId: () => null), presets), 'Eigene Einstellungen');
    expect(presetLabel(base, presets), 'Standard');
  });

  test('eigene Presets speichern, umbenennen, löschen und neu laden', () async {
    final dir = Directory.systemTemp.createTempSync('presets');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = JsonStore(dir);
    final presets = PresetStore(store);
    final settings = base.copyWith(processId: '0.16', speedPercent: 120).withValue('wall_loops', 3);
    final saved = await presets.save('  Mein Halter  ', settings);
    expect(saved.name, 'Mein Halter');
    expect(saved.matches(settings), isTrue);
    expect(presets.all, hasLength(10));
    await presets.rename(saved.id, 'Halter v2');
    expect(presets.byId(saved.id)!.name, 'Halter v2');
    expect(() => presets.save('   ', settings), throwsArgumentError);

    final reloaded = PresetStore(store);
    await reloaded.load();
    final again = reloaded.byId(saved.id)!;
    expect(again.name, 'Halter v2');
    expect(again.processId, '0.16');
    expect(again.values, {'wall_loops': 3});
    expect(again.speedPercent, 120);
    expect(again.applyTo(base, catalog).presetId, saved.id);

    await reloaded.delete(saved.id);
    final empty = PresetStore(store);
    await empty.load();
    expect(empty.custom.value, isEmpty);
  });

  test('beim Laden werden unbekannte Schlüssel und kaputte Einträge bereinigt', () async {
    final dir = Directory.systemTemp.createTempSync('presets');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = JsonStore(dir);
    await store.write('presets', [
      {'id': 'custom-1', 'name': 'Alt', 'values': {'wall_loops': 3, 'gibtsnicht': 1, 'spiral_mode': 'ja'}, 'speedPercent': 10},
      {'id': 'standard', 'name': 'Doppelt'},
      {'name': 'ohne id'},
      'Müll',
    ]);
    final presets = PresetStore(store);
    await presets.load();
    expect(presets.custom.value, hasLength(1));
    final old = presets.custom.value.single;
    expect(old.values, {'wall_loops': 3});
    expect(old.speedPercent, SliceSettings.minSpeed);
    expect(old.processId, isNull);
  });
}
