import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../data/preset_store.dart';
import '../engine/presets.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_sheet.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_text_field.dart';
import '../ui/pixel_theme.dart';

void applyPreset(BuildContext context, SlicePreset preset) {
  final services = AppScope.of(context);
  services.settings.value = preset.applyTo(services.settings.value, services.catalog);
  PixelToast.show(context, 'Preset „${preset.name}“ angewendet', kind: PixelToastKind.success);
}

/// Asks for a name and stores the current settings as a custom preset.
Future<void> savePresetFlow(BuildContext context) async {
  final services = AppScope.of(context);
  final name = await _askName(context, title: 'Als Preset speichern', initial: '', action: 'Speichern');
  if (name == null) return;
  final preset = await services.presets.save(name, services.settings.value);
  services.settings.value = services.settings.value.copyWith(presetId: () => preset.id);
  if (context.mounted) PixelToast.show(context, 'Preset „${preset.name}“ gespeichert', kind: PixelToastKind.success);
}

Future<void> renamePresetFlow(BuildContext context, SlicePreset preset) async {
  final services = AppScope.of(context);
  final name = await _askName(context, title: 'Preset umbenennen', initial: preset.name, action: 'Umbenennen');
  if (name != null) await services.presets.rename(preset.id, name);
}

Future<void> deletePresetFlow(BuildContext context, SlicePreset preset) async {
  final services = AppScope.of(context);
  final ok = await showPixelDialog<bool>(
    context,
    title: 'Preset löschen?',
    message: '„${preset.name}“ wird entfernt. Deine aktuellen Einstellungen bleiben, wie sie sind.',
    icon: PixelIcons.trash,
    actions: const [
      PixelDialogAction('Behalten', false),
      PixelDialogAction('Löschen', true, style: PixelButtonStyle.danger),
    ],
  );
  if (ok != true) return;
  await services.presets.delete(preset.id);
  if (services.settings.value.presetId == preset.id) {
    services.settings.value = services.settings.value.copyWith(presetId: () => null);
  }
}

Future<String?> _askName(BuildContext context, {required String title, required String initial, required String action}) =>
    showPixelSheet<String>(
      context,
      title: title,
      icon: PixelIcons.save,
      builder: (context) => _NameForm(initial: initial, action: action),
    );

class _NameForm extends StatefulWidget {
  const _NameForm({required this.initial, required this.action});

  final String initial;
  final String action;

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bitte einen Namen eingeben');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PixelTextField(
            controller: _controller,
            label: 'Name',
            hint: 'z. B. Halterung PETG',
            errorText: _error,
            inputFormatters: [LengthLimitingTextInputFormatter(PresetStore.maxName)],
            onSubmitted: (_) => _submit(),
          ),
          const PixelGap(4),
          PixelButton(label: widget.action, style: PixelButtonStyle.primary, expand: true, onPressed: _submit),
        ],
      );
}

/// Rebuilds when the settings or the custom presets change.
class _PresetListener extends StatelessWidget {
  const _PresetListener({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(listenable: Listenable.merge([services.settings, services.presets.custom]), builder: (context, _) => builder(context));
  }
}

/// "Preset: Technisch · angepasst" with a restore button while the settings differ from the preset.
class PresetStatus extends StatelessWidget {
  const PresetStatus({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) => _PresetListener(builder: (context) {
        final services = AppScope.of(context);
        final settings = services.settings.value;
        final preset = services.presets.byId(settings.presetId);
        final modified = preset != null && !preset.matches(settings);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelText.small('Aktiv: ${presetLabel(settings, services.presets)}', color: modified ? PixelColors.yellow : PixelColors.muted),
            if (modified) ...[
              const PixelGap(2),
              PixelButton(
                label: 'Preset wiederherstellen',
                icon: PixelIcons.back,
                expand: true,
                onPressed: enabled ? () => applyPreset(context, preset) : null,
              ),
            ],
          ],
        );
      });
}

/// Horizontally scrolling preset tiles, the first thing to pick on the model screen.
class PresetStrip extends StatelessWidget {
  const PresetStrip({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context) => _PresetListener(builder: (context) {
        final services = AppScope.of(context);
        final current = services.settings.value.presetId;
        return SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final preset in services.presets.all) ...[
                _PresetTile(
                  preset: preset,
                  selected: preset.id == current,
                  onTap: enabled ? () => applyPreset(context, preset) : null,
                ),
                const PixelGap(2),
              ],
            ],
          ),
        );
      });
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.selected, required this.onTap});

  final SlicePreset preset;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'Preset ${preset.name}',
        hint: preset.description,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            width: 104,
            child: PixelPanel(
              borderColor: selected ? PixelColors.accent : PixelColors.shadow,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PixelIcon(preset.glyph, scale: 2, secondColor: selected ? PixelColors.accent : PixelColors.muted),
                  const PixelGap(1),
                  PixelText.small(preset.name, align: TextAlign.center, maxLines: 2, color: selected ? PixelColors.accent : PixelColors.text),
                ],
              ),
            ),
          ),
        ),
      );
}

/// One preset as a list row; custom presets get rename and delete buttons.
class PresetRow extends StatelessWidget {
  const PresetRow({super.key, required this.preset, required this.selected});

  final SlicePreset preset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Preset ${preset.name}',
              hint: preset.description,
              excludeSemantics: true,
              onTap: () => applyPreset(context, preset),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  applyPreset(context, preset);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: PixelTheme.minTouch + 8),
                  child: Row(
                    children: [
                      PixelIcon(preset.glyph, scale: 2, secondColor: selected ? PixelColors.accent : PixelColors.muted),
                      const PixelGap(3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PixelText(preset.name, color: selected ? PixelColors.accent : PixelColors.text),
                            PixelText.small(
                              [preset.description, preset.summary(services.catalog)].where((t) => t.isNotEmpty).join(' · '),
                              color: PixelColors.muted,
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!preset.builtIn) ...[
            const PixelGap(2),
            PixelIconButton(icon: PixelIcons.pencil, label: '${preset.name} umbenennen', onPressed: () => renamePresetFlow(context, preset)),
            const PixelGap(2),
            PixelIconButton(icon: PixelIcons.trash, label: '${preset.name} löschen', onPressed: () => deletePresetFlow(context, preset)),
          ],
        ],
      ),
    );
  }
}
