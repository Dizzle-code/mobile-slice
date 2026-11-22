String decimal(double value, int digits) => value.toStringAsFixed(digits).replaceAll('.', ',');

/// Engine timings: "850 ms", "12,3 s", "1 min 23 s".
String formatDuration(int ms) {
  if (ms < 1000) return '$ms ms';
  final seconds = ms / 1000;
  if (seconds < 60) return '${decimal(seconds, 1)} s';
  final minutes = ms ~/ 60000;
  final rest = (ms % 60000) / 1000;
  return '$minutes min ${decimal(rest, 0)} s';
}

/// Print times: "45 min", "2 h 05 min", "3 T 4 h".
String formatPrintTime(int seconds) {
  if (seconds < 60) return '< 1 min';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  if (hours < 48) return '$hours h ${(minutes % 60).toString().padLeft(2, '0')} min';
  return '${hours ~/ 24} T ${hours % 24} h';
}

/// Filament: "12,4 g", "1,25 kg".
String formatGrams(double grams) => grams < 1000 ? '${decimal(grams, 1)} g' : '${decimal(grams / 1000, 2)} kg';

String formatKb(int kb) {
  if (kb <= 0) return '–';
  final mb = kb / 1024;
  if (mb < 1024) return '${decimal(mb, 0)} MB';
  return '${decimal(mb / 1024, 2)} GB';
}

String formatBytes(int bytes) => bytes < 1024 ? '$bytes B' : formatKb(bytes ~/ 1024);

String two(int n) => n.toString().padLeft(2, '0');

/// "21.11.2026, 17:05"
String formatDateTime(DateTime t) => '${two(t.day)}.${two(t.month)}.${t.year}, ${two(t.hour)}:${two(t.minute)}';

String formatEuro(double euros) => '${decimal(euros, 2)} €';
