import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../app_shell.dart';
import '../engine/slice_outcome.dart';
import '../printer/bambu_printer.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import 'printer_screen.dart';

/// Upload the sliced file to the P1S and start it, with progress and clear errors.
Future<void> sendToPrinter(BuildContext context, SliceOutcome outcome) async {
  final services = AppScope.of(context);
  final printer = services.printer.value;
  if (printer == null) {
    final setup = await showPixelDialog<bool>(
      context,
      title: 'Kein Drucker eingerichtet',
      message: 'Richte zuerst deinen P1S im LAN ein.',
      icon: PixelIcons.printer,
      actions: const [
        PixelDialogAction('Später', false),
        PixelDialogAction('Jetzt einrichten', true, style: PixelButtonStyle.primary),
      ],
    );
    if (setup == true && context.mounted) await PrinterScreen.openSetup(context);
    return;
  }

  final progress = ValueNotifier<double?>(null);
  final message = ValueNotifier('Verbinde mit ${printer.config.name} …');
  final dialog = showPixelProgressDialog(context, title: 'An P1S senden', message: message, progress: progress);
  String? error;
  try {
    if (!printer.online) {
      unawaited(printer.connect());
      await _waitOnline(printer, const Duration(seconds: 12));
    }
    message.value = 'Lade ${outcome.remoteName} hoch …';
    final subtask = outcome.remoteName.replaceFirst(RegExp(r'\.gcode\.3mf$'), '');
    await printer.sendAndPrint(File(outcome.archivePath), outcome.remoteName, subtask, onProgress: (p) => progress.value = p);
    message.value = 'Druck wird gestartet …';
    await services.history.recordSent(outcome, subtask);
  } catch (e) {
    error = e is PrinterException ? e.message : e.toString();
    final details = e is PrinterException ? e.details : null;
    try {
      await services.slicer.appendLog('Senden an ${printer.config.name}', [error, ?details].join('\n'));
    } catch (_) {
      // Logging must never hide the actual send error.
    }
  } finally {
    dialog.close();
  }
  if (!context.mounted) return;
  if (error != null) {
    await showPixelDialog<void>(
      context,
      title: 'Senden fehlgeschlagen',
      message: error,
      icon: PixelIcons.warning,
      actions: const [PixelDialogAction('OK', null, style: PixelButtonStyle.primary)],
    );
    return;
  }
  PixelToast.show(context, 'Druck gestartet!', kind: PixelToastKind.success);
  AppShellState.maybeOf(context)?.select(1);
}

Future<void> _waitOnline(BambuPrinter printer, Duration timeout) {
  if (printer.online) return Future.value();
  final completer = Completer<void>();
  void listener() {
    final link = printer.link.value;
    if (link.state == LinkState.online && !completer.isCompleted) completer.complete();
  }

  printer.link.addListener(listener);
  return completer.future.timeout(timeout, onTimeout: () {
    final link = printer.link.value;
    throw PrinterException(link.message ?? 'Drucker nicht erreichbar');
  }).whenComplete(() => printer.link.removeListener(listener));
}
