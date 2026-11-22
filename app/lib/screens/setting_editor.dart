import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../engine/setting_defs.dart';
import '../engine/setting_search.dart';
import '../engine/slice_settings.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_choice.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_sheet.dart';
import '../ui/pixel_slider.dart';
import '../ui/pixel_stepper.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/pixel_toggle.dart';

/// Opens the editor for one setting; changes apply right away.
Future<void> showSettingEditor(BuildContext context, SettingDef def) {
  final services = AppScope.of(context);
  return showPixelSheet<void>(
    context,
    title: def.label,
    icon: def.category.glyph,
    builder: (context) => AppScope(services: services, child: SettingEditor(def: def)),
  );
}

/// The control for [def] (switch, choice, slider and stepper), its help text and the profile value.
class SettingEditor extends StatelessWidget {
  const SettingEditor({super.key, required this.def});

  final SettingDef def;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final profile = services.profile;
    return ValueListenableBuilder<SliceSettings>(
      valueListenable: services.settings,
      builder: (context, settings, _) {
        final profileValue = settings.profileValue(def, profile);
        final value = settings.effective(def, profile);
        final changed = settings.isChanged(def.key);
        void set(Object? next) =>
            services.settings.value = services.settings.value.withValue(def.key, next, profileValue: profileValue);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PixelText(def.help, color: PixelColors.muted),
            const PixelGap(4),
            _control(value, set),
            const PixelGap(4),
            PixelPanel(
              color: PixelColors.background,
              shadow: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const PixelText.small('Profilwert', color: PixelColors.muted),
                        PixelText(formatSettingValue(def, profileValue)),
                      ],
                    ),
                  ),
                  if (changed) const PixelText.small('geändert', color: PixelColors.accent),
                ],
              ),
            ),
            const PixelGap(3),
            PixelButton(
              label: 'Auf Profilwert zurücksetzen',
              expand: true,
              onPressed: changed ? () => set(null) : null,
            ),
            if (def.scalesWithSpeed && settings.speedPercent != 100 && !changed) ...[
              const PixelGap(2),
              PixelText.small(
                'Wird mit dem Geschwindigkeitsregler auf ${settings.speedPercent} % skaliert, solange du den Wert nicht einzeln setzt.',
                color: PixelColors.muted,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _control(Object value, ValueChanged<Object?> set) {
    switch (def.kind) {
      case SettingKind.toggle:
        return PixelToggle(label: def.label, value: value == true, onChanged: set);
      case SettingKind.choice:
        final known = def.choices.any((c) => c.value == value);
        return PixelChoiceList<String>(
          options: [
            for (final c in def.choices) PixelOption(c.value, c.label),
            if (!known) PixelOption('$value', '$value (aus dem Profil)'),
          ],
          value: '$value',
          onChanged: set,
        );
      case SettingKind.integer:
      case SettingKind.decimal:
      case SettingKind.percent:
        final number = (value as num).toDouble();
        final min = def.min.toDouble();
        final max = def.max.toDouble();
        final step = def.step.toDouble();
        final divisions = ((max - min) / step).round();
        Object typed(double v) => def.kind == SettingKind.integer ? v.round() : v;
        String format(double v) => formatSettingValue(def, typed(v));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PixelStepper(
              label: def.label,
              value: number,
              min: number < min ? number : min,
              max: number > max ? number : max,
              step: step,
              format: format,
              onChanged: (v) => set(typed(v)),
            ),
            if (divisions <= 200) ...[
              const PixelGap(3),
              PixelSlider(
                label: 'Grob einstellen',
                value: number.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                format: format,
                unit: def.unit,
                onChanged: (v) => set(typed(double.parse(v.toStringAsFixed(6)))),
              ),
            ],
          ],
        );
    }
  }
}
