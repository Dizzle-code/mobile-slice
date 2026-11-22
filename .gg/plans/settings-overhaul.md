# Einstellungen, Presets, Skalierung, schönere Vorschau, Schriftwahl

## Ziel
- Fuzzy Skin, Modellgröße, Druckgeschwindigkeit und ein kuratierter Satz von rund 120 Slicer-Einstellungen mit deutschen Namen und kurzer Erklärung.
- Presets für typische Drucke (z. B. „Feine dünne Wände“, „Technisch“) als Ausgangspunkt, die man danach weiter anpassen kann, dazu eigene Presets.
- Die Einstellungen sind durchsuchbar, nach Kategorien geordnet und trotz der Menge übersichtlich.
- Die 3D-Vorschau ist glatt statt verpixelt; die Drehgesten sind horizontal und vertikal umgekehrt.
- In den App-Einstellungen ist die Schrift wählbar: Pixelify Sans, Atkinson Hyperlegible oder System (Roboto).

## Ansatz

**Einstellungsmodell (Dart)**
- `lib/engine/setting_defs.dart`: eine Liste `SettingDef` mit
  - OrcaSlicer-Schlüssel, Bezeichnung, Hilfetext, Suchbegriffe, Kategorie
  - Typ (int, float, Prozent, bool, Auswahl), Einheit, Min/Max/Schritt, Auswahlwerte mit deutschen Labels
  - Quelle (Prozess- oder Filamentprofil), Engine-Standardwert für Schlüssel, die im Profil fehlen (z. B. `fuzzy_skin`)
  - `advanced`-Flag und `visibleIf` (Abhängigkeiten, z. B. Fuzzy-Skin-Dicke nur bei aktivem Fuzzy Skin)
- Kategorien:
  - Qualität
  - Wände
  - Ober-/Unterseiten
  - Füllung
  - Geschwindigkeit
  - Stützen
  - Haftung (Brim/Skirt/Raft)
  - Kühlung
  - Temperatur
  - Filament und Rückzug
  - Oberfläche und Spezial (Fuzzy Skin, Bügeln, Naht, Vasenmodus)
- `lib/engine/profile_values.dart`: lädt die flachen Prozess- und Filament-JSONs aus den Assets, damit jede Zeile den Profilwert zeigt. Filamentwerte sind Arrays mit einem Element.
- `SliceSettings` wird umgebaut:
  - `processId`, `filamentId`, `values` (Map Schlüssel → Wert, nur Abweichungen), `speedPercent`, `presetId`
  - `overrides()` liefert die Werte als Engine-Strings, z. B. `"15%"` oder `"1"`.
  - Die Geschwindigkeits-Prozentzahl skaliert alle Druckgeschwindigkeiten des Profils, außer denen, die der Nutzer einzeln gesetzt hat.
  - `fromJson` übernimmt alte gespeicherte Werte (Füllung, Wände, Stützen, Brim).
- Schlüsselprüfung: `test/engine/orca_keys.txt` wird aus `PrintConfig.cpp` des gepinnten OrcaSlicer (WSL) erzeugt. Ein Test prüft, dass jeder Schlüssel existiert und jeder Auswahlwert gültig ist. Unbekannte Schlüssel lässt die Engine sonst scheitern.

**Presets**
- `lib/engine/presets.dart`: Ein `SlicePreset` hat ID, Name, Pixel-Icon, Kurzbeschreibung und Inhalt: Schichthöhe (Prozessprofil), `values` und `speedPercent`. Das Filament bleibt unberührt.
- Eingebaute Presets:

  | Preset | Kern |
  |---|---|
  | Standard | Profilwerte, keine Änderungen |
  | Schneller Entwurf | 0,28 mm, 10 % Füllung, 2 Wände, 130 % Geschwindigkeit |
  | Fein und detailliert | 0,12 mm, langsamere Außenwand, Naht hinten |
  | Feine dünne Wände | 0,12 mm, Arachne-Wandgenerator, Detektion dünner Wände an, 80 % Geschwindigkeit |
  | Technisch und stabil | 0,20 mm, 4 Wände, 40 % Gyroid, 5 Ober- und Unterschichten |
  | Glatte Oberseite | Bügeln an, monotone Oberseite |
  | Vase | Spiralvasenmodus, 0 % Füllung, 1 Wand, 0 Oberschichten |
  | Miniatur | 0,08 mm, Baumstützen, langsamer, kleiner Brim |
  | Fuzzy-Optik | Fuzzy Skin außen, 0,3 mm Dicke |

- Anwenden: Das Preset ersetzt Schichthöhe, `values` und Geschwindigkeit. Danach bleibt alles frei veränderbar.
- `presetId` merkt sich die Herkunft. Weichen die Werte ab, zeigt die App „Technisch · angepasst“ mit einem Knopf „Preset wiederherstellen“.
- Eigene Presets: „Aktuelle Einstellungen als Preset speichern“ mit Namen, umbenennen und löschen. Gespeichert wird in `lib/data/preset_store.dart` (JsonStore `presets`). Eigene Presets mit Schlüsseln, die nicht mehr in `SettingDef` vorkommen, werden beim Laden bereinigt.
- Platzierung:
  - Ganz oben im Modellbildschirm als waagerecht scrollbare Preset-Kacheln, das erste, was man vor dem Feinjustieren wählt.
  - Ganz oben im Einstellungs-Browser als eigener Abschnitt „Presets“ über den Kategorien, mit Speichern und Verwalten. Bei aktiver Suche verschwindet er, Presets sind aber auch suchbar.

**Modellgröße**
- Die CLI bekommt `--scale <Faktor>`. `load_model` skaliert vor `ensure_on_bed` und der Passt-Prüfung; das gilt für Vorschau und Slice.
- Die Engine wird in WSL neu gebaut (`build-window.cmd skip`) und mit `file` geprüft.
- In der App ist die Größe Teil des Modellbildschirms, nicht der globalen Einstellungen oder Presets:
  - Prozent, verbundene mm-Felder X/Y/Z (eins ändern, die anderen folgen) und „Auf Bett einpassen“.
  - Vorschau und Passt-Prüfung skalieren sofort in Dart; die Engine erhält den Faktor beim Slicen.
  - `EngineJob` bekommt ein `scale`-Feld, Kotlin reicht `--scale` weiter.

**Darstellung der Einstellungen**
- Modellbildschirm: oben die Preset-Kacheln, darunter das Panel „Schnelleinstellungen“ mit
  - Schichthöhe, Füllung, Stützen, Brim, Filament
  - Geschwindigkeit in %
  - Fuzzy Skin (an/aus)
  - Größe
  - Knopf „Alle Einstellungen · N geändert“
- Neuer Bildschirm `settings_browser_screen.dart`:
  - Oben ein Suchfeld und ein Filter „Nur geänderte“.
  - Ohne Suche: der Abschnitt „Presets“, darunter ein Kachelraster der Kategorien mit Pixel-Icon und Anzahl geänderter Werte.
  - Kategorieseite: Zeilen mit Name, aktuellem Wert und einem Markierungspunkt für geänderte Werte. Erweiterte Optionen sind hinter „Mehr anzeigen“ eingeklappt.
  - Suche: Treffer aus allen Kategorien und Presets mit Kategorie-Hinweis. Durchsucht werden Name, Hilfetext, Suchbegriffe und Schlüssel, ohne Rücksicht auf Groß-/Kleinschreibung und Umlaute.
- Antippen einer Zeile öffnet ein Pixel-Bottom-Sheet `setting_editor.dart`:
  - passender Regler, Stepper, Schalter oder Auswahl
  - Hilfetext
  - „Profilwert“ zum Zurücksetzen
- Dazu „Alles zurücksetzen“.
- Neue Widgets kommen nach `lib/ui/`: `pixel_search_field`, `pixel_sheet`, `pixel_stepper`.

**Vorschau**
- Der CPU-Rasterizer wird ersetzt:
  - Der Worker-Isolat projiziert die Dreiecke für die aktuelle Kamera.
  - Rückseiten werden verworfen, wenn die Normale eindeutig ist; die Dreiecke werden von hinten nach vorn sortiert.
  - Pro Dreieck wird eine weiche Beleuchtung berechnet: Hemisphärenlicht, Hauptlicht und Glanz, ohne harte Stufen.
  - Zurück kommen Positionen und Farben.
- Ein `CustomPainter` zeichnet Bett, Gitter (antialiased) und das Modell als `ui.Vertices` in voller Displayauflösung.
- Gesten: beide Drehrichtungen umgekehrt. Die Kamera nimmt einen Skalierungsfaktor für die Größenvorschau.

**Schriftwahl**
- Atkinson Hyperlegible (Regular/Bold, OFL) kommt aus `github.com/google/fonts/ofl/atkinsonhyperlegible` samt Lizenz nach `assets/fonts/`.
- `lib/data/app_settings.dart` (JsonStore `app_settings`) speichert die Schrift.
- `PixelTheme.text` liest die aktuelle Schrift samt Größenfaktor pro Schrift. Bei „System“ ist die Familie `null`.
- `MobileSliceApp` baut bei Wechsel neu auf.
- Im Einstellungsbildschirm kommt ein Abschnitt „Darstellung“ mit Auswahl und Vorschau hinzu; die Lizenzseite zeigt beide Schriftlizenzen.

## Risiken
- **Falsche Schlüssel oder Auswahlwerte lassen das Slicen scheitern.** Abhilfe: Schlüsseltest gegen die Quelle für Defs und Presets; den echten Slice-Lauf mit geänderten Werten prüfst du auf dem Handy über die Test-APK.
- **Sortierung von hinten nach vorn kann bei sich durchdringenden Flächen kleine Fehler zeigen.** Das ist für eine Vorschau akzeptabel.
- **Hohe Geschwindigkeit wird durch den maximalen Volumenfluss des Filaments begrenzt.** Der Hilfetext sagt das.
- **Der Engine-Neubau braucht WSL.** Der Schnellbuild nutzt den vorhandenen Baum.

## Prüfung
- `flutter analyze`, `flutter test`. Neu getestet werden Defs/Schlüssel, Overrides inklusive Geschwindigkeit und Migration, Presets (gültige Schlüssel, Anwenden, „angepasst“, eigene speichern/löschen), Suche, Browser-Widgets, Editor, Skalierung, Projektor und Schriftwechsel.
- `file -L libslicer_cli.so` nach dem Neubau.
- `flutter build apk --release --target-platform android-arm64`.

## Steps
1. Statusseite `.gg/status/update.sh` auf die Schritte dieses Plans umstellen und auf 0 setzen.
2. `--scale` in `engine/cli/slicer_cli.cpp` einbauen (vor `ensure_on_bed`, gilt für Vorschau und Slice), Engine in WSL per Schnellbuild neu bauen, mit `file -L` prüfen und nach `jniLibs` kopieren.
3. `scale` in `EngineJob` (`slicer_channel.dart`) und `SlicerService.kt` durchreichen, Kanaltest erweitern.
4. `test/engine/orca_keys.txt` mit gültigen Schlüsseln und Enum-Werten aus `PrintConfig.cpp` des gepinnten OrcaSlicer in WSL erzeugen.
5. `setting_defs.dart` mit rund 120 Einstellungen in 11 Kategorien und `profile_values.dart` schreiben; Test, dass alle Schlüssel und Auswahlwerte gültig und alle Profilwerte lesbar sind.
6. `SliceSettings` auf `values`, `speedPercent` und `presetId` umbauen, inklusive `overrides()`, Geschwindigkeitsskalierung und Migration alter Daten; `settings_test.dart` anpassen und erweitern.
7. `presets.dart` mit den 9 eingebauten Presets und `preset_store.dart` für eigene Presets (speichern, umbenennen, löschen, Bereinigung) schreiben; Tests für gültige Schlüssel, Anwenden, Erkennung „angepasst“ und Speicherung.
8. UI-Bausteine `pixel_search_field.dart`, `pixel_sheet.dart` und `pixel_stepper.dart` in `lib/ui/` mit Widget-Tests bauen.
9. `settings_browser_screen.dart` (Presets-Abschnitt ganz oben mit Speichern und Verwalten, Kategorien-Raster, Kategorieseite mit „Mehr anzeigen“, Suche über Einstellungen und Presets, Filter „Nur geänderte“, Alles zurücksetzen) und `setting_editor.dart` (Sheet mit Hilfetext und Profilwert) bauen und testen.
10. Modellbildschirm umbauen: Preset-Kacheln ganz oben (mit „angepasst“ und „Preset wiederherstellen“), Schnelleinstellungen mit Geschwindigkeit, Fuzzy Skin, Größe (Prozent, mm X/Y/Z, auf Bett einpassen) und Knopf zu allen Einstellungen; Skalierung an Vorschau, Passt-Prüfung und Slice-Job anbinden; Flow-Tests anpassen.
11. Vorschau ersetzen: Projektor im Worker (Rückseiten, Sortierung, weiche Beleuchtung, Skalierung), `CustomPainter` mit `ui.Vertices` in voller Auflösung, Gesten umkehren; `rasterizer.dart` entfernen und Modelltests umstellen.
12. Atkinson Hyperlegible mit OFL-Lizenz herunterladen und einbinden, `app_settings.dart` und schaltbare Schrift in `PixelTheme` umsetzen, Abschnitt „Darstellung“ und beide Lizenzen in `settings_screen.dart` ergänzen, Tests für Wechsel und Speicherung schreiben.
13. `flutter analyze` und `flutter test` ausführen, Release-APK für arm64 bauen und auf Inhalte prüfen, Statusseite auf 100 % setzen.
