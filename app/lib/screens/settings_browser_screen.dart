import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../engine/profile_values.dart';
import '../engine/setting_defs.dart';
import '../engine/setting_search.dart';
import '../engine/slice_settings.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_choice.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_route.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_search_field.dart';
import '../ui/pixel_sheet.dart';
import '../ui/pixel_slider.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/pixel_toggle.dart';
import '../util/format.dart';
import 'preset_widgets.dart';
import 'setting_editor.dart';

/// All slicer settings: presets on top, categories below, search across everything.
class SettingsBrowserScreen extends StatefulWidget {
  const SettingsBrowserScreen({super.key});

  @override
  State<SettingsBrowserScreen> createState() => _SettingsBrowserScreenState();
}

class _SettingsBrowserScreenState extends State<SettingsBrowserScreen> {
  final _search = TextEditingController();
  bool _onlyChanged = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _resetAll() async {
    final services = AppScope.of(context);
    final ok = await showPixelDialog<bool>(
      context,
      title: 'Alles zurücksetzen?',
      message: 'Alle Änderungen und die Geschwindigkeit gehen zurück auf die Profilwerte. Schichthöhe und Filament bleiben.',
      icon: PixelIcons.warning,
      actions: const [
        PixelDialogAction('Abbrechen', false),
        PixelDialogAction('Zurücksetzen', true, style: PixelButtonStyle.danger),
      ],
    );
    if (ok == true) services.settings.value = services.settings.value.reset();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return PixelScaffold(
      title: 'Alle Einstellungen',
      onBack: () => Navigator.of(context).maybePop(),
      body: ListenableBuilder(
        listenable: Listenable.merge([services.settings, services.presets.custom]),
        builder: (context, _) {
          final settings = services.settings.value;
          final query = _search.text.trim();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              PixelSearchField(controller: _search, hint: 'Einstellung oder Preset suchen'),
              PixelToggle(
                label: 'Nur geänderte',
                subtitle: settings.changedCount == 0 ? 'Noch nichts geändert' : '${settings.changedCount} geändert',
                value: _onlyChanged,
                onChanged: (v) => setState(() => _onlyChanged = v),
              ),
              const PixelGap(2),
              if (query.isNotEmpty)
                ..._searchResults(query, settings, services)
              else if (_onlyChanged)
                ..._changedList(settings, services)
              else ...[
                _presetSection(settings, services),
                const PixelGap(5),
                const PixelText.heading('Kategorien'),
                const PixelGap(2),
                _categoryGrid(settings),
                const PixelGap(5),
                PixelButton(
                  label: 'Alles zurücksetzen',
                  icon: PixelIcons.cross,
                  style: PixelButtonStyle.danger,
                  expand: true,
                  onPressed: settings.changedCount == 0 ? null : _resetAll,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _presetSection(SliceSettings settings, AppServices services) => PixelPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              PixelIcon(PixelIcons.star, scale: 1),
              const PixelGap(2),
              const Expanded(child: PixelText.heading('Presets')),
            ]),
            const PixelGap(1),
            const PixelText.small('Ein Preset ist der Startpunkt, danach kannst du alles weiter anpassen.', color: PixelColors.muted),
            const PixelGap(2),
            const PresetStatus(),
            const PixelGap(3),
            for (final preset in services.presets.all) PresetRow(preset: preset, selected: preset.id == settings.presetId),
            const PixelGap(1),
            PixelButton(
              label: 'Aktuelle Einstellungen als Preset speichern',
              icon: PixelIcons.save,
              expand: true,
              onPressed: () => savePresetFlow(context),
            ),
          ],
        ),
      );

  Widget _categoryGrid(SliceSettings settings) {
    final tiles = [for (final category in SettingCategory.values) _CategoryTile(category: category, settings: settings)];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 520 ? 3 : 2;
      final rows = <Widget>[];
      for (var i = 0; i < tiles.length; i += columns) {
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const PixelGap(2),
                Expanded(child: i + c < tiles.length ? tiles[i + c] : const SizedBox.shrink()),
              ],
            ],
          ),
        ));
        rows.add(const PixelGap(2));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }

  List<Widget> _searchResults(String query, SliceSettings settings, AppServices services) {
    final presets = _onlyChanged ? const [] : searchPresets(query, services.presets.all);
    final defs = searchSettings(query).where((d) => !_onlyChanged || settings.isChanged(d.key)).toList();
    if (presets.isEmpty && defs.isEmpty) {
      return [
        const PixelGap(6),
        PixelText('Nichts gefunden für „$query“.', color: PixelColors.muted, align: TextAlign.center),
      ];
    }
    return [
      if (presets.isNotEmpty) ...[
        const PixelText.small('PRESETS', color: PixelColors.muted),
        const PixelGap(1),
        for (final preset in presets) PresetRow(preset: preset, selected: preset.id == settings.presetId),
        const PixelGap(3),
      ],
      if (defs.isNotEmpty) ...[
        PixelText.small('EINSTELLUNGEN (${defs.length})', color: PixelColors.muted),
        const PixelGap(1),
        for (final def in defs) SettingRow(def: def, settings: settings, profile: services.profile, showCategory: true),
      ],
    ];
  }

  List<Widget> _changedList(SliceSettings settings, AppServices services) {
    final defs = [for (final def in settingDefs) if (settings.isChanged(def.key)) def];
    return [
      if (settings.speedPercent != 100)
        PixelText('Geschwindigkeit: ${settings.speedPercent} %', color: PixelColors.accent),
      if (defs.isEmpty && settings.speedPercent == 100)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: PixelText('Alles steht auf den Profilwerten.', color: PixelColors.muted, align: TextAlign.center),
        ),
      for (final def in defs) SettingRow(def: def, settings: settings, profile: services.profile, showCategory: true),
    ];
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.settings});

  final SettingCategory category;
  final SliceSettings settings;

  @override
  Widget build(BuildContext context) {
    final changed = settingsIn(category).where((d) => settings.isChanged(d.key)).length;
    void open() {
      HapticFeedback.selectionClick();
      Navigator.of(context).push(PixelRoute<void>(builder: (_) => SettingsCategoryScreen(category: category)));
    }

    return Semantics(
      button: true,
      label: category.label,
      hint: changed == 0 ? category.summary : '$changed geändert',
      excludeSemantics: true,
      onTap: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: PixelPanel(
          borderColor: changed > 0 ? PixelColors.accent : PixelColors.shadow,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelIcon(category.glyph, scale: 2),
              const PixelGap(2),
              PixelText(category.label, maxLines: 2),
              PixelText.small(
                changed == 0 ? category.summary : '$changed geändert',
                color: changed == 0 ? PixelColors.muted : PixelColors.accent,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One category: basic settings, the advanced ones behind "Mehr anzeigen".
class SettingsCategoryScreen extends StatefulWidget {
  const SettingsCategoryScreen({super.key, required this.category});

  final SettingCategory category;

  @override
  State<SettingsCategoryScreen> createState() => _SettingsCategoryScreenState();
}

class _SettingsCategoryScreenState extends State<SettingsCategoryScreen> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return PixelScaffold(
      title: widget.category.label,
      onBack: () => Navigator.of(context).maybePop(),
      body: ValueListenableBuilder<SliceSettings>(
        valueListenable: services.settings,
        builder: (context, settings, _) {
          final all = settingsIn(widget.category).where((d) => settings.isVisible(d, services.profile)).toList();
          final basic = all.where((d) => !d.advanced).toList();
          final advanced = all.where((d) => d.advanced).toList();
          final changedAdvanced = advanced.where((d) => settings.isChanged(d.key)).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              PixelText.small(widget.category.summary, color: PixelColors.muted),
              const PixelGap(3),
              if (widget.category == SettingCategory.quality) _LayerHeightRow(settings: settings),
              if (widget.category == SettingCategory.speed) _SpeedRow(settings: settings),
              for (final def in basic) SettingRow(def: def, settings: settings, profile: services.profile),
              if (advanced.isNotEmpty) ...[
                const PixelGap(3),
                PixelButton(
                  label: _showAdvanced
                      ? 'Weniger anzeigen'
                      : 'Mehr anzeigen (${advanced.length}${changedAdvanced > 0 ? ', $changedAdvanced geändert' : ''})',
                  expand: true,
                  onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                ),
                if (_showAdvanced) ...[
                  const PixelGap(3),
                  for (final def in advanced) SettingRow(def: def, settings: settings, profile: services.profile),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Name, current value and a dot when the value differs from the profile.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.def, required this.settings, required this.profile, this.showCategory = false});

  final SettingDef def;
  final SliceSettings settings;
  final ProfileValues profile;
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final changed = settings.isChanged(def.key);
    final value = formatSettingValue(def, settings.effective(def, profile));
    return _Row(
      label: def.label,
      value: value,
      changed: changed,
      hint: showCategory ? def.category.label : null,
      onTap: () => showSettingEditor(context, def),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.changed, required this.onTap, this.hint});

  final String label;
  final String value;
  final bool changed;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return Semantics(
      button: true,
      label: '$label: $value${changed ? ', geändert' : ''}',
      hint: hint,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: PixelTheme.minTouch + 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: PixelColors.panel, width: 2))),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: changed ? const _ChangedDot() : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelText(label),
                    if (hint != null) PixelText.small(hint, color: PixelColors.muted),
                  ],
                ),
              ),
              const PixelGap(2),
              Flexible(
                child: PixelText(value, color: changed ? PixelColors.accent : PixelColors.muted, align: TextAlign.right, maxLines: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangedDot extends StatelessWidget {
  const _ChangedDot();

  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(dimension: 8, child: ColoredBox(color: PixelColors.accent)),
      );
}

/// Layer height is the process profile choice, shown at the top of "Qualität".
class _LayerHeightRow extends StatelessWidget {
  const _LayerHeightRow({required this.settings});

  final SliceSettings settings;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final process = services.catalog.process(settings.processId);
    return _Row(
      label: 'Schichthöhe',
      value: '${decimal(process.layerHeight, 2)} mm',
      changed: false,
      onTap: () => showPixelSheet<void>(
        context,
        title: 'Schichthöhe',
        icon: PixelIcons.layers,
        builder: (context) => ValueListenableBuilder<SliceSettings>(
          valueListenable: services.settings,
          builder: (context, settings, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const PixelText('Dünnere Schichten zeigen feinere Details, der Druck dauert aber länger. Wählt das Prozessprofil.',
                  color: PixelColors.muted),
              const PixelGap(3),
              PixelChoiceList<String>(
                options: [
                  for (final p in services.catalog.processes) PixelOption(p.id, '${decimal(p.layerHeight, 2)} mm', subtitle: p.label),
                ],
                value: settings.processId,
                onChanged: (id) => services.settings.value = services.settings.value.copyWith(processId: id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The overall speed percentage, shown at the top of "Geschwindigkeit".
class _SpeedRow extends StatelessWidget {
  const _SpeedRow({required this.settings});

  final SliceSettings settings;

  @override
  Widget build(BuildContext context) => _Row(
        label: 'Geschwindigkeit gesamt',
        value: '${settings.speedPercent} %',
        changed: settings.speedPercent != 100,
        onTap: () => showSpeedEditor(context),
      );
}

/// Sheet with the overall speed slider; also used by the model screen.
Future<void> showSpeedEditor(BuildContext context) {
  final services = AppScope.of(context);
  return showPixelSheet<void>(
    context,
    title: 'Geschwindigkeit',
    icon: PixelIcons.speed,
    builder: (context) => ValueListenableBuilder<SliceSettings>(
      valueListenable: services.settings,
      builder: (context, settings, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PixelText(
            'Skaliert Wände, Füllung, Oberseiten, Lücken und Stützen. Erste Schicht, Brücken, Überhänge und Leerfahrten bleiben. '
            'Einzeln gesetzte Geschwindigkeiten gelten weiter. Nach oben begrenzt der maximale Volumenfluss des Filaments.',
            color: PixelColors.muted,
          ),
          const PixelGap(4),
          SpeedSlider(settings: settings, onChanged: (v) => services.settings.value = services.settings.value.copyWith(speedPercent: v)),
          const PixelGap(3),
          PixelButton(
            label: 'Auf 100 % zurücksetzen',
            expand: true,
            onPressed: settings.speedPercent == 100 ? null : () => services.settings.value = services.settings.value.copyWith(speedPercent: 100),
          ),
        ],
      ),
    ),
  );
}

class SpeedSlider extends StatelessWidget {
  const SpeedSlider({super.key, required this.settings, required this.onChanged});

  final SliceSettings settings;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return PixelSlider(
      label: 'Geschwindigkeit',
      value: settings.speedPercent.toDouble(),
      min: SliceSettings.minSpeed.toDouble(),
      max: SliceSettings.maxSpeed.toDouble(),
      divisions: (SliceSettings.maxSpeed - SliceSettings.minSpeed) ~/ 5,
      format: (v) => '${v.round()} %',
      unit: '%',
      onChanged: onChanged == null ? null : (v) => onChanged(v.round()),
    );
  }
}
