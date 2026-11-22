import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/engine/profile_catalog.dart';
import 'package:mobile_slice/engine/setting_defs.dart';
import 'package:mobile_slice/engine/slice_settings.dart';

import 'setting_defs_test.dart' show bundledValues, expectValidValue, orcaKeys;

ProfileCatalog bundledCatalog() => ProfileCatalog.fromJson(
      jsonDecode(File('assets/engine/profiles/catalog.json').readAsStringSync()) as Map<String, Object?>,
    );

void main() {
  group('ProfileCatalog', () {
    final catalog = bundledCatalog();

    test('liest den mitgelieferten Katalog', () {
      expect(catalog.printer.modelId, 'C12');
      expect(catalog.printer.bedX, 256);
      expect(catalog.processes.map((p) => p.id), ['0.08', '0.12', '0.16', '0.20', '0.24', '0.28']);
      expect(catalog.filaments, hasLength(7));
      expect(catalog.process('0.08').layerHeight, closeTo(0.08, 1e-9));
      expect(catalog.filament('generic-petg').type, 'PETG');
    });

    test('alle Profildateien existieren', () {
      for (final file in [...catalog.processes.map((p) => p.file), ...catalog.filaments.map((f) => f.file)]) {
        expect(File('assets/engine/profiles/$file').existsSync(), isTrue, reason: file);
      }
    });

    test('unbekannte IDs fallen auf den Standard zurück', () {
      expect(catalog.process('9.99').id, catalog.defaultProcess);
      expect(catalog.filament('gibtsnicht').id, catalog.defaultFilament);
    });

    test('Farben', () {
      expect(parseHexColor('#FF8A3D'), const Color(0xFFFF8A3D));
      expect(parseHexColor('kaputt'), const Color(0xFFFFFFFF));
    });
  });


  group('SliceSettings', () {
    final catalog = bundledCatalog();
    final profile = bundledValues(catalog);
    final keys = orcaKeys();
    final base = SliceSettings.defaults(catalog);

    test('Standard schickt keine Änderungen', () {
      expect(base.overrides(profile), isEmpty);
      expect(base.changedCount, 0);
      expect(base.presetId, 'standard');
      expect(base.effectiveKey('sparse_infill_density', profile), 15.0);
      expect(base.effectiveKey('wall_loops', profile), 2);
    });

    test('Werte werden zu Engine-Text', () {
      final settings = base
          .withValue('sparse_infill_density', 40.0)
          .withValue('wall_loops', 4)
          .withValue('enable_support', true)
          .withValue('support_type', 'tree(auto)')
          .withValue('fuzzy_skin', 'external')
          .withValue('fuzzy_skin_thickness', 0.3)
          .withValue('nozzle_temperature', 230);
      expect(settings.overrides(profile), {
        'sparse_infill_density': '40%',
        'wall_loops': '4',
        'enable_support': '1',
        'support_type': 'tree(auto)',
        'fuzzy_skin': 'external',
        'fuzzy_skin_thickness': '0.3',
        'nozzle_temperature': '230',
      });
      expect(settings.changedCount, 7);
      for (final MapEntry(:key, :value) in settings.values.entries) {
        expectValidValue(keys, key, value);
      }
    });

    test('Profilwert oder null setzt zurück', () {
      final changed = base.withValue('wall_loops', 5);
      expect(changed.isChanged('wall_loops'), isTrue);
      expect(changed.withValue('wall_loops', 2, profileValue: 2).isChanged('wall_loops'), isFalse);
      expect(changed.withValue('wall_loops', null).values, isEmpty);
    });

    test('Geschwindigkeit skaliert Druckgeschwindigkeiten außer einzeln gesetzten', () {
      final fast = base.copyWith(speedPercent: 150).withValue('outer_wall_speed', 120.0);
      final overrides = fast.overrides(profile);
      expect(overrides['outer_wall_speed'], '120');
      expect(overrides['inner_wall_speed'], '450');
      expect(overrides['sparse_infill_speed'], '405');
      expect(overrides.containsKey('travel_speed'), isFalse);
      expect(overrides.containsKey('initial_layer_speed'), isFalse);
      expect(overrides.containsKey('bridge_speed'), isFalse);
      expect(fast.changedCount, 2);
      final slow = base.copyWith(speedPercent: 80).overrides(profile);
      expect(slow['top_surface_speed'], '160');
      expect(slow['gap_infill_speed'], '200');
    });

    test('Sichtbarkeit hängt an anderen Einstellungen', () {
      final thickness = settingDef('fuzzy_skin_thickness')!;
      expect(base.isVisible(thickness, profile), isFalse);
      expect(base.withValue('fuzzy_skin', 'external').isVisible(thickness, profile), isTrue);
      expect(base.isVisible(settingDef('wall_loops')!, profile), isTrue);
    });

    test('JSON hin und zurück, unbekannte und kaputte Werte fallen weg', () {
      final settings = base.copyWith(processId: '0.08', speedPercent: 130, presetId: () => 'technical').withValue('wall_loops', 4);
      expect(SliceSettings.fromJson(settings.toJson(), catalog), settings);
      final broken = SliceSettings.fromJson({
        'processId': 'x',
        'values': {'wall_loops': 'viele', 'gibtsnicht': 3, 'spiral_mode': true},
        'speedPercent': 999,
      }, catalog);
      expect(broken.processId, catalog.defaultProcess);
      expect(broken.values, {'spiral_mode': true});
      expect(broken.speedPercent, SliceSettings.maxSpeed);
    });

    test('alte Einstellungen werden übernommen', () {
      final old = SliceSettings.fromJson({
        'processId': '0.12',
        'filamentId': 'generic-petg',
        'infill': 25,
        'walls': 3,
        'support': 'tree',
        'supportOnPlateOnly': true,
        'brim': 'off',
      }, catalog);
      expect(old.processId, '0.12');
      expect(old.values, {
        'sparse_infill_density': 25.0,
        'wall_loops': 3,
        'enable_support': true,
        'support_type': 'tree(auto)',
        'support_on_build_plate_only': true,
        'brim_type': 'no_brim',
      });
      final untouched = SliceSettings.fromJson({'processId': '0.20', 'support': 'off', 'brim': 'auto'}, catalog);
      expect(untouched.values, isEmpty);
      expect(untouched.presetId, 'standard');
    });

    test('Zurücksetzen behält Schichthöhe und Filament', () {
      final reset = base.copyWith(processId: '0.12', filamentId: 'generic-abs', speedPercent: 70).withValue('wall_loops', 6).reset();
      expect(reset.values, isEmpty);
      expect(reset.speedPercent, 100);
      expect(reset.processId, '0.12');
      expect(reset.filamentId, 'generic-abs');
    });
  });
}
