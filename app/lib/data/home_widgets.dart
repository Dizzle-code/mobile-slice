import 'dart:async';

import 'package:flutter/foundation.dart';

import '../printer/bambu_printer.dart';
import '../printer/printer_status.dart';
import '../trophies/trophy_catalog.dart';
import '../util/format.dart';
import 'print_history.dart';
import 'stats.dart';

/// The texts both home screen widgets show. Times are absolute ("fertig ~15:40", "Stand 14:32")
/// so the widgets stay truthful after the app is closed.
Map<String, String> homeWidgetData({
  required String? printerName,
  required PrinterLink? link,
  required PrinterStatus status,
  required List<PrintRecord> records,
  required Set<String> unlocked,
  required List<Trophy> catalog,
  required DateTime now,
}) {
  final data = <String, String>{
    'p_name': printerName ?? 'Drucker',
    'p_job': '',
    'p_percent': '',
    'p_line': '',
    'p_temps': '',
    'p_updated': 'Stand ${two(now.hour)}:${two(now.minute)}',
  };
  if (printerName == null) {
    data
      ..['p_state'] = 'Nicht eingerichtet'
      ..['p_state_color'] = 'muted'
      ..['p_line'] = 'In der App unter „Drucker“ verbinden'
      ..['p_updated'] = '';
  } else if (link?.state != LinkState.online || status.isEmpty) {
    data
      ..['p_state'] = link?.state == LinkState.connecting ? 'Verbinde …' : 'Nicht verbunden'
      ..['p_state_color'] = link?.state == LinkState.error ? 'red' : 'muted';
  } else {
    final state = status.state;
    data
      ..['p_state'] = state.label
      ..['p_state_color'] = switch (state) {
        PrintState.printing || PrintState.preparing => 'accent',
        PrintState.paused => 'yellow',
        PrintState.failed => 'red',
        PrintState.unknown => 'muted',
        _ => 'green',
      }
      ..['p_temps'] = 'Düse ${status.nozzle.round()}° · Bett ${status.bed.round()}°';
    if (state.busy || state == PrintState.finished || state == PrintState.failed) data['p_job'] = status.subtaskName;
    if (state.busy) {
      data['p_percent'] = '${status.percent}';
      final parts = ['${status.percent} %'];
      final minutes = status.remainingMinutes;
      if (minutes > 0) {
        final end = now.add(Duration(minutes: minutes));
        parts
          ..add('noch ${formatPrintTime(minutes * 60)}')
          ..add('fertig ~${two(end.hour)}:${two(end.minute)}');
      }
      if (status.totalLayers > 0 && minutes <= 0) parts.add('Schicht ${status.layer}/${status.totalLayers}');
      data['p_line'] = parts.join(' · ');
    } else if (state == PrintState.finished) {
      data['p_line'] = 'Druck fertig, Platte abräumen';
    } else if (state == PrintState.idle) {
      data['p_line'] = 'Bereit für den nächsten Druck';
    }
  }

  final stats = PrintStats.from(records);
  data
    ..['w_prints'] = '${stats.finished}'
    ..['w_grams'] = formatGrams(stats.grams)
    ..['w_hours'] = '${stats.hours.floor()} h'
    ..['w_trophies'] = 'Trophäen ${catalog.where((t) => unlocked.contains(t.id)).length} / ${catalog.length}';
  final context = TrophyContext(records);
  Trophy? next;
  TrophyProgress? nextProgress;
  for (final trophy in catalog) {
    if (unlocked.contains(trophy.id)) continue;
    final progress = trophy.progress(context);
    if (nextProgress == null || progress.fraction > nextProgress.fraction) {
      next = trophy;
      nextProgress = progress;
    }
  }
  data['w_next'] = next == null ? 'Alle Trophäen geschafft!' : 'Nächste: ${next.name} · ${nextProgress!.label}';
  return data;
}

/// Pushes [homeWidgetData] to Android whenever it changes. Small changes (temperatures, the clock)
/// are sent at most every [quietInterval]; state, progress and statistics go out right away.
class HomeWidgetSync {
  HomeWidgetSync({
    required this.send,
    required this.printer,
    required this.history,
    required this.unlocked,
    required this.catalog,
    DateTime Function()? clock,
    this.quietInterval = const Duration(minutes: 1),
  }) : _clock = clock ?? DateTime.now;

  final Future<void> Function(Map<String, String> data) send;
  final ValueListenable<BambuPrinter?> printer;
  final ValueListenable<List<PrintRecord>> history;
  final ValueListenable<Map<String, DateTime>> unlocked;
  final List<Trophy> catalog;
  final Duration quietInterval;
  final DateTime Function() _clock;

  static const _quietKeys = {'p_temps', 'p_updated', 'p_line'};

  BambuPrinter? _watched;
  Map<String, String>? _sent;
  DateTime? _sentAt;
  Timer? _later;
  bool _disposed = false;

  void start() {
    printer.addListener(_printerChanged);
    history.addListener(update);
    unlocked.addListener(update);
    _printerChanged();
  }

  void _printerChanged() {
    _watched?.link.removeListener(update);
    _watched?.status.removeListener(update);
    _watched = printer.value;
    _watched?.link.addListener(update);
    _watched?.status.addListener(update);
    update();
  }

  void update() {
    if (_disposed) return;
    final p = printer.value;
    final now = _clock();
    final data = homeWidgetData(
      printerName: p?.config.name,
      link: p?.link.value,
      status: p?.status.value ?? const PrinterStatus(),
      records: history.value,
      unlocked: unlocked.value.keys.toSet(),
      catalog: catalog,
      now: now,
    );
    final sent = _sent;
    if (sent != null && mapEquals(sent, data)) return;
    final important = sent == null || data.keys.any((k) => !_quietKeys.contains(k) && sent[k] != data[k]);
    final wait = _sentAt == null ? Duration.zero : quietInterval - now.difference(_sentAt!);
    if (important || wait <= Duration.zero) {
      _push(data, now);
    } else {
      _later ??= Timer(wait, () {
        _later = null;
        update();
      });
    }
  }

  void _push(Map<String, String> data, DateTime now) {
    _later?.cancel();
    _later = null;
    _sent = data;
    _sentAt = now;
    unawaited(send(data).catchError((Object _) {
      // Widgets are a nice extra; a failed update must never disturb the app.
    }));
  }

  void dispose() {
    _disposed = true;
    _later?.cancel();
    printer.removeListener(_printerChanged);
    history.removeListener(update);
    unlocked.removeListener(update);
    _watched?.link.removeListener(update);
    _watched?.status.removeListener(update);
  }
}
