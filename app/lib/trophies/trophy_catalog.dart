import 'dart:math';

import '../data/print_history.dart';
import '../data/stats.dart';
import '../ui/pixel_icon.dart';
import '../util/format.dart';

/// What the rules look at: all records plus their totals.
class TrophyContext {
  TrophyContext(this.records) : stats = PrintStats.from(records);

  final List<PrintRecord> records;
  final PrintStats stats;

  Iterable<PrintRecord> get finished => records.where((r) => r.result == PrintResult.finished);
}

class TrophyProgress {
  const TrophyProgress(this.current, this.target, this.label);

  final double current;
  final double target;
  final String label;

  double get fraction => target <= 0 ? 1 : min(1, current / target);
  bool get done => current >= target;
}

class Trophy {
  const Trophy({required this.id, required this.name, required this.description, required this.glyph, required this.progress});

  final String id;
  final String name;
  final String description;
  final PixelGlyph glyph;
  final TrophyProgress Function(TrophyContext context) progress;
}

TrophyProgress _count(num current, num target, [String unit = '']) =>
    TrophyProgress(current.toDouble(), target.toDouble(), '${min(current, target).floor()} / ${target.floor()}$unit');

TrophyProgress _any(bool done) => TrophyProgress(done ? 1 : 0, 1, done ? 'geschafft' : 'noch nicht');

abstract final class TrophyGlyphs {
  static final firstPrint = PixelGlyph('first_print', const [
    '.##..........##.',
    '.#+#........#+#.',
    '..#+#......#+#..',
    '...#+#....#+#...',
    '....#+#..#+#....',
    '.....######.....',
    '....#++++++#....',
    '...#+++##+++#...',
    '...#++###+++#...',
    '...#+++##+++#...',
    '...#+++##+++#...',
    '...#++####++#...',
    '....#++++++#....',
    '.....######.....',
  ]);

  static final fivePack = PixelGlyph('five_pack', const [
    '................',
    '.######..######.',
    '.#++++#..#++++#.',
    '.#++++#..#++++#.',
    '.######..######.',
    '.....######.....',
    '.....#++++#.....',
    '.....#++++#.....',
    '.....######.....',
    '.######..######.',
    '.#++++#..#++++#.',
    '.#++++#..#++++#.',
    '.######..######.',
  ]);

  static final serial = PixelGlyph('serial', const [
    '................',
    '................',
    '......####......',
    '......#++#......',
    '......####......',
    '....####.####...',
    '....#++#.#++#...',
    '....####.####...',
    '..####.####.####',
    '..#++#.#++#.#++#',
    '..####.####.####',
  ]);

  static final factory = PixelGlyph('factory', const [
    '................',
    '.##.............',
    '.##.............',
    '.##.............',
    '.##...#.....#...',
    '.##..##....##...',
    '.##.###...###...',
    '.##.####.####...',
    '.###############',
    '.#++++++++++++#.',
    '.#+##++##++##+#.',
    '.#+##++##++##+#.',
    '.#++++++++++++#.',
    '.#++++++##++++#.',
    '.##############.',
  ]);

  static final firstKilo = PixelGlyph('first_kilo', const [
    '................',
    '...##########...',
    '..#..........#..',
    '..############..',
    '...#++++++++#...',
    '...#+#++#+#+#...',
    '...#+##+#+#+#...',
    '...#+#+##+#+#...',
    '...#+#+#+###+#..',
    '...#++++++++#...',
    '...#++++++++#...',
    '..############..',
    '..#..........#..',
    '...##########...',
  ]);

  static final heavyweight = PixelGlyph('heavyweight', const [
    '......####......',
    '.....#....#.....',
    '.....#....#.....',
    '...##########...',
    '...#++++++++#...',
    '..#++++++++++#..',
    '..#+++####+++#..',
    '..#+++#++++++#..',
    '.#++++###+++++#.',
    '.#+++++++#++++#.',
    '.#+++++++#++++#.',
    '.#++++###+++++#.',
    '.##############.',
  ]);

  static final tenHours = PixelGlyph('ten_hours', const [
    '..############..',
    '...#++++++++#...',
    '...#++++++++#...',
    '....#++++++#....',
    '.....#++++#.....',
    '......#++#......',
    '......#..#......',
    '.....#....#.....',
    '....#..++..#....',
    '...#..++++..#...',
    '...#.++++++.#...',
    '..############..',
  ]);

  static final hundredHours = PixelGlyph('hundred_hours', const [
    '................',
    '................',
    '................',
    '................',
    '..#..###.###.#..',
    '.##..#.#.#.#.#..',
    '..#..#.#.#.#.###',
    '..#..#.#.#.#.#.#',
    '.###.###.###.#.#',
    '................',
    '.+++++++++++++++',
  ]);

  static final marathon = PixelGlyph('marathon', const [
    '.##.............',
    '.##############.',
    '.##++##++##++##.',
    '.####++##++##++.',
    '.##++##++##++##.',
    '.####++##++##++.',
    '.##############.',
    '.##.............',
    '.##.............',
    '.##.............',
    '.##.............',
    '.##.............',
    '.##.............',
    '####............',
  ]);

  static final nightOwl = PixelGlyph('night_owl', const [
    '................',
    '.....####.......',
    '...###..........',
    '..###.......+...',
    '.###.......+++..',
    '.###........+...',
    '###.............',
    '###.............',
    '###.........+...',
    '###........+.+..',
    '.###........+...',
    '.####...........',
    '..#####.....##..',
    '...##########...',
    '.....######.....',
  ]);

  static final captain = PixelGlyph('captain', const [
    '................',
    '.......##.......',
    '.......#+#......',
    '.......#++#.....',
    '.......#+++#....',
    '.......#++++#...',
    '.......#+++++#..',
    '.......#........',
    '.......#........',
    '################',
    '.#++++++++++++#.',
    '..#++++++++++#..',
    '...##########...',
    '................',
    '.++..++..++..++.',
    '+..++..++..++..+',
  ]);

  static final materials = PixelGlyph('materials', const [
    '................',
    '.###..###..###..',
    '.#.#..#.#..#.#..',
    '.#.#..#.#..#.#..',
    '.#.#..#.#..#+#..',
    '.#.#..#+#..#+#..',
    '.#+#..#+#..#+#..',
    '.#+#..#+#..#+#..',
    '.#+#..#+#..#+#..',
    '.#+#..#+#..#+#..',
    '.#+#..#+#..#+#..',
    '..#....#....#...',
    '................',
    '################',
  ]);

  static final fineMech = PixelGlyph('fine_mech', const [
    '................',
    '...######.......',
    '..#++++++#......',
    '.#++++++++#.....',
    '.#++++++++#.....',
    '.#++++++++#.....',
    '.#++++++++#.....',
    '..#++++++#......',
    '...#######......',
    '.........###....',
    '..........###...',
    '...........###..',
    '............###.',
    '.............##.',
  ]);

  static final streak = PixelGlyph('streak', const [
    '.......#........',
    '......##........',
    '......#+#.......',
    '.....#++#...#...',
    '....#+++#..##...',
    '....#++++##+#...',
    '...#++++++++#...',
    '...#+++##+++#...',
    '..#+++#..#+++#..',
    '..#++#....#++#..',
    '..#++#....#++#..',
    '..#+++#..#+++#..',
    '...#++++++++#...',
    '....########....',
  ]);
}

/// The first 14 trophies, in display order.
final List<Trophy> trophyCatalog = [
  Trophy(
    id: 'first_print',
    name: 'Erster Druck',
    description: 'Ein Druck aus der App ist fertig geworden.',
    glyph: TrophyGlyphs.firstPrint,
    progress: (c) => _count(c.stats.finished, 1),
  ),
  Trophy(
    id: 'five_pack',
    name: 'Fünferpack',
    description: '5 fertige Drucke.',
    glyph: TrophyGlyphs.fivePack,
    progress: (c) => _count(c.stats.finished, 5),
  ),
  Trophy(
    id: 'serial_production',
    name: 'Serienproduktion',
    description: '25 fertige Drucke.',
    glyph: TrophyGlyphs.serial,
    progress: (c) => _count(c.stats.finished, 25),
  ),
  Trophy(
    id: 'print_factory',
    name: 'Druckfabrik',
    description: '100 fertige Drucke.',
    glyph: TrophyGlyphs.factory,
    progress: (c) => _count(c.stats.finished, 100),
  ),
  Trophy(
    id: 'first_kilo',
    name: 'Erstes Kilo',
    description: '1 kg Filament verdruckt.',
    glyph: TrophyGlyphs.firstKilo,
    progress: (c) => TrophyProgress(c.stats.grams, 1000, '${formatGrams(min(c.stats.grams, 1000))} / 1 kg'),
  ),
  Trophy(
    id: 'heavyweight',
    name: 'Schwergewicht',
    description: '5 kg Filament verdruckt.',
    glyph: TrophyGlyphs.heavyweight,
    progress: (c) => TrophyProgress(c.stats.grams, 5000, '${formatGrams(min(c.stats.grams, 5000))} / 5 kg'),
  ),
  Trophy(
    id: 'ten_hours',
    name: 'Zehn Stunden',
    description: '10 Stunden Druckzeit insgesamt.',
    glyph: TrophyGlyphs.tenHours,
    progress: (c) => _count(c.stats.hours, 10, ' h'),
  ),
  Trophy(
    id: 'hundred_hours',
    name: 'Hundert Stunden',
    description: '100 Stunden Druckzeit insgesamt.',
    glyph: TrophyGlyphs.hundredHours,
    progress: (c) => _count(c.stats.hours, 100, ' h'),
  ),
  Trophy(
    id: 'marathon',
    name: 'Marathon',
    description: 'Ein einzelner Druck über 8 Stunden.',
    glyph: TrophyGlyphs.marathon,
    progress: (c) => TrophyProgress(c.stats.longestSeconds / 3600, 8.0001,
        'längster: ${formatPrintTime(c.stats.longestSeconds)}'),
  ),
  Trophy(
    id: 'night_owl',
    name: 'Nachteule',
    description: 'Einen Druck zwischen 0 und 5 Uhr gestartet.',
    glyph: TrophyGlyphs.nightOwl,
    progress: (c) => _any(c.finished.any((r) => r.sentAt.hour < 5)),
  ),
  Trophy(
    id: 'captain',
    name: 'Kapitän',
    description: 'Ein Benchy ist vom Stapel gelaufen.',
    glyph: TrophyGlyphs.captain,
    progress: (c) => _any(c.finished.any((r) => r.modelName.toLowerCase().contains('benchy'))),
  ),
  Trophy(
    id: 'materials',
    name: 'Materialkunde',
    description: 'Mit 3 verschiedenen Filamenttypen gedruckt.',
    glyph: TrophyGlyphs.materials,
    progress: (c) => _count(c.stats.filamentTypes.length, 3, ' Typen'),
  ),
  Trophy(
    id: 'fine_mechanic',
    name: 'Feinmechaniker',
    description: 'Ein Druck mit 0,08 mm Schichthöhe.',
    glyph: TrophyGlyphs.fineMech,
    progress: (c) => _any(c.finished.any((r) => r.layerHeight > 0 && r.layerHeight <= 0.0801)),
  ),
  Trophy(
    id: 'streak',
    name: 'Durchhalter',
    description: '5 erfolgreiche Drucke in Folge.',
    glyph: TrophyGlyphs.streak,
    progress: (c) => _count(c.stats.bestStreak, 5),
  ),
];
