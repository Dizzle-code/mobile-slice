import 'print_history.dart';

/// Totals over the history; only finished prints count towards material and time.
class PrintStats {
  const PrintStats({
    required this.finished,
    required this.failed,
    required this.sent,
    required this.grams,
    required this.seconds,
    required this.longestSeconds,
    required this.filamentTypes,
    required this.currentStreak,
    required this.bestStreak,
    required this.favoriteFilament,
  });

  factory PrintStats.from(List<PrintRecord> records) {
    final done = records.where((r) => r.result == PrintResult.finished).toList();
    // Streaks run oldest to newest over closed prints; a failure resets them.
    final closed = records.where((r) => !r.result.open).toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    var current = 0, best = 0;
    for (final r in closed) {
      current = r.result == PrintResult.finished ? current + 1 : 0;
      if (current > best) best = current;
    }
    final counts = <String, int>{};
    for (final r in done) {
      if (r.filamentLabel.isNotEmpty) counts[r.filamentLabel] = (counts[r.filamentLabel] ?? 0) + 1;
    }
    final favorite = counts.entries.fold<MapEntry<String, int>?>(null, (best, e) => best == null || e.value > best.value ? e : best);
    return PrintStats(
      finished: done.length,
      failed: records.where((r) => r.result == PrintResult.failed).length,
      sent: records.length,
      grams: done.fold(0.0, (sum, r) => sum + r.grams),
      seconds: done.fold(0, (sum, r) => sum + r.printSeconds),
      longestSeconds: done.fold(0, (m, r) => r.printSeconds > m ? r.printSeconds : m),
      filamentTypes: {for (final r in done) if (r.filamentType.isNotEmpty) r.filamentType.toUpperCase()},
      currentStreak: current,
      bestStreak: best,
      favoriteFilament: favorite?.key,
    );
  }

  final int finished;
  final int failed;
  final int sent;
  final double grams;
  final int seconds;
  final int longestSeconds;
  final Set<String> filamentTypes;
  final int currentStreak;
  final int bestStreak;
  final String? favoriteFilament;

  double get hours => seconds / 3600;

  /// Share of closed prints that finished, 0..1.
  double get successRate => finished + failed == 0 ? 0 : finished / (finished + failed);
}
