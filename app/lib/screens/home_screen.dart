import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../app_shell.dart';
import '../data/print_history.dart';
import '../data/stats.dart';
import '../engine/slicer_channel.dart';
import '../printer/bambu_printer.dart';
import '../printer/printer_status.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_progress.dart';
import '../ui/pixel_route.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/stat_tile.dart';
import '../util/format.dart';
import 'model_screen.dart';
import 'settings_screen.dart';

/// "Werkstatt": open a model, reopen a recent one, glance at the printer.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static Future<void> openModel(BuildContext context) async {
    final services = AppScope.of(context);
    try {
      final picked = await services.slicer.pickModel();
      if (picked == null || !context.mounted) return;
      await open(context, picked);
    } on PlatformException catch (e) {
      if (context.mounted) PixelToast.show(context, e.message ?? e.code, kind: PixelToastKind.error);
    }
  }

  static Future<void> open(BuildContext context, PickedModel model) async {
    final services = AppScope.of(context);
    if (model.path.startsWith(services.recent.modelsDir.path)) await services.recent.add(model);
    if (!context.mounted) return;
    await Navigator.of(context).push(PixelRoute<void>(builder: (_) => ModelScreen(model: model)));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return PixelScaffold(
      title: 'Werkstatt',
      actions: [
        PixelIconButton(
          icon: PixelIcons.gear,
          label: 'Einstellungen',
          onPressed: () => Navigator.of(context).push(PixelRoute<void>(builder: (_) => const SettingsScreen())),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _Hero(),
          const PixelGap(4),
          PixelButton(
            label: 'Modell öffnen',
            icon: PixelIcons.folder,
            style: PixelButtonStyle.primary,
            expand: true,
            onPressed: () => openModel(context),
          ),
          const PixelGap(2),
          PixelButton(
            label: 'Testwürfel ausprobieren',
            icon: PixelIcons.cube,
            expand: true,
            onPressed: () => open(context, services.sampleModel),
          ),
          const PixelGap(4),
          const _MakerWorldPanel(),
          const PixelGap(4),
          const _PrinterTile(),
          const PixelGap(4),
          ValueListenableBuilder<List<PrintRecord>>(
            valueListenable: services.history.records,
            builder: (context, records, _) {
              final stats = PrintStats.from(records);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: StatTile(glyph: PixelIcons.check, value: '${stats.finished}', label: 'Drucke', color: PixelColors.green)),
                  const PixelGap(2),
                  Expanded(child: StatTile(glyph: PixelIcons.spool, value: formatGrams(stats.grams), label: 'Filament')),
                  const PixelGap(2),
                  Expanded(
                    child: StatTile(glyph: PixelIcons.clock, value: '${stats.hours.floor()} h', label: 'Druckzeit', color: PixelColors.yellow),
                  ),
                ],
              );
            },
          ),
          ValueListenableBuilder<List<PickedModel>>(
            valueListenable: services.recent.models,
            builder: (context, models, _) => models.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PixelGap(5),
                      const PixelText.heading('Zuletzt geöffnet'),
                      for (final model in models) ...[
                        const PixelGap(2),
                        PixelButton(label: model.name, icon: PixelIcons.file, expand: true, onPressed: () => open(context, model)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// MakerWorld has no public API, so models come in through Android: download in the browser,
/// then "Öffnen mit" or "Teilen" hands the file to this app (see MainActivity.receive).
class _MakerWorldPanel extends StatelessWidget {
  const _MakerWorldPanel();

  static const url = 'https://makerworld.com/de';

  Future<void> _open(BuildContext context) async {
    try {
      await AppScope.of(context).slicer.openUrl(url);
    } on PlatformException catch (e) {
      if (context.mounted) PixelToast.show(context, e.message ?? 'Browser konnte nicht geöffnet werden', kind: PixelToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) => PixelPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              PixelIcon(PixelIcons.globe, scale: 2, secondColor: PixelColors.green),
              const PixelGap(3),
              const Expanded(child: PixelText.heading('Modelle von MakerWorld')),
            ]),
            const PixelGap(2),
            PixelText(
              AppScope.of(context).slicer.desktop
                  ? 'Lade dort ein Modell als .3mf oder .stl herunter. Dann hier auf „Modell öffnen“ klicken '
                      'und die Datei aus dem Download-Ordner wählen.'
                  : 'Lade dort ein Modell als .3mf oder .stl herunter. Dann in der Download-Meldung oder im Dateimanager '
                      '„Öffnen mit“ oder „Teilen“ wählen und Mobile Slice antippen. Das Modell öffnet sich direkt hier.',
              color: PixelColors.muted,
            ),
            const PixelGap(3),
            PixelButton(label: 'MakerWorld öffnen', icon: PixelIcons.globe, expand: true, onPressed: () => _open(context)),
          ],
        ),
      );
}

/// Small animated cube banner: the playful touch on the start screen.
class _Hero extends StatefulWidget {
  const _Hero();

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true, count: 6);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PixelPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _bob,
              builder: (context, child) =>
                  Transform.translate(offset: Offset(0, -(_bob.value * 2).round() * PixelTheme.unit), child: child),
              child: PixelIcon(PixelIcons.cube, scale: 3),
            ),
            const PixelGap(4),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PixelText.title('Mobile Slice'),
                  PixelText.small('STL oder 3MF öffnen, slicen, ab auf den P1S.', color: PixelColors.muted),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PrinterTile extends StatelessWidget {
  const _PrinterTile();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ValueListenableBuilder<BambuPrinter?>(
      valueListenable: services.printer,
      builder: (context, printer, _) {
        void goToPrinter() => AppShellState.maybeOf(context)?.select(1);
        if (printer == null) {
          return PixelButton(label: 'Drucker einrichten', icon: PixelIcons.printer, expand: true, onPressed: goToPrinter);
        }
        return ValueListenableBuilder<PrinterLink>(
          valueListenable: printer.link,
          builder: (context, link, _) => ValueListenableBuilder<PrinterStatus>(
            valueListenable: printer.status,
            builder: (context, status, _) {
              final online = link.state == LinkState.online;
              final text = online ? (status.isEmpty ? 'Verbunden' : status.state.label) : switch (link.state) {
                LinkState.connecting => 'Verbinde …',
                LinkState.error => link.message ?? 'Fehler',
                _ => 'Nicht verbunden',
              };
              final color = online ? PixelColors.green : (link.state == LinkState.error ? PixelColors.red : PixelColors.muted);
              return Semantics(
                button: true,
                label: '${printer.config.name}: $text',
                excludeSemantics: true,
                onTap: goToPrinter,
                child: GestureDetector(
                  onTap: goToPrinter,
                  child: PixelPanel(
                    borderColor: color,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          PixelIcon(PixelIcons.printer, scale: 1, secondColor: color),
                          const PixelGap(2),
                          Expanded(child: PixelText(printer.config.name, maxLines: 1)),
                          PixelText(text, color: color, maxLines: 1),
                        ]),
                        if (online && status.state.busy) ...[
                          const PixelGap(2),
                          PixelProgressBar(value: status.percent / 100, height: 16, semanticLabel: 'Druckfortschritt'),
                          const PixelGap(1),
                          PixelText.small('${status.percent} % · noch ${formatPrintTime(status.remainingMinutes * 60)}',
                              color: PixelColors.muted),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
