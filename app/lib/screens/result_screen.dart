import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../data/app_settings.dart';
import '../engine/slice_outcome.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_route.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/stat_tile.dart';
import '../util/format.dart';
import 'send_flow.dart';

abstract final class PixelRouteFor {
  static PixelRoute<void> result(SliceOutcome outcome) =>
      PixelRoute(builder: (_) => ResultScreen(outcome: outcome), settings: const RouteSettings(name: 'result'));
}

/// Slice summary with the way to the printer.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.outcome});

  final SliceOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final tiles = [
      StatTile(glyph: PixelIcons.clock, value: formatPrintTime(outcome.printSeconds), label: 'Druckzeit'),
      StatTile(
        glyph: PixelIcons.spool,
        value: formatGrams(outcome.grams),
        label: '${decimal(outcome.meters, 2)} m ${outcome.filamentType}',
        color: PixelColors.green,
      ),
      StatTile(glyph: PixelIcons.layers, value: '${outcome.layers}', label: 'Schichten', color: PixelColors.yellow),
      StatTile(
        glyph: PixelIcons.support,
        value: outcome.supportUsed ? 'Ja' : 'Nein',
        label: 'Stützen',
        color: PixelColors.text,
      ),
    ];
    return PixelScaffold(
      title: 'Fertig gesliced!',
      onBack: () => Navigator.of(context).maybePop(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          PixelText(outcome.modelName, color: PixelColors.muted, maxLines: 2),
          const PixelGap(3),
          for (var row = 0; row < tiles.length; row += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _PopIn(delay: row * 2, child: tiles[row])),
                const PixelGap(3),
                Expanded(child: _PopIn(delay: row * 2 + 1, child: tiles[row + 1])),
              ],
            ),
            const PixelGap(3),
          ],
          PixelPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row('Profil', '${decimal(outcome.layerHeight, 2)} mm · ${outcome.processLabel}'),
                _row('Filament', outcome.filamentLabel),
                _row(
                  'Material',
                  'ca. ${formatEuro(filamentCost(outcome.grams, services.appSettings.pricePerKg.value))} '
                      '(${decimal(services.appSettings.pricePerKg.value, 0)} €/kg)',
                ),
                _row('Füllung', '${outcome.infill} %'),
                _row('Wände', '${outcome.walls}'),
                _row('Datei', outcome.remoteName),
              ],
            ),
          ),
          for (final warning in outcome.warnings) ...[
            const PixelGap(3),
            PixelPanel(borderColor: PixelColors.yellow, child: PixelText.small(warning, color: PixelColors.yellow)),
          ],
        ],
      ),
      bottom: Container(
        color: PixelColors.panel,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PixelButton(
              label: 'An P1S senden',
              icon: PixelIcons.upload,
              style: PixelButtonStyle.primary,
              expand: true,
              onPressed: () => sendToPrinter(context, outcome),
            ),
            const PixelGap(2),
            PixelButton(
              label: services.slicer.desktop ? 'Datei speichern' : 'Datei teilen',
              icon: services.slicer.desktop ? PixelIcons.save : PixelIcons.share,
              expand: true,
              onPressed: () async {
                try {
                  await services.slicer.shareFile(outcome.archivePath, mime: 'application/vnd.ms-package.3dmanufacturing-3dmodel+xml', title: services.slicer.desktop ? 'Druckdatei speichern' : 'Druckdatei teilen');
                } on PlatformException catch (e) {
                  if (context.mounted) PixelToast.show(context, e.message ?? e.code, kind: PixelToastKind.error);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: PixelText(label, color: PixelColors.muted)),
            Expanded(child: PixelText(value)),
          ],
        ),
      );
}

/// Tiles hop in one after another.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.delay, required this.child});

  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 240 + delay * 90),
        builder: (context, t, child) {
          final local = ((t * (240 + delay * 90) - delay * 90) / 240).clamp(0.0, 1.0);
          final steps = (local * 3).ceil() / 3;
          return Opacity(opacity: steps, child: Transform.translate(offset: Offset(0, (1 - steps) * 12), child: child));
        },
        child: child,
      );
}
