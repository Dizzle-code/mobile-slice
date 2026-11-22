import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../data/app_settings.dart';
import '../data/print_history.dart';
import '../data/stats.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/stat_tile.dart';
import '../util/format.dart';

/// All prints sent from the app plus the totals.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return PixelScaffold(
      title: 'Verlauf',
      body: ValueListenableBuilder<List<PrintRecord>>(
        valueListenable: services.history.records,
        builder: (context, records, _) {
          if (records.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelIcon(PixelIcons.clock, scale: 4),
                    const PixelGap(4),
                    const PixelText.heading('Noch keine Drucke'),
                    const PixelGap(2),
                    const PixelText('Alles, was du an den P1S sendest, landet hier.', color: PixelColors.muted, align: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          final stats = PrintStats.from(records);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(children: [
                Expanded(child: StatTile(glyph: PixelIcons.check, value: '${stats.finished}', label: 'fertig', color: PixelColors.green)),
                const PixelGap(2),
                Expanded(child: StatTile(glyph: PixelIcons.cross, value: '${stats.failed}', label: 'abgebrochen', color: PixelColors.red)),
                const PixelGap(2),
                Expanded(
                  child: StatTile(
                    glyph: PixelIcons.star,
                    value: '${(stats.successRate * 100).round()} %',
                    label: 'Erfolgsquote',
                    color: PixelColors.yellow,
                  ),
                ),
              ]),
              const PixelGap(2),
              Row(children: [
                Expanded(child: StatTile(glyph: PixelIcons.spool, value: formatGrams(stats.grams), label: 'Filament')),
                const PixelGap(2),
                Expanded(child: StatTile(glyph: PixelIcons.clock, value: formatPrintTime(stats.seconds), label: 'Druckzeit')),
                const PixelGap(2),
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: services.appSettings.pricePerKg,
                    builder: (context, price, _) => StatTile(
                      glyph: PixelIcons.star,
                      value: formatEuro(filamentCost(stats.grams, price)),
                      label: 'Material',
                      color: PixelColors.yellow,
                    ),
                  ),
                ),
              ]),
              if (stats.favoriteFilament != null) ...[
                const PixelGap(2),
                PixelText.small('Lieblingsfilament: ${stats.favoriteFilament}', color: PixelColors.muted),
              ],
              const PixelGap(4),
              for (final record in records) ...[
                _RecordTile(record: record),
                const PixelGap(2),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final PrintRecord record;

  Future<void> _delete(BuildContext context) async {
    final services = AppScope.of(context);
    final yes = await showPixelDialog<bool>(
      context,
      title: 'Eintrag löschen?',
      message: '${record.modelName} vom ${formatDateTime(record.sentAt)} wird aus dem Verlauf entfernt. Trophäen bleiben.',
      actions: const [
        PixelDialogAction('Behalten', false),
        PixelDialogAction('Löschen', true, style: PixelButtonStyle.danger),
      ],
    );
    if (yes == true) await services.history.delete(record.id);
  }

  Future<void> _setResult(BuildContext context) async {
    final services = AppScope.of(context);
    final result = await showPixelDialog<PrintResult>(
      context,
      title: 'Wie ist der Druck ausgegangen?',
      message: record.result.open
          ? 'Die App hat das Ende von ${record.modelName} nicht mitbekommen, zum Beispiel weil sie geschlossen oder der Drucker aus war. Fertige Drucke zählen für Statistik und Trophäen.'
          : 'Ergebnis von ${record.modelName} korrigieren. Fertige Drucke zählen für Statistik und Trophäen.',
      actions: const [
        PixelDialogAction('Fertig gedruckt', PrintResult.finished, style: PixelButtonStyle.primary),
        PixelDialogAction('Abgebrochen', PrintResult.failed, style: PixelButtonStyle.danger),
      ],
    );
    if (result != null && result != record.result) await services.history.setResult(record.id, result);
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (record.result) {
      PrintResult.finished => PixelColors.green,
      PrintResult.failed => PixelColors.red,
      PrintResult.printing => PixelColors.accent,
      PrintResult.sent => PixelColors.yellow,
    };
    return PixelPanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PixelText(record.modelName, maxLines: 1),
                PixelText.small(formatDateTime(record.sentAt), color: PixelColors.muted),
                const PixelGap(1),
                PixelText.small(
                  '${formatPrintTime(record.printSeconds)} · ${formatGrams(record.grams)} · ${record.filamentLabel}',
                  color: PixelColors.muted,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const PixelGap(2),
          Semantics(
            button: true,
            label: 'Ergebnis ändern',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setResult(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PixelText(record.result.label, color: color),
                    if (record.result.open) const PixelText.small('antippen', color: PixelColors.muted),
                  ],
                ),
              ),
            ),
          ),
          const PixelGap(2),
          PixelIconButton(icon: PixelIcons.cross, label: 'Eintrag löschen', onPressed: () => _delete(context)),
        ],
      ),
    );
  }
}
