import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../engine/profile_catalog.dart';
import '../engine/setting_defs.dart';
import '../engine/slice_settings.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_choice.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_route.dart';
import '../ui/pixel_slider.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/pixel_toggle.dart';
import '../util/format.dart';
import 'preset_widgets.dart';
import 'settings_browser_screen.dart' show SettingsBrowserScreen, SpeedSlider;

/// Layer height, infill, walls, speed, support, brim, fuzzy skin and filament, plus the way to all settings.
/// Shared by the desktop sidebar and the phone layout.
class QuickSettingsPanel extends StatelessWidget {
  const QuickSettingsPanel({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ValueListenableBuilder<SliceSettings>(
      valueListenable: services.settings,
      builder: (context, settings, _) => _panel(context, services, settings),
    );
  }

  Widget _panel(BuildContext context, AppServices services, SliceSettings settings) {
    void update(SliceSettings Function(SliceSettings) change) => services.settings.value = change(services.settings.value);
    void set(String key, Object? value) =>
        update((s) => s.withValue(key, value, profileValue: s.profileValue(settingDef(key)!, services.profile)));

    final catalog = services.catalog;
    final profile = services.profile;
    final processes = catalog.processes;
    final processIndex = processes.indexWhere((p) => p.id == settings.processId).clamp(0, processes.length - 1);
    final supportOn = settings.effectiveKey('enable_support', profile) == true;
    final support = !supportOn ? 'off' : ('${settings.effectiveKey('support_type', profile)}'.startsWith('tree') ? 'tree' : 'normal');
    final brim = '${settings.effectiveKey('brim_type', profile)}';
    final fuzzy = settings.effectiveKey('fuzzy_skin', profile) != 'none';
    final changed = settings.changedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PixelText.small('PRESET', color: PixelColors.muted),
        const PixelGap(1),
        PresetStrip(enabled: enabled),
        const PixelGap(1),
        PresetStatus(enabled: enabled),
        const PixelGap(4),
        PixelPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                PixelIcon(PixelIcons.gear, scale: 1),
                const PixelGap(2),
                const Expanded(child: PixelText.heading('Schnelleinstellungen')),
              ]),
              const PixelGap(4),
              PixelSlider(
                label: 'Schichthöhe',
                value: processIndex.toDouble(),
                min: 0,
                max: (processes.length - 1).toDouble(),
                divisions: processes.length - 1,
                format: (v) {
                  final p = processes[v.round()];
                  return '${decimal(p.layerHeight, 2)} mm · ${p.label}';
                },
                unit: 'mm',
                inputDigits: 2,
                detail: (v) => processes[v.round()].label,
                toInput: (v) => processes[v.round()].layerHeight,
                fromInput: (mm) => nearestProcess(processes, mm).toDouble(),
                onChanged: enabled ? (v) => update((s) => s.copyWith(processId: processes[v.round()].id)) : null,
              ),
              const PixelGap(3),
              PixelSlider(
                label: 'Füllung',
                value: (settings.effectiveKey('sparse_infill_density', profile) as double).clamp(0, 100),
                min: 0,
                max: 100,
                divisions: 20,
                format: (v) => '${v.round()} %',
                unit: '%',
                onChanged: enabled ? (v) => set('sparse_infill_density', v.roundToDouble()) : null,
              ),
              const PixelGap(3),
              PixelSlider(
                label: 'Wände',
                value: (settings.effectiveKey('wall_loops', profile) as int).clamp(1, 6).toDouble(),
                min: 1,
                max: 6,
                divisions: 5,
                onChanged: enabled ? (v) => set('wall_loops', v.round()) : null,
              ),
              const PixelGap(3),
              SpeedSlider(settings: settings, onChanged: enabled ? (v) => update((s) => s.copyWith(speedPercent: v)) : null),
              const PixelGap(4),
              const PixelText('Stützen'),
              const PixelGap(1),
              PixelSegmented<String>(
                options: const [PixelOption('off', 'Aus'), PixelOption('normal', 'Normal'), PixelOption('tree', 'Baum')],
                value: support,
                onChanged: enabled
                    ? (m) {
                        set('enable_support', m != 'off');
                        if (m != 'off') set('support_type', m == 'tree' ? 'tree(auto)' : 'normal(auto)');
                      }
                    : null,
              ),
              if (supportOn)
                PixelToggle(
                  label: 'Nur vom Druckbett aus',
                  subtitle: 'Keine Stützen, die auf dem Modell stehen',
                  value: settings.effectiveKey('support_on_build_plate_only', profile) == true,
                  onChanged: enabled ? (v) => set('support_on_build_plate_only', v) : null,
                ),
              const PixelGap(4),
              const PixelText('Rand (Brim)'),
              const PixelGap(1),
              PixelSegmented<String>(
                options: const [PixelOption('auto_brim', 'Auto'), PixelOption('no_brim', 'Aus'), PixelOption('outer_only', 'Außen')],
                value: brim,
                onChanged: enabled ? (m) => set('brim_type', m) : null,
              ),
              const PixelGap(2),
              PixelToggle(
                label: 'Fuzzy Skin',
                subtitle: 'Raue, griffige Außenwand',
                value: fuzzy,
                onChanged: enabled ? (v) => set('fuzzy_skin', v ? 'external' : 'none') : null,
              ),
              const PixelGap(4),
              Row(children: [
                PixelIcon(PixelIcons.spool, scale: 1),
                const PixelGap(2),
                const PixelText('Filament'),
              ]),
              const PixelGap(1),
              PixelChoiceList<String>(
                options: [
                  for (final f in catalog.filaments)
                    PixelOption(f.id, f.label, subtitle: '${f.type} · Düse ${f.nozzleTemp} °C · Bett ${f.bedTemp} °C'),
                ],
                value: settings.filamentId,
                onChanged: enabled ? (id) => update((s) => s.copyWith(filamentId: id)) : null,
              ),
              const PixelGap(4),
              PixelButton(
                label: changed == 0 ? 'Alle Einstellungen' : 'Alle Einstellungen · $changed geändert',
                icon: PixelIcons.search,
                style: PixelButtonStyle.primary,
                expand: true,
                onPressed: enabled ? () => Navigator.of(context).push(PixelRoute<void>(builder: (_) => const SettingsBrowserScreen())) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Index of the profile whose layer height is closest to [mm].
int nearestProcess(List<ProcessProfile> processes, double mm) {
  var best = 0;
  for (var i = 1; i < processes.length; i++) {
    if ((processes[i].layerHeight - mm).abs() < (processes[best].layerHeight - mm).abs()) best = i;
  }
  return best;
}
