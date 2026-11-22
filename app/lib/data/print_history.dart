import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/slice_outcome.dart';
import '../printer/printer_status.dart';
import 'json_store.dart';

enum PrintResult {
  sent('Gesendet'),
  printing('Druckt'),
  finished('Fertig'),
  failed('Abgebrochen');

  const PrintResult(this.label);
  final String label;

  bool get open => this == sent || this == printing;
}

class PrintRecord {
  const PrintRecord({
    required this.id,
    required this.modelName,
    required this.subtaskName,
    required this.sentAt,
    required this.result,
    required this.printSeconds,
    required this.grams,
    required this.filamentType,
    required this.filamentLabel,
    required this.layerHeight,
    required this.processLabel,
    this.seenActive = false,
    this.finishedAt,
  });

  factory PrintRecord.fromJson(Map<String, Object?> json) => PrintRecord(
        id: json['id'] as String,
        modelName: json['modelName'] as String? ?? '?',
        subtaskName: json['subtaskName'] as String? ?? '',
        sentAt: DateTime.parse(json['sentAt'] as String),
        result: PrintResult.values.firstWhere((r) => r.name == json['result'], orElse: () => PrintResult.sent),
        printSeconds: (json['printSeconds'] as num?)?.toInt() ?? 0,
        grams: (json['grams'] as num?)?.toDouble() ?? 0,
        filamentType: json['filamentType'] as String? ?? '',
        filamentLabel: json['filamentLabel'] as String? ?? '',
        layerHeight: (json['layerHeight'] as num?)?.toDouble() ?? 0,
        processLabel: json['processLabel'] as String? ?? '',
        seenActive: json['seenActive'] == true,
        finishedAt: json['finishedAt'] == null ? null : DateTime.parse(json['finishedAt'] as String),
      );

  final String id;
  final String modelName;

  /// Name the printer reports while printing this job.
  final String subtaskName;
  final DateTime sentAt;
  final PrintResult result;

  /// Slicer estimate.
  final int printSeconds;
  final double grams;
  final String filamentType;
  final String filamentLabel;
  final double layerHeight;
  final String processLabel;

  /// Whether the printer was ever seen working on it (guards against stale FINISH reports).
  final bool seenActive;
  final DateTime? finishedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'modelName': modelName,
        'subtaskName': subtaskName,
        'sentAt': sentAt.toIso8601String(),
        'result': result.name,
        'printSeconds': printSeconds,
        'grams': grams,
        'filamentType': filamentType,
        'filamentLabel': filamentLabel,
        'layerHeight': layerHeight,
        'processLabel': processLabel,
        'seenActive': seenActive,
        'finishedAt': finishedAt?.toIso8601String(),
      };

  PrintRecord copyWith({PrintResult? result, bool? seenActive, DateTime? finishedAt}) => PrintRecord(
        id: id,
        modelName: modelName,
        subtaskName: subtaskName,
        sentAt: sentAt,
        result: result ?? this.result,
        printSeconds: printSeconds,
        grams: grams,
        filamentType: filamentType,
        filamentLabel: filamentLabel,
        layerHeight: layerHeight,
        processLabel: processLabel,
        seenActive: seenActive ?? this.seenActive,
        finishedAt: finishedAt ?? this.finishedAt,
      );
}

/// All prints sent from this app, newest first, persisted as `history.json`.
class PrintHistory {
  PrintHistory(this.store);

  final JsonStore store;
  final records = ValueNotifier<List<PrintRecord>>(const []);
  static const _name = 'history';

  Future<void> load() async {
    final json = await store.read(_name);
    if (json is! List) return;
    final loaded = <PrintRecord>[];
    for (final item in json) {
      try {
        loaded.add(PrintRecord.fromJson((item as Map).cast<String, Object?>()));
      } catch (_) {
        // A single damaged entry must not cost the whole history.
      }
    }
    loaded.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    records.value = List.unmodifiable(loaded);
  }

  Future<void> _save(List<PrintRecord> next) async {
    records.value = List.unmodifiable(next);
    await store.write(_name, [for (final r in next) r.toJson()]);
  }

  Future<PrintRecord> recordSent(SliceOutcome outcome, String subtaskName, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    final record = PrintRecord(
      id: '${time.microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}',
      modelName: outcome.modelName,
      subtaskName: subtaskName,
      sentAt: time,
      result: PrintResult.sent,
      printSeconds: outcome.printSeconds,
      grams: outcome.grams,
      filamentType: outcome.filamentType,
      filamentLabel: outcome.filamentLabel,
      layerHeight: outcome.layerHeight,
      processLabel: outcome.processLabel,
    );
    await _save([record, ...records.value]);
    return record;
  }

  static String _jobKey(String name) {
    final base = name.trim().split(RegExp(r'[\/]')).last.toLowerCase();
    return base.replaceFirst(RegExp(r'(\.gcode)?\.3mf$|\.gcode$'), '');
  }

  /// Applies a printer report to the newest open record with the same subtask name and closes
  /// older open records the printer has clearly moved on from. Returns a record that just finished or failed.
  Future<PrintRecord?> applyStatus(PrinterStatus status, {DateTime? now}) async {
    final state = status.state;
    if (state == PrintState.unknown) return null;
    final time = now ?? DateTime.now();
    final key = _jobKey(status.subtaskName);
    final list = [...records.value];
    final index = key.isEmpty ? -1 : list.indexWhere((r) => r.result.open && _jobKey(r.subtaskName) == key);
    PrintRecord? closed;
    var changed = false;
    if (index >= 0) {
      final next = _advance(list[index], state, time);
      if (next != null) {
        list[index] = next;
        changed = true;
        if (!next.result.open) closed = next;
      }
    }
    // The finish report was missed (app closed, printer switched off, next job started):
    // a job that was seen running and has had its full estimated time counts as done.
    if (state == PrintState.idle || key.isNotEmpty) {
      for (var i = 0; i < list.length; i++) {
        final r = list[i];
        if (i == index || !r.result.open || !r.seenActive) continue;
        if (time.difference(r.sentAt).inSeconds < r.printSeconds) continue;
        list[i] = r.copyWith(result: PrintResult.finished, finishedAt: time);
        changed = true;
        closed ??= list[i];
      }
    }
    if (changed) await _save(list);
    return closed;
  }

  PrintRecord? _advance(PrintRecord record, PrintState state, DateTime time) {
    if (state.busy) {
      if (record.result != PrintResult.printing || !record.seenActive) {
        return record.copyWith(result: PrintResult.printing, seenActive: true);
      }
    } else if (state == PrintState.finished || state == PrintState.failed) {
      // Right after sending, the printer may still report the previous job of the same name.
      final age = time.difference(record.sentAt);
      final plausible = record.seenActive ||
          (state == PrintState.finished ? age.inSeconds >= record.printSeconds ~/ 2 : age.inMinutes >= 2);
      if (plausible) {
        return record.copyWith(
          result: state == PrintState.finished ? PrintResult.finished : PrintResult.failed,
          finishedAt: time,
        );
      }
    }
    return null;
  }

  /// Lets the user settle a result the printer reports could not.
  Future<void> setResult(String id, PrintResult result, {DateTime? now}) => _save([
        for (final r in records.value)
          if (r.id == id) r.copyWith(result: result, finishedAt: r.finishedAt ?? now ?? DateTime.now()) else r,
      ]);

  Future<void> delete(String id) => _save(records.value.where((r) => r.id != id).toList());

  Future<void> clear() => _save(const []);
}
