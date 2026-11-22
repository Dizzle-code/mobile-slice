import 'package:flutter/widgets.dart';

import '../app_services.dart';
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
import 'printer_setup_screen.dart';

/// Live view of the P1S: progress, layer, temperatures, pause/stop.
class PrinterScreen extends StatelessWidget {
  const PrinterScreen({super.key});

  static Future<void> openSetup(BuildContext context) =>
      Navigator.of(context).push(PixelRoute<void>(builder: (_) => const PrinterSetupScreen()));

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ValueListenableBuilder<BambuPrinter?>(
      valueListenable: services.printer,
      builder: (context, printer, _) => PixelScaffold(
        title: printer?.config.name ?? 'Drucker',
        actions: [
          PixelIconButton(icon: PixelIcons.gear, label: 'Drucker einrichten', onPressed: () => openSetup(context)),
        ],
        body: printer == null ? const _NoPrinter() : _Live(printer: printer),
      ),
    );
  }
}

class _NoPrinter extends StatelessWidget {
  const _NoPrinter();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelIcon(PixelIcons.printer, scale: 4),
              const PixelGap(4),
              const PixelText.heading('Noch kein Drucker', align: TextAlign.center),
              const PixelGap(2),
              const PixelText('Verbinde deinen P1S im LAN, um Drucke direkt vom Handy zu starten.',
                  color: PixelColors.muted, align: TextAlign.center),
              const PixelGap(4),
              PixelButton(
                label: 'Drucker einrichten',
                icon: PixelIcons.plus,
                style: PixelButtonStyle.primary,
                onPressed: () => PrinterScreen.openSetup(context),
              ),
            ],
          ),
        ),
      );
}

class _Live extends StatelessWidget {
  const _Live({required this.printer});

  final BambuPrinter printer;

  Future<void> _confirmStop(BuildContext context) async {
    final yes = await showPixelDialog<bool>(
      context,
      title: 'Druck abbrechen?',
      message: 'Der laufende Druck wird gestoppt und lässt sich nicht fortsetzen.',
      icon: PixelIcons.warning,
      actions: const [
        PixelDialogAction('Weiterdrucken', false),
        PixelDialogAction('Abbrechen', true, style: PixelButtonStyle.danger),
      ],
    );
    if (yes == true && context.mounted) _run(context, printer.stop);
  }

  void _run(BuildContext context, void Function() command) {
    try {
      command();
    } on PrinterException catch (e) {
      PixelToast.show(context, e.message, kind: PixelToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PrinterLink>(
      valueListenable: printer.link,
      builder: (context, link, _) => ValueListenableBuilder<PrinterStatus>(
        valueListenable: printer.status,
        builder: (context, status, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _LinkBadge(link: link, onRetry: () => printer.connect()),
            const PixelGap(3),
            if (link.state == LinkState.online && !status.isEmpty) ...[
              _jobPanel(context, status),
              const PixelGap(3),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      glyph: PixelIcons.thermometer,
                      value: '${status.nozzle.round()} °C',
                      label: 'Düse${status.nozzleTarget > 0 ? ' → ${status.nozzleTarget.round()} °C' : ''}',
                      color: PixelColors.red,
                    ),
                  ),
                  const PixelGap(3),
                  Expanded(
                    child: StatTile(
                      glyph: PixelIcons.bed,
                      value: '${status.bed.round()} °C',
                      label: 'Bett${status.bedTarget > 0 ? ' → ${status.bedTarget.round()} °C' : ''}',
                      color: PixelColors.yellow,
                    ),
                  ),
                ],
              ),
              if (!status.hasSdCard) ...[
                const PixelGap(3),
                const PixelPanel(
                  borderColor: PixelColors.red,
                  child: PixelText('Keine SD-Karte im Drucker: Drucke können nicht gestartet werden.', color: PixelColors.red),
                ),
              ],
              if (status.printError != 0) ...[
                const PixelGap(3),
                PixelPanel(
                  borderColor: PixelColors.red,
                  child: PixelText('Druckerfehler ${status.printError.toRadixString(16).toUpperCase()} (siehe Druckerdisplay)',
                      color: PixelColors.red),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _jobPanel(BuildContext context, PrinterStatus status) {
    final state = status.state;
    final active = state.busy;
    final color = switch (state) {
      PrintState.finished => PixelColors.green,
      PrintState.failed => PixelColors.red,
      PrintState.paused => PixelColors.yellow,
      _ => PixelColors.accent,
    };
    return PixelPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: PixelText.title(state.label, color: color)),
            if (active || state == PrintState.finished) PixelText.title('${status.percent} %', color: color),
          ]),
          if (status.subtaskName.isNotEmpty) PixelText(status.subtaskName, color: PixelColors.muted, maxLines: 1),
          if (state == PrintState.preparing && status.stageLabel != null)
            PixelText.small(status.stageLabel!, color: PixelColors.yellow),
          if (active || state == PrintState.finished) ...[
            const PixelGap(3),
            PixelProgressBar(value: status.percent / 100, color: color, semanticLabel: 'Druckfortschritt'),
            const PixelGap(2),
            Row(children: [
              Expanded(
                child: PixelText.small(
                  status.totalLayers > 0 ? 'Schicht ${status.layer} / ${status.totalLayers}' : 'Schicht –',
                  color: PixelColors.muted,
                ),
              ),
              if (active) PixelText.small('noch ${formatPrintTime(status.remainingMinutes * 60)}', color: PixelColors.muted),
            ]),
          ],
          if (active) ...[
            const PixelGap(4),
            Row(children: [
              Expanded(
                child: state == PrintState.paused
                    ? PixelButton(label: 'Fortsetzen', icon: PixelIcons.play, onPressed: () => _run(context, printer.resume))
                    : PixelButton(label: 'Pause', icon: PixelIcons.pause, onPressed: () => _run(context, printer.pause)),
              ),
              const PixelGap(3),
              Expanded(
                child: PixelButton(
                  label: 'Abbrechen',
                  icon: PixelIcons.stop,
                  style: PixelButtonStyle.danger,
                  onPressed: () => _confirmStop(context),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _LinkBadge extends StatelessWidget {
  const _LinkBadge({required this.link, required this.onRetry});

  final PrinterLink link;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (link.state) {
      LinkState.online => ('Verbunden', PixelColors.green),
      LinkState.connecting => ('Verbinde …', PixelColors.yellow),
      LinkState.error => (link.message ?? 'Fehler', PixelColors.red),
      LinkState.off => ('Nicht verbunden', PixelColors.muted),
    };
    return PixelPanel(
      borderColor: color,
      child: Row(
        children: [
          PixelIcon(PixelIcons.wifi, scale: 1, color: color, secondColor: color),
          const PixelGap(2),
          Expanded(child: PixelText(text, color: color)),
          if (link.state == LinkState.error || link.state == LinkState.off) ...[
            const PixelGap(2),
            PixelButton(label: 'Neu verbinden', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}
