import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';

enum SettingKind { integer, decimal, percent, toggle, choice }

/// Which bundled profile holds a setting's value.
enum SettingSource { process, filament }

enum SettingCategory {
  quality('Qualität', 'Schichten, Linienbreiten, Genauigkeit'),
  walls('Wände', 'Anzahl, Reihenfolge, dünne Wände'),
  shells('Ober-/Unterseiten', 'Deckschichten und Muster'),
  infill('Füllung', 'Dichte, Muster, Lücken'),
  speed('Geschwindigkeit', 'Tempo und Beschleunigung'),
  support('Stützen', 'Normal- und Baumstützen'),
  adhesion('Haftung', 'Brim, Skirt, Raft'),
  cooling('Kühlung', 'Lüfter und Schichtzeit'),
  temperature('Temperatur', 'Düse und Druckbett'),
  filament('Filament und Rückzug', 'Fluss, Rückzug, Z-Hop'),
  special('Oberfläche und Spezial', 'Fuzzy Skin, Bügeln, Naht, Vase');

  const SettingCategory(this.label, this.summary);

  final String label;
  final String summary;

  PixelGlyph get glyph => switch (this) {
        quality => PixelIcons.star,
        walls => PixelIcons.walls,
        shells => PixelIcons.surface,
        infill => PixelIcons.infill,
        speed => PixelIcons.speed,
        support => PixelIcons.support,
        adhesion => PixelIcons.brim,
        cooling => PixelIcons.fan,
        temperature => PixelIcons.thermometer,
        filament => PixelIcons.spool,
        special => PixelIcons.sparkle,
      };
}

class SettingChoice {
  const SettingChoice(this.value, this.label);

  /// Engine value, e.g. `tree(auto)`.
  final String value;
  final String label;
}

/// Shows a setting only while another setting has (or lacks) certain values.
class ShowIf {
  const ShowIf(this.key, {this.any = const [], this.not = const []});

  final String key;
  final List<Object> any;
  final List<Object> not;

  bool test(Object? value) => (any.isEmpty || any.contains(value)) && !not.contains(value);
}

/// One engine setting the app exposes. Values are typed by [kind]:
/// integer → int, decimal/percent → double, toggle → bool, choice → String.
class SettingDef {
  const SettingDef({
    required this.key,
    required this.label,
    required this.help,
    required this.category,
    required this.kind,
    this.unit = '',
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.choices = const [],
    this.source = SettingSource.process,
    this.engineDefault,
    this.printerFallback,
    this.advanced = false,
    this.showIf,
    this.terms = '',
    this.scalesWithSpeed = false,
  });

  /// OrcaSlicer config key.
  final String key;
  final String label;
  final String help;
  final SettingCategory category;
  final SettingKind kind;
  final String unit;
  final num min;
  final num max;
  final num step;
  final List<SettingChoice> choices;
  final SettingSource source;

  /// Engine default for keys the bundled profiles leave out.
  final Object? engineDefault;

  /// Printer key that applies while the filament profile says `nil`.
  final String? printerFallback;
  final bool advanced;
  final ShowIf? showIf;

  /// Extra search words.
  final String terms;

  /// Scaled by the overall speed percentage unless set individually.
  final bool scalesWithSpeed;

  String choiceLabel(String value) =>
      choices.firstWhere((c) => c.value == value, orElse: () => SettingChoice(value, value)).label;
}

const _layers = SettingCategory.quality;
const _walls = SettingCategory.walls;
const _shells = SettingCategory.shells;
const _infill = SettingCategory.infill;
const _speed = SettingCategory.speed;
const _support = SettingCategory.support;
const _adhesion = SettingCategory.adhesion;
const _cooling = SettingCategory.cooling;
const _temp = SettingCategory.temperature;
const _filament = SettingCategory.filament;
const _special = SettingCategory.special;

SettingDef _int(String key, String label, String help, SettingCategory category,
        {num min = 0, num max = 100, String unit = '', SettingSource source = SettingSource.process, Object? engineDefault, bool advanced = false, ShowIf? showIf, String terms = ''}) =>
    SettingDef(key: key, label: label, help: help, category: category, kind: SettingKind.integer, min: min, max: max, unit: unit, source: source, engineDefault: engineDefault, advanced: advanced, showIf: showIf, terms: terms);

SettingDef _dec(String key, String label, String help, SettingCategory category,
        {num min = 0, num max = 10, num step = 0.01, String unit = 'mm', SettingSource source = SettingSource.process, Object? engineDefault, String? printerFallback, bool advanced = false, ShowIf? showIf, String terms = '', bool scales = false}) =>
    SettingDef(key: key, label: label, help: help, category: category, kind: SettingKind.decimal, min: min, max: max, step: step, unit: unit, source: source, engineDefault: engineDefault, printerFallback: printerFallback, advanced: advanced, showIf: showIf, terms: terms, scalesWithSpeed: scales);

SettingDef _speedDef(String key, String label, String help, {bool scales = true, bool advanced = false, num max = 600, ShowIf? showIf, String terms = ''}) =>
    _dec(key, label, help, _speed, min: 1, max: max, step: 5, unit: 'mm/s', advanced: advanced, scales: scales, showIf: showIf, terms: 'tempo schnell langsam $terms');

SettingDef _accel(String key, String label, String help, {Object? engineDefault}) =>
    _dec(key, label, help, _speed, min: 100, max: 20000, step: 100, unit: 'mm/s²', engineDefault: engineDefault, advanced: true, terms: 'beschleunigung acceleration');

SettingDef _pct(String key, String label, String help, SettingCategory category,
        {num min = 0, num max = 100, num step = 1, SettingSource source = SettingSource.process, Object? engineDefault, bool advanced = false, ShowIf? showIf, String terms = ''}) =>
    SettingDef(key: key, label: label, help: help, category: category, kind: SettingKind.percent, min: min, max: max, step: step, unit: '%', source: source, engineDefault: engineDefault, advanced: advanced, showIf: showIf, terms: terms);

SettingDef _bool(String key, String label, String help, SettingCategory category,
        {SettingSource source = SettingSource.process, Object? engineDefault, String? printerFallback, bool advanced = false, ShowIf? showIf, String terms = ''}) =>
    SettingDef(key: key, label: label, help: help, category: category, kind: SettingKind.toggle, source: source, engineDefault: engineDefault, printerFallback: printerFallback, advanced: advanced, showIf: showIf, terms: terms);

SettingDef _choice(String key, String label, String help, SettingCategory category, List<SettingChoice> choices,
        {SettingSource source = SettingSource.process, Object? engineDefault, String? printerFallback, bool advanced = false, ShowIf? showIf, String terms = ''}) =>
    SettingDef(key: key, label: label, help: help, category: category, kind: SettingKind.choice, choices: choices, source: source, engineDefault: engineDefault, printerFallback: printerFallback, advanced: advanced, showIf: showIf, terms: terms);

SettingDef _width(String key, String label, {bool advanced = true}) => _dec(key, label,
    'Breite der gedruckten Linie. Breiter ist stabiler und schneller, schmaler bildet feinere Details ab. Üblich: 100–120 % der Düse (0,4 mm).',
    _layers, min: 0.2, max: 1.0, step: 0.01, advanced: advanced, terms: 'linienbreite extrusionsbreite line width');

const _surfacePatterns = [
  SettingChoice('monotonic', 'Monoton'),
  SettingChoice('monotonicline', 'Monotone Linie'),
  SettingChoice('rectilinear', 'Geradlinig'),
  SettingChoice('alignedrectilinear', 'Geradlinig ausgerichtet'),
  SettingChoice('concentric', 'Konzentrisch'),
  SettingChoice('hilbertcurve', 'Hilbert-Kurve'),
  SettingChoice('archimedeanchords', 'Archimedische Sehnen'),
  SettingChoice('octagramspiral', 'Oktagramm-Spirale'),
];

const _supportOn = ShowIf('enable_support', any: [true]);
const _fuzzyOn = ShowIf('fuzzy_skin', not: ['none']);
const _ironingOn = ShowIf('ironing_type', not: ['no ironing']);
const _overhangSpeedOn = ShowIf('enable_overhang_speed', any: [true]);
const _wipeOn = ShowIf('filament_wipe', any: [true]);

/// Every setting the app shows, in display order per category.
final List<SettingDef> settingDefs = List.unmodifiable([
  // Qualität
  _dec('initial_layer_print_height', 'Höhe der ersten Schicht',
      'Dicke der allerersten Schicht. Etwas dicker haftet besser und gleicht Unebenheiten des Betts aus.', _layers,
      min: 0.05, max: 0.4, terms: 'erste schicht first layer'),
  _width('line_width', 'Linienbreite (Standard)', advanced: false),
  _width('outer_wall_line_width', 'Linienbreite Außenwand'),
  _width('inner_wall_line_width', 'Linienbreite Innenwände'),
  _width('top_surface_line_width', 'Linienbreite Oberseite'),
  _width('sparse_infill_line_width', 'Linienbreite Füllung'),
  _width('internal_solid_infill_line_width', 'Linienbreite massive Füllung'),
  _width('initial_layer_line_width', 'Linienbreite erste Schicht'),
  _width('support_line_width', 'Linienbreite Stützen'),
  _bool('enable_arc_fitting', 'Bögen glätten (Arc Fitting)',
      'Fasst viele kurze Linien zu Kreisbögen zusammen. Kleinerer G-Code, flüssigere Bewegungen.', _layers,
      advanced: true, terms: 'g2 g3 bogen kreis'),
  _dec('resolution', 'Auflösung',
      'Wie stark das Modell vor dem Slicen vereinfacht wird. Kleiner ist genauer, aber langsamer zu berechnen.', _layers,
      min: 0.001, max: 0.1, step: 0.001, advanced: true, terms: 'genauigkeit vereinfachen'),
  _dec('xy_hole_compensation', 'Lochausgleich XY',
      'Vergrößert (+) oder verkleinert (−) Löcher, damit Schrauben und Stifte passen.', _layers,
      min: -1, max: 1, advanced: true, terms: 'toleranz loch passung bohrung'),
  _dec('xy_contour_compensation', 'Konturausgleich XY',
      'Vergrößert (+) oder verkleinert (−) die Außenkontur, um Maßabweichungen auszugleichen.', _layers,
      min: -1, max: 1, advanced: true, terms: 'toleranz maß passung'),
  _bool('precise_outer_wall', 'Präzise Außenwand',
      'Hält die Außenwand genauer auf Maß, indem der Abstand zu den Innenwänden angepasst wird.', _layers,
      engineDefault: true, advanced: true, terms: 'maßhaltig genau'),
  _dec('slice_closing_radius', 'Schließradius beim Slicen',
      'Kleine Lücken im Modell bis zu diesem Radius werden geschlossen. Hilft bei leicht kaputten Modellen.', _layers,
      min: 0, max: 1, step: 0.001, engineDefault: 0.049, advanced: true, terms: 'reparieren lücke'),
  _bool('reduce_crossing_wall', 'Wände bei Fahrten meiden',
      'Leerfahrten umgehen Wände, statt sie zu überqueren. Weniger Fäden und Kratzer, etwas langsamer.', _layers,
      advanced: true, terms: 'travel leerfahrt fäden stringing'),
  _dec('bridge_flow', 'Brückenfluss',
      'Materialmenge beim Überbrücken. Etwas weniger als 1 macht Brücken straffer.', _layers,
      min: 0.5, max: 1.5, advanced: true, unit: '', terms: 'brücke bridge'),
  _bool('thick_bridges', 'Dicke Brücken',
      'Druckt Brücken mit dicker runder Linie. Stabiler bei langen Brücken, sieht aber gröber aus.', _layers,
      engineDefault: false, advanced: true, terms: 'brücke bridge'),

  // Wände
  _int('wall_loops', 'Anzahl Wände',
      'Wie viele Linien die Außenseite bilden. Mehr Wände machen Teile deutlich stabiler.', _walls,
      min: 1, max: 20, terms: 'perimeter wandlinien schalen'),
  _choice('wall_generator', 'Wandgenerator',
      'Arachne passt die Linienbreite an und füllt dünne Stellen sauber. Klassisch nutzt feste Breiten.', _walls,
      const [SettingChoice('classic', 'Klassisch'), SettingChoice('arachne', 'Arachne (variable Breite)')],
      terms: 'perimeter generator'),
  _bool('detect_thin_wall', 'Dünne Wände erkennen',
      'Druckt Stellen, die für zwei Linien zu schmal sind, mit einer einzelnen Linie statt sie wegzulassen.', _walls,
      terms: 'schmal dünn'),
  _choice('wall_sequence', 'Wandreihenfolge',
      'Außen zuerst ergibt genauere Maße, innen zuerst schönere Überhänge.', _walls,
      const [
        SettingChoice('inner wall/outer wall', 'Innen, dann außen'),
        SettingChoice('outer wall/inner wall', 'Außen, dann innen'),
        SettingChoice('inner-outer-inner wall', 'Innen-außen-innen'),
      ],
      engineDefault: 'inner wall/outer wall', terms: 'reihenfolge perimeter order'),
  _bool('is_infill_first', 'Füllung vor Wänden',
      'Druckt die Füllung vor den Wänden. Stabiler, kann aber Abdrücke auf der Außenseite hinterlassen.', _walls,
      engineDefault: false, advanced: true, terms: 'reihenfolge'),
  _choice('wall_direction', 'Wandrichtung',
      'Druckrichtung der Wände. Automatisch ist meist richtig.', _walls,
      const [SettingChoice('auto', 'Automatisch'), SettingChoice('ccw', 'Gegen Uhrzeigersinn'), SettingChoice('cw', 'Im Uhrzeigersinn')],
      engineDefault: 'auto', advanced: true),
  _bool('detect_overhang_wall', 'Überhangwände erkennen',
      'Erkennt überhängende Wände und druckt sie langsamer und mit mehr Kühlung.', _walls,
      advanced: true, terms: 'überhang overhang'),
  _bool('extra_perimeters_on_overhangs', 'Zusatzwände an Überhängen',
      'Fügt an steilen Überhängen zusätzliche Wände ein, damit sie besser halten.', _walls,
      engineDefault: false, advanced: true, terms: 'überhang overhang'),
  _bool('only_one_wall_top', 'Nur eine Wand oben',
      'Auf der obersten Fläche nur eine Wand. Gibt der Oberseite mehr Platz für schöne Füllung.', _walls,
      advanced: true, terms: 'oberseite top'),
  _bool('only_one_wall_first_layer', 'Nur eine Wand in der ersten Schicht',
      'Die erste Schicht bekommt nur eine Wand. Hilft bei sehr kleinen Teilen.', _walls,
      engineDefault: false, advanced: true, terms: 'erste schicht'),
  _choice('ensure_vertical_shell_thickness', 'Senkrechte Wandstärke sichern',
      'Fügt bei schrägen Flächen massive Füllung hinzu, damit die Wand nicht dünn wird.', _walls,
      const [
        SettingChoice('none', 'Aus'),
        SettingChoice('ensure_critical_only', 'Nur kritische Stellen'),
        SettingChoice('ensure_moderate', 'Mäßig'),
        SettingChoice('ensure_all', 'Überall'),
      ],
      engineDefault: 'ensure_all', advanced: true, terms: 'schale shell'),
  _pct('infill_wall_overlap', 'Überlappung Füllung/Wand',
      'Wie weit die Füllung in die Wände ragt. Mehr verbindet besser, kann aber außen durchdrücken.', _walls,
      max: 50, advanced: true, terms: 'überlappung overlap'),
  _pct('min_bead_width', 'Minimale Linienbreite (Arachne)',
      'Kleinste Linienbreite, die Arachne für dünne Stellen nutzt, in Prozent der Düse.', _walls,
      min: 5, max: 100, engineDefault: 85.0, advanced: true, showIf: const ShowIf('wall_generator', any: ['arachne'])),
  _pct('min_feature_size', 'Kleinste Detailgröße (Arachne)',
      'Details schmaler als dieser Anteil der Düse werden weggelassen.', _walls,
      min: 0, max: 100, engineDefault: 25.0, advanced: true, showIf: const ShowIf('wall_generator', any: ['arachne'])),
  _dec('wall_transition_angle', 'Übergangswinkel (Arachne)',
      'Ab diesem Winkel wechselt Arachne zwischen unterschiedlich vielen Wänden.', _walls,
      min: 1, max: 59, step: 1, unit: '°', engineDefault: 10.0, advanced: true,
      showIf: const ShowIf('wall_generator', any: ['arachne'])),

  // Ober-/Unterseiten
  _int('top_shell_layers', 'Deckschichten oben',
      'Massive Schichten auf der Oberseite. Mehr schließt die Fläche sauberer.', _shells,
      min: 0, max: 30, terms: 'top layers oberseite'),
  _int('bottom_shell_layers', 'Bodenschichten',
      'Massive Schichten auf der Unterseite.', _shells,
      min: 0, max: 30, terms: 'bottom layers unterseite boden'),
  _dec('top_shell_thickness', 'Mindeststärke oben',
      'Mindestdicke der Oberseite. Bei dünnen Schichten werden automatisch mehr Deckschichten gedruckt.', _shells,
      max: 5, step: 0.1, advanced: true),
  _dec('bottom_shell_thickness', 'Mindeststärke unten',
      'Mindestdicke der Unterseite. 0 nutzt nur die Anzahl der Bodenschichten.', _shells,
      max: 5, step: 0.1, advanced: true),
  _choice('top_surface_pattern', 'Muster Oberseite',
      'Linienmuster der sichtbaren Oberseite. Monoton ergibt die gleichmäßigste Fläche.', _shells, _surfacePatterns,
      terms: 'top pattern'),
  _choice('bottom_surface_pattern', 'Muster Unterseite',
      'Linienmuster der Unterseite, die auf dem Bett liegt.', _shells, _surfacePatterns,
      terms: 'bottom pattern'),
  _choice('internal_solid_infill_pattern', 'Muster massive Füllung innen',
      'Muster der verdeckten massiven Schichten.', _shells, _surfacePatterns,
      engineDefault: 'monotonic', advanced: true),
  _pct('top_surface_density', 'Dichte Oberseite',
      'Unter 100 % bleibt die Oberseite offen, etwa für dekorative Gitter.', _shells,
      min: 10, max: 100, engineDefault: 100.0, advanced: true),
  _dec('top_solid_infill_flow_ratio', 'Fluss Oberseite',
      'Materialmenge auf der Oberseite. Etwas weniger verhindert Wülste, etwas mehr schließt Lücken.', _shells,
      min: 0.5, max: 1.5, unit: '', engineDefault: 1.0, advanced: true, terms: 'flow'),
  _dec('bottom_solid_infill_flow_ratio', 'Fluss Unterseite',
      'Materialmenge auf der Unterseite.', _shells,
      min: 0.5, max: 1.5, unit: '', engineDefault: 1.0, advanced: true, terms: 'flow'),

  // Füllung
  _pct('sparse_infill_density', 'Fülldichte',
      'Wie viel vom Inneren gefüllt wird. 10–20 % reichen für Deko, 40 % und mehr für belastete Teile.', _infill,
      terms: 'füllung infill dichte innen'),
  _choice('sparse_infill_pattern', 'Füllmuster',
      'Form der inneren Struktur. Gyroid ist in alle Richtungen stabil, Gitter und Kreuzschraffur sind schnell.', _infill,
      const [
        SettingChoice('crosshatch', 'Kreuzschraffur'),
        SettingChoice('grid', 'Gitter'),
        SettingChoice('gyroid', 'Gyroid'),
        SettingChoice('cubic', 'Kubisch'),
        SettingChoice('adaptivecubic', 'Adaptiv kubisch'),
        SettingChoice('triangles', 'Dreiecke'),
        SettingChoice('tri-hexagon', 'Tri-Hexagon'),
        SettingChoice('honeycomb', 'Waben'),
        SettingChoice('3dhoneycomb', '3D-Waben'),
        SettingChoice('lightning', 'Blitz (nur Stütze für oben)'),
        SettingChoice('rectilinear', 'Geradlinig'),
        SettingChoice('alignedrectilinear', 'Geradlinig ausgerichtet'),
        SettingChoice('line', 'Linien'),
        SettingChoice('zigzag', 'Zickzack'),
        SettingChoice('concentric', 'Konzentrisch'),
        SettingChoice('hilbertcurve', 'Hilbert-Kurve'),
        SettingChoice('archimedeanchords', 'Archimedische Sehnen'),
        SettingChoice('octagramspiral', 'Oktagramm-Spirale'),
      ],
      terms: 'infill pattern muster gyroid'),
  _dec('infill_direction', 'Füllwinkel',
      'Richtung der Fülllinien.', _infill,
      min: 0, max: 360, step: 5, unit: '°', advanced: true),
  _bool('infill_combination', 'Füllung zusammenfassen',
      'Druckt die Füllung nur jede zweite Schicht doppelt so dick. Schneller, bei gleicher Optik.', _infill,
      advanced: true, terms: 'combine schneller'),
  _dec('minimum_sparse_infill_area', 'Kleinste Füllfläche',
      'Kleinere Füllbereiche werden massiv gedruckt.', _infill,
      max: 100, step: 1, unit: 'mm²', advanced: true),
  _choice('gap_fill_target', 'Lücken füllen',
      'Wo schmale Lücken zwischen Wänden mit Material geschlossen werden.', _infill,
      const [SettingChoice('everywhere', 'Überall'), SettingChoice('topbottom', 'Nur oben und unten'), SettingChoice('nowhere', 'Nirgends')],
      engineDefault: 'nowhere', advanced: true, terms: 'gap fill'),
  _dec('filter_out_gap_fill', 'Kleine Lücken ignorieren',
      'Lückenfüllung kürzer als dieser Wert wird weggelassen.', _infill,
      max: 5, step: 0.1, engineDefault: 0.0, advanced: true),
  _bool('reduce_infill_retraction', 'Weniger Rückzug in der Füllung',
      'Spart Rückzüge innerhalb der Füllung, wo Fäden nicht sichtbar sind.', _infill,
      advanced: true, terms: 'retraction'),

  // Geschwindigkeit
  _speedDef('outer_wall_speed', 'Außenwand', 'Tempo der sichtbaren Außenwand. Langsamer wirkt sauberer.'),
  _speedDef('inner_wall_speed', 'Innenwände', 'Tempo der verdeckten Wände.'),
  _speedDef('sparse_infill_speed', 'Füllung', 'Tempo der inneren Füllung.'),
  _speedDef('internal_solid_infill_speed', 'Massive Füllung', 'Tempo der verdeckten massiven Schichten.'),
  _speedDef('top_surface_speed', 'Oberseite', 'Tempo der obersten Fläche. Langsamer ergibt eine glattere Oberseite.'),
  _speedDef('gap_infill_speed', 'Lückenfüllung', 'Tempo für schmale Lücken zwischen Wänden.', advanced: true),
  _speedDef('support_speed', 'Stützen', 'Tempo der Stützstrukturen.', advanced: true),
  _speedDef('support_interface_speed', 'Stützen-Kontaktfläche', 'Tempo der Schicht direkt unter dem Modell.', advanced: true),
  _speedDef('bridge_speed', 'Brücken', 'Tempo über freie Strecken. Wird nicht mit dem Geschwindigkeitsregler skaliert.',
      scales: false, advanced: true),
  _speedDef('initial_layer_speed', 'Erste Schicht', 'Tempo der Wände in der ersten Schicht. Langsam haftet besser.',
      scales: false, max: 200),
  _speedDef('initial_layer_infill_speed', 'Füllung erste Schicht', 'Tempo der Füllung in der ersten Schicht.',
      scales: false, max: 300, advanced: true),
  _speedDef('travel_speed', 'Leerfahrten', 'Tempo ohne Druck. Wird nicht mit dem Geschwindigkeitsregler skaliert.',
      scales: false, max: 1000, advanced: true, terms: 'travel'),
  _bool('enable_overhang_speed', 'Überhänge verlangsamen',
      'Druckt Überhänge je nach Steilheit langsamer, damit sie nicht absacken.', _speed,
      engineDefault: true, advanced: true, terms: 'überhang overhang'),
  _speedDef('overhang_2_4_speed', 'Überhang 25–50 %', 'Tempo für leicht überhängende Wände.',
      scales: false, advanced: true, showIf: _overhangSpeedOn, terms: 'überhang'),
  _speedDef('overhang_3_4_speed', 'Überhang 50–75 %', 'Tempo für deutlich überhängende Wände.',
      scales: false, advanced: true, showIf: _overhangSpeedOn, terms: 'überhang'),
  _speedDef('overhang_4_4_speed', 'Überhang 75–100 %', 'Tempo für fast waagerechte Überhänge.',
      scales: false, advanced: true, showIf: _overhangSpeedOn, terms: 'überhang'),
  _accel('default_acceleration', 'Beschleunigung allgemein', 'Wie schnell der Drucker auf Tempo kommt. Weniger verringert Schwingungen (Ghosting).'),
  _accel('outer_wall_acceleration', 'Beschleunigung Außenwand', 'Beschleunigung der sichtbaren Außenwand.'),
  _accel('inner_wall_acceleration', 'Beschleunigung Innenwände', 'Beschleunigung der verdeckten Wände.', engineDefault: 10000.0),
  _accel('top_surface_acceleration', 'Beschleunigung Oberseite', 'Beschleunigung der obersten Fläche.'),
  _accel('initial_layer_acceleration', 'Beschleunigung erste Schicht', 'Beschleunigung in der ersten Schicht.'),
  _accel('travel_acceleration', 'Beschleunigung Leerfahrten', 'Beschleunigung ohne Druck.', engineDefault: 10000.0),

  // Stützen
  _bool('enable_support', 'Stützen', 'Baut Stützstrukturen unter Überhängen, die sonst in die Luft gedruckt würden.', _support,
      terms: 'support stütze überhang'),
  _choice('support_type', 'Stützenart',
      'Normal stützt senkrecht und ist leicht zu entfernen, Baum verzweigt sich und spart Material.', _support,
      const [SettingChoice('normal(auto)', 'Normal'), SettingChoice('tree(auto)', 'Baum')],
      showIf: _supportOn, terms: 'tree baum'),
  _choice('support_style', 'Stützenstil',
      'Feinform der Stütze. Standard passt meist.', _support,
      const [
        SettingChoice('default', 'Standard'),
        SettingChoice('grid', 'Gitter'),
        SettingChoice('snug', 'Eng anliegend'),
        SettingChoice('organic', 'Organisch'),
        SettingChoice('tree_slim', 'Baum schlank'),
        SettingChoice('tree_strong', 'Baum kräftig'),
        SettingChoice('tree_hybrid', 'Baum hybrid'),
      ],
      showIf: _supportOn, advanced: true),
  _int('support_threshold_angle', 'Überhangwinkel',
      'Flächen flacher als dieser Winkel (von der Waagerechten) bekommen Stützen. Größer heißt mehr Stützen.', _support,
      min: 0, max: 90, unit: '°', showIf: _supportOn, terms: 'winkel threshold'),
  _bool('support_on_build_plate_only', 'Nur vom Druckbett',
      'Stützen stehen nur auf dem Bett, nie auf dem Modell. Schont die Oberfläche.', _support,
      showIf: _supportOn, terms: 'bett plate'),
  _dec('support_top_z_distance', 'Abstand oben',
      'Lücke zwischen Stütze und Modell. Größer löst sich leichter, kleiner gibt eine schönere Unterseite.', _support,
      max: 1, step: 0.01, showIf: _supportOn, terms: 'z abstand'),
  _dec('support_bottom_z_distance', 'Abstand unten',
      'Lücke, wo die Stütze auf dem Modell steht.', _support,
      max: 1, step: 0.01, showIf: _supportOn, advanced: true),
  _dec('support_object_xy_distance', 'Seitlicher Abstand',
      'Abstand der Stütze zu den Seitenwänden des Modells.', _support,
      max: 3, step: 0.05, showIf: _supportOn, terms: 'xy abstand'),
  _choice('support_base_pattern', 'Stützenmuster',
      'Muster im Inneren der Stütze.', _support,
      const [
        SettingChoice('default', 'Standard'),
        SettingChoice('rectilinear', 'Geradlinig'),
        SettingChoice('rectilinear-grid', 'Gitter'),
        SettingChoice('honeycomb', 'Waben'),
        SettingChoice('lightning', 'Blitz'),
        SettingChoice('hollow', 'Hohl'),
      ],
      showIf: _supportOn, advanced: true),
  _dec('support_base_pattern_spacing', 'Linienabstand Stütze',
      'Abstand der Stützlinien. Größer spart Material, kleiner trägt besser.', _support,
      min: 0.5, max: 10, step: 0.1, showIf: _supportOn, advanced: true),
  _int('support_interface_top_layers', 'Kontaktschichten oben',
      'Dichte Schichten direkt unter dem Modell für eine glattere Unterseite.', _support,
      max: 10, showIf: _supportOn, advanced: true),
  _int('support_interface_bottom_layers', 'Kontaktschichten unten',
      'Dichte Schichten, wo die Stütze auf dem Modell steht.', _support,
      max: 10, showIf: _supportOn, advanced: true),
  _choice('support_interface_pattern', 'Muster Kontaktschicht',
      'Linienmuster der Kontaktschichten.', _support,
      const [
        SettingChoice('auto', 'Automatisch'),
        SettingChoice('rectilinear', 'Geradlinig'),
        SettingChoice('concentric', 'Konzentrisch'),
        SettingChoice('rectilinear_interlaced', 'Geradlinig verschränkt'),
        SettingChoice('grid', 'Gitter'),
      ],
      showIf: _supportOn, advanced: true),
  _dec('support_interface_spacing', 'Linienabstand Kontaktschicht',
      'Abstand der Linien in den Kontaktschichten. 0 ist massiv.', _support,
      max: 5, step: 0.1, showIf: _supportOn, advanced: true),
  _dec('support_expansion', 'Stützen verbreitern',
      'Macht die Stützfläche seitlich größer.', _support,
      min: -5, max: 5, step: 0.1, showIf: _supportOn, advanced: true),
  _dec('tree_support_branch_angle', 'Astwinkel (Baum)',
      'Wie schräg Äste wachsen dürfen. Größer erreicht mehr, ist aber weniger stabil.', _support,
      min: 0, max: 60, step: 1, unit: '°', showIf: const ShowIf('support_type', any: ['tree(auto)']), advanced: true),
  _dec('tree_support_branch_diameter', 'Astdurchmesser (Baum)',
      'Dicke der Äste. Dicker ist stabiler.', _support,
      min: 1, max: 10, step: 0.5, showIf: const ShowIf('support_type', any: ['tree(auto)']), advanced: true),
  _int('tree_support_wall_count', 'Astwände (Baum)',
      'Wände pro Ast. 0 lässt den Slicer entscheiden.', _support,
      max: 5, showIf: const ShowIf('support_type', any: ['tree(auto)']), advanced: true),
  _bool('support_critical_regions_only', 'Nur kritische Stellen',
      'Stützt nur scharfe Kanten und frei schwebende Teile.', _support,
      engineDefault: false, showIf: _supportOn, advanced: true),
  _bool('support_remove_small_overhang', 'Kleine Überhänge ignorieren',
      'Sehr kleine Überhänge bekommen keine Stütze.', _support,
      engineDefault: true, showIf: _supportOn, advanced: true),
  _bool('bridge_no_support', 'Brücken nicht stützen',
      'Waagerechte Brücken zwischen zwei Wänden ohne Stützen drucken.', _support,
      showIf: _supportOn, advanced: true, terms: 'brücke bridge'),

  // Haftung
  _choice('brim_type', 'Brim',
      'Ein flacher Rand um das Modell, der es auf dem Bett hält. Hilft gegen Ablösen und Verziehen.', _adhesion,
      const [
        SettingChoice('auto_brim', 'Automatisch'),
        SettingChoice('no_brim', 'Aus'),
        SettingChoice('outer_only', 'Außen'),
        SettingChoice('inner_only', 'Innen'),
        SettingChoice('outer_and_inner', 'Außen und innen'),
        SettingChoice('brim_ears', 'Mausohren'),
      ],
      engineDefault: 'auto_brim', terms: 'rand haftung warping'),
  _dec('brim_width', 'Brim-Breite',
      'Wie breit der Rand ist.', _adhesion,
      max: 30, step: 0.5, showIf: const ShowIf('brim_type', not: ['no_brim', 'auto_brim'])),
  _dec('brim_object_gap', 'Brim-Abstand',
      'Lücke zwischen Rand und Modell. Größer lässt sich leichter ablösen.', _adhesion,
      max: 2, step: 0.05, showIf: const ShowIf('brim_type', not: ['no_brim']), advanced: true),
  _int('skirt_loops', 'Skirt-Runden',
      'Linien um das Modell herum, die die Düse vor dem Druck füllen. 0 ist aus.', _adhesion,
      max: 10, terms: 'skirt umrandung'),
  _dec('skirt_distance', 'Skirt-Abstand',
      'Abstand der Skirt-Linien zum Modell.', _adhesion,
      max: 20, step: 0.5, showIf: const ShowIf('skirt_loops', not: [0]), advanced: true),
  _int('skirt_height', 'Skirt-Höhe',
      'Wie viele Schichten hoch der Skirt gedruckt wird.', _adhesion,
      min: 1, max: 20, unit: 'Schichten', showIf: const ShowIf('skirt_loops', not: [0]), advanced: true),
  _choice('draft_shield', 'Windschutz',
      'Eine dünne Wand um das Modell, die Zugluft abhält. Nützlich bei ABS.', _adhesion,
      const [SettingChoice('disabled', 'Aus'), SettingChoice('enabled', 'An')],
      showIf: const ShowIf('skirt_loops', not: [0]), advanced: true),
  _int('raft_layers', 'Raft-Schichten',
      'Eine Unterlage aus mehreren Schichten unter dem Modell. Für sehr kleine Auflageflächen oder verzogene Betten.', _adhesion,
      max: 10, terms: 'raft floß unterlage'),
  _dec('raft_contact_distance', 'Raft-Abstand',
      'Lücke zwischen Raft und Modell.', _adhesion,
      max: 1, step: 0.01, engineDefault: 0.1, showIf: const ShowIf('raft_layers', not: [0]), advanced: true),
  _dec('elefant_foot_compensation', 'Elefantenfuß-Ausgleich',
      'Zieht die erste Schicht etwas ein, damit sie nicht breiter als der Rest wird.', _adhesion,
      max: 1, step: 0.01, advanced: true, terms: 'elephant foot erste schicht'),

  // Kühlung
  _int('fan_min_speed', 'Lüfter minimal',
      'Bauteillüfter bei langen Schichten.', _cooling,
      unit: '%', source: SettingSource.filament, terms: 'fan lüfter kühlung'),
  _int('fan_max_speed', 'Lüfter maximal',
      'Bauteillüfter bei kurzen Schichten, die schnell abkühlen müssen.', _cooling,
      unit: '%', source: SettingSource.filament, terms: 'fan lüfter kühlung'),
  _int('fan_cooling_layer_time', 'Volle Kühlung unter',
      'Schichten, die schneller als diese Zeit fertig sind, bekommen mehr Lüfter.', _cooling,
      max: 300, unit: 's', source: SettingSource.filament, advanced: true),
  _int('close_fan_the_first_x_layers', 'Lüfter aus für erste Schichten',
      'So viele Schichten am Anfang ohne Lüfter, für bessere Haftung.', _cooling,
      max: 10, unit: 'Schichten', source: SettingSource.filament),
  _int('full_fan_speed_layer', 'Volle Lüfterleistung ab Schicht',
      'Der Lüfter fährt bis zu dieser Schicht langsam hoch. 0 heißt sofort.', _cooling,
      max: 100, source: SettingSource.filament, advanced: true),
  _int('overhang_fan_speed', 'Lüfter bei Überhängen',
      'Lüfterleistung für Überhänge und Brücken.', _cooling,
      unit: '%', source: SettingSource.filament, terms: 'überhang brücke'),
  _choice('overhang_fan_threshold', 'Überhang-Kühlung ab',
      'Ab welchem Überhanganteil die Überhang-Lüfterleistung gilt.', _cooling,
      const [
        SettingChoice('0%', 'Immer'),
        SettingChoice('10%', '10 %'),
        SettingChoice('25%', '25 %'),
        SettingChoice('50%', '50 %'),
        SettingChoice('75%', '75 %'),
        SettingChoice('95%', '95 %'),
      ],
      source: SettingSource.filament, advanced: true),
  _int('additional_cooling_fan_speed', 'Zusatzlüfter (Seite)',
      'Der große Seitenlüfter des P1S. Hilft bei PLA, bei ABS lieber aus.', _cooling,
      unit: '%', source: SettingSource.filament, engineDefault: 0, terms: 'aux lüfter'),
  _bool('slow_down_for_layer_cooling', 'Für Kühlung verlangsamen',
      'Kleine Schichten werden langsamer gedruckt, damit sie abkühlen können.', _cooling,
      source: SettingSource.filament),
  _int('slow_down_layer_time', 'Mindestzeit pro Schicht',
      'Jede Schicht dauert mindestens so lange. Wichtig für kleine Spitzen.', _cooling,
      max: 60, unit: 's', source: SettingSource.filament, showIf: const ShowIf('slow_down_for_layer_cooling', any: [true])),
  _int('slow_down_min_speed', 'Mindesttempo beim Abkühlen',
      'Langsamer wird beim Abkühlen nie gedruckt.', _cooling,
      max: 100, unit: 'mm/s', source: SettingSource.filament, advanced: true,
      showIf: const ShowIf('slow_down_for_layer_cooling', any: [true])),
  _bool('reduce_fan_stop_start_freq', 'Lüfter nicht ständig schalten',
      'Lässt den Lüfter laufen, statt ihn immer wieder an- und auszuschalten.', _cooling,
      source: SettingSource.filament, advanced: true),
  _int('during_print_exhaust_fan_speed', 'Abluftlüfter',
      'Abluftlüfter während des Drucks.', _cooling,
      unit: '%', source: SettingSource.filament, advanced: true, terms: 'exhaust abluft'),

  // Temperatur
  _int('nozzle_temperature', 'Düsentemperatur',
      'Temperatur der Düse. Heißer fließt besser und haftet stärker zwischen Schichten, kann aber fädeln.', _temp,
      min: 150, max: 300, unit: '°C', source: SettingSource.filament, terms: 'hotend düse nozzle'),
  _int('nozzle_temperature_initial_layer', 'Düse erste Schicht',
      'Düsentemperatur in der ersten Schicht.', _temp,
      min: 150, max: 300, unit: '°C', source: SettingSource.filament),
  _int('textured_plate_temp', 'Druckbett',
      'Temperatur der texturierten PEI-Platte.', _temp,
      max: 120, unit: '°C', source: SettingSource.filament, terms: 'bett plate heizbett'),
  _int('textured_plate_temp_initial_layer', 'Druckbett erste Schicht',
      'Betttemperatur in der ersten Schicht.', _temp,
      max: 120, unit: '°C', source: SettingSource.filament, terms: 'bett plate'),

  // Filament und Rückzug
  _dec('filament_flow_ratio', 'Flussrate',
      'Faktor für die geförderte Materialmenge. Bei Überextrusion senken, bei Lücken erhöhen.', _filament,
      min: 0.5, max: 1.5, step: 0.01, unit: '', source: SettingSource.filament, terms: 'flow extrusion multiplier'),
  _dec('filament_max_volumetric_speed', 'Maximaler Volumenfluss',
      'Wie viel Material die Düse pro Sekunde schmelzen kann. Begrenzt hohe Geschwindigkeiten.', _filament,
      min: 1, max: 50, step: 0.5, unit: 'mm³/s', source: SettingSource.filament, terms: 'volumetric durchfluss'),
  _bool('enable_pressure_advance', 'Pressure Advance',
      'Gleicht den Druck in der Düse an Ecken aus. Der P1S kalibriert das sonst selbst.', _filament,
      source: SettingSource.filament, engineDefault: false, advanced: true, terms: 'linear advance'),
  _dec('pressure_advance', 'Pressure-Advance-Wert',
      'Stärke des Druckausgleichs.', _filament,
      max: 1, step: 0.001, unit: '', source: SettingSource.filament, engineDefault: 0.02, advanced: true,
      showIf: const ShowIf('enable_pressure_advance', any: [true])),
  _dec('filament_retraction_length', 'Rückzuglänge',
      'Wie weit das Filament vor Leerfahrten zurückgezogen wird. Mehr verhindert Fäden.', _filament,
      max: 10, step: 0.1, source: SettingSource.filament, printerFallback: 'retraction_length', terms: 'retraction stringing fäden'),
  _dec('filament_retraction_speed', 'Rückzuggeschwindigkeit',
      'Tempo des Rückzugs.', _filament,
      min: 1, max: 100, step: 1, unit: 'mm/s', source: SettingSource.filament, printerFallback: 'retraction_speed', advanced: true),
  _dec('filament_deretraction_speed', 'Wiedereinzug-Geschwindigkeit',
      'Tempo beim Zurückschieben. 0 nutzt das Rückzugtempo.', _filament,
      max: 100, step: 1, unit: 'mm/s', source: SettingSource.filament, printerFallback: 'deretraction_speed', advanced: true),
  _dec('filament_retraction_minimum_travel', 'Rückzug ab Fahrtlänge',
      'Kürzere Leerfahrten lösen keinen Rückzug aus.', _filament,
      max: 20, step: 0.5, source: SettingSource.filament, printerFallback: 'retraction_minimum_travel', advanced: true),
  _bool('filament_retract_when_changing_layer', 'Rückzug beim Schichtwechsel',
      'Zieht das Filament bei jedem Schichtwechsel zurück.', _filament,
      source: SettingSource.filament, printerFallback: 'retract_when_changing_layer', advanced: true),
  _dec('filament_z_hop', 'Z-Hop',
      'Hebt die Düse bei Leerfahrten an, damit sie nicht über das Modell kratzt.', _filament,
      max: 2, step: 0.1, source: SettingSource.filament, printerFallback: 'z_hop', terms: 'anheben lift'),
  _choice('filament_z_hop_types', 'Z-Hop-Art',
      'Wie die Düse angehoben wird.', _filament,
      const [
        SettingChoice('Auto Lift', 'Automatisch'),
        SettingChoice('Normal Lift', 'Gerade'),
        SettingChoice('Slope Lift', 'Schräg'),
        SettingChoice('Spiral Lift', 'Spirale'),
      ],
      source: SettingSource.filament, printerFallback: 'z_hop_types', advanced: true),
  _bool('filament_wipe', 'Wischen',
      'Wischt die Düse beim Rückzug über die gedruckte Linie. Weniger Tropfen.', _filament,
      source: SettingSource.filament, printerFallback: 'wipe', advanced: true, terms: 'wipe'),
  _dec('filament_wipe_distance', 'Wischweg',
      'Länge der Wischbewegung.', _filament,
      max: 10, step: 0.5, source: SettingSource.filament, printerFallback: 'wipe_distance', engineDefault: 1.0, advanced: true, showIf: _wipeOn),
  _pct('filament_shrink', 'Schrumpfausgleich XY',
      'Schrumpft das Material beim Abkühlen, wird das Modell entsprechend größer gedruckt. 100 % ist aus.', _filament,
      min: 90, max: 110, step: 0.1, source: SettingSource.filament, advanced: true, terms: 'schrumpf shrinkage'),

  // Oberfläche und Spezial
  _choice('fuzzy_skin', 'Fuzzy Skin',
      'Zittert die Wände leicht, sodass eine raue, griffige Oberfläche entsteht. Versteckt Schichtlinien.', _special,
      const [
        SettingChoice('none', 'Aus'),
        SettingChoice('external', 'Außenkontur'),
        SettingChoice('all', 'Außen und Löcher'),
        SettingChoice('allwalls', 'Alle Wände'),
      ],
      engineDefault: 'none', terms: 'rau textur struktur fuzzy'),
  _dec('fuzzy_skin_thickness', 'Fuzzy-Dicke',
      'Wie weit die Wand ausschlägt. Unter der Linienbreite bleiben.', _special,
      max: 1, step: 0.05, engineDefault: 0.2, showIf: _fuzzyOn),
  _dec('fuzzy_skin_point_distance', 'Fuzzy-Punktabstand',
      'Abstand der Zitterpunkte. Kleiner wirkt feiner und rauer.', _special,
      min: 0.1, max: 5, step: 0.05, engineDefault: 0.3, showIf: _fuzzyOn),
  _bool('fuzzy_skin_first_layer', 'Fuzzy auch erste Schicht',
      'Rau auch in der ersten Schicht. Meist besser aus, damit das Modell gerade steht.', _special,
      engineDefault: false, showIf: _fuzzyOn, advanced: true),
  _choice('fuzzy_skin_noise_type', 'Fuzzy-Rauschart',
      'Art des Zufallsmusters. Klassisch ist gleichmäßig rau, Perlin wirkt organisch.', _special,
      const [
        SettingChoice('classic', 'Klassisch'),
        SettingChoice('perlin', 'Perlin'),
        SettingChoice('billow', 'Wolkig'),
        SettingChoice('ridgedmulti', 'Gratig'),
        SettingChoice('voronoi', 'Voronoi'),
      ],
      engineDefault: 'classic', showIf: _fuzzyOn, advanced: true),
  _choice('ironing_type', 'Bügeln',
      'Fährt nach der Oberseite noch einmal mit wenig Material darüber. Ergibt eine sehr glatte Fläche, dauert länger.', _special,
      const [
        SettingChoice('no ironing', 'Aus'),
        SettingChoice('top', 'Alle Oberseiten'),
        SettingChoice('topmost', 'Nur oberste Fläche'),
        SettingChoice('solid', 'Alle massiven Schichten'),
      ],
      terms: 'ironing glatt'),
  _choice('ironing_pattern', 'Bügelmuster', 'Linienmuster beim Bügeln.', _special,
      const [SettingChoice('rectilinear', 'Geradlinig'), SettingChoice('concentric', 'Konzentrisch')],
      engineDefault: 'rectilinear', showIf: _ironingOn, advanced: true),
  _pct('ironing_flow', 'Bügelfluss',
      'Materialmenge beim Bügeln. Zu viel gibt Wülste, zu wenig lässt Rillen.', _special,
      max: 50, showIf: _ironingOn),
  _dec('ironing_spacing', 'Bügel-Linienabstand',
      'Abstand der Bügellinien. Kleiner ist glatter, dauert länger.', _special,
      min: 0.05, max: 1, step: 0.01, showIf: _ironingOn),
  _dec('ironing_speed', 'Bügeltempo', 'Tempo beim Bügeln.', _special,
      min: 5, max: 200, step: 5, unit: 'mm/s', showIf: _ironingOn),
  _dec('ironing_inset', 'Bügel-Randabstand',
      'Abstand vom Rand der Fläche, der nicht gebügelt wird.', _special,
      max: 1, step: 0.01, showIf: _ironingOn, advanced: true),
  _choice('seam_position', 'Nahtposition',
      'Wo jede Runde beginnt und endet. Hinten versteckt die Naht, zufällig verteilt sie.', _special,
      const [
        SettingChoice('aligned', 'Ausgerichtet'),
        SettingChoice('aligned_back', 'Ausgerichtet hinten'),
        SettingChoice('nearest', 'Nächste'),
        SettingChoice('back', 'Hinten'),
        SettingChoice('random', 'Zufällig'),
      ],
      terms: 'seam naht'),
  _choice('seam_slope_type', 'Schalnaht (Scarf)',
      'Beginnt jede Runde mit einer flachen Rampe, sodass die Naht fast verschwindet.', _special,
      const [SettingChoice('none', 'Aus'), SettingChoice('external', 'Nur außen'), SettingChoice('all', 'Alle Wände')],
      engineDefault: 'none', advanced: true, terms: 'scarf seam naht'),
  _bool('staggered_inner_seams', 'Innennähte versetzen',
      'Versetzt die Nähte der Innenwände, damit keine durchgehende Schwachstelle entsteht.', _special,
      engineDefault: false, advanced: true, terms: 'naht seam'),
  _bool('spiral_mode', 'Vasenmodus',
      'Druckt nur eine Außenwand als durchgehende Spirale ohne Oberseite. Für Vasen und Becher.', _special,
      terms: 'spiral vase'),
  _bool('spiral_mode_smooth', 'Vasenmodus glätten',
      'Glättet den Übergang in die Spirale.', _special,
      engineDefault: false, showIf: const ShowIf('spiral_mode', any: [true]), advanced: true),
  _bool('make_overhang_printable', 'Überhänge druckbar machen',
      'Formt steile Überhänge zu druckbaren Kegeln um. Verändert die Form.', _special,
      engineDefault: false, advanced: true, terms: 'überhang kegel'),
  _bool('hole_to_polyhole', 'Löcher als Vielecke',
      'Druckt waagerechte Löcher als Vielecke, damit sie maßgenauer werden.', _special,
      engineDefault: false, advanced: true, terms: 'polyhole loch'),
  _choice('print_sequence', 'Druckreihenfolge',
      'Bei mehreren Teilen: alle Schicht für Schicht oder eins nach dem anderen.', _special,
      const [SettingChoice('by layer', 'Schichtweise'), SettingChoice('by object', 'Objekt für Objekt')],
      advanced: true),
]);

final Map<String, SettingDef> settingsByKey = {for (final def in settingDefs) def.key: def};

SettingDef? settingDef(String key) => settingsByKey[key];

List<SettingDef> settingsIn(SettingCategory category) => [for (final def in settingDefs) if (def.category == category) def];
