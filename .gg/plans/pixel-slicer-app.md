# Mobile Slice: die richtige App (Android)

## Ziel
Eine eigene Slicer-App für den Bambu Lab P1S: STL/3MF öffnen, als 3D-Modell ansehen (drehen, zoomen), Schichthöhe, Füllung, Stützen und Filament einstellen, slicen, per LAN an den P1S senden und den Druck live verfolgen. Dazu kommen ein Druckverlauf mit Statistik und Trophäen. Die Oberfläche ist auf Deutsch, pixelig, aber gut lesbar, mit etwas Verspieltheit (kleine Animationen, Trophäen-Pop-up).

## Grundsätze
- **Alles selbst gebaut:** keine Material- oder Cupertino-Widgets. Die App läuft auf `WidgetsApp` mit eigenem Theme, eigenem Navigator-Übergang und eigenen Komponenten. Kotlin bleibt nur dort, wo Android es zwingend verlangt: Engine-Prozess als Vordergrunddienst, Dateiauswahl, Teilen, Multicast-Lock für die Druckersuche.
- **Keine Fremdpakete in Dart:** MQTT, FTPS, STL-Parser und 3D-Renderer schreibe ich selbst, nur mit `dart:io`, `dart:typed_data` und `dart:isolate`. ZIP und 3MF übernimmt die Engine (libslic3r).
- **Wiederverwendbare Bausteine:** `lib/ui/` enthält das komplette Designsystem. Bildschirme setzen sich nur daraus zusammen und zeichnen nichts selbst.

## Design
- Palette mit 8 festen Farben (dunkler Hintergrund `#1B1B2F`, Panel `#2A2A48`, Akzent Orange `#FF8A3D` passend zum P1S, Grün, Rot, Gelb, Text hell und gedämpft), zentral in `PixelTheme`.
- Schrift **Pixelify Sans** (OFL, Google Fonts) als Asset, Lizenz liegt bei. Größen nur in Vielfachen von 4 px.
- Rahmen mit Treppenecken und harte 4-px-Schatten. Buttons „drücken“ sich beim Antippen 4 px nach unten. Icons sind 16×16-Pixelgrafiken als Zeichenketten-Raster im Code und skalieren ohne Glättung.
- 3D-Vorschau in niedriger Auflösung (etwa 200 px Breite), ohne Glättung hochskaliert. Das spart Rechenzeit und passt zum Stil.

## Ansatz

### Engine (C++, `engine/cli/slicer_cli.cpp`)
- Neue Argumente: `--overrides <json>` (Schlüssel/Wert wie `sparse_infill_density`, `enable_support`, `support_type`), `--export-3mf <pfad>` (druckfertige `.gcode.3mf` über `Slic3r::store_bbs_3mf` mit selbst befülltem `PlateData`: G-Code-Pfad, Zeit, Gewicht, Filament-Info, ohne Vorschaubild) und `--preview <pfad>` (nur laden und platzieren, dann binäres STL des platzierten Modells schreiben, ohne Slicen).
- 3MF-Dateien lädt die Engine selbst (`Model::read_from_file`). Projekt-Einstellungen in der 3MF werden ignoriert, es gelten die App-Einstellungen.
- `build-android.sh` legt mehrere Profile flach ab: Prozesse 0,08 / 0,12 / 0,16 / 0,20 / 0,24 / 0,28 mm (@BBL X1C, P1S-kompatibel) und Filamente Bambu PLA Basic, Bambu PLA Matte, Bambu PETG HF, Generic PLA, Generic PETG, Generic ABS, Generic TPU. Dazu schreibt es einen `catalog.json` mit Namen, Typ und Farbe.

### Kotlin (bleibt klein)
- `SlicerService.kt`: Job-Typen `slice` und `preview`, übergibt Overrides und 3MF-Pfad, Abbrechen per `destroy()`.
- `MainActivity.kt`: `pickModel` (.stl/.3mf), `appDir`, `shareFile`, `multicastLock(on/off)`. Den Test-Bildschirm und den alten Log-Kanal löse ich ab. Das Diagnose-Log bleibt unter Einstellungen erreichbar.

### Dart-Struktur (`app/lib/`)
- `ui/`: `pixel_theme.dart`, `pixel_frame.dart` (Treppenrahmen-Painter + `PixelPanel`), `pixel_button.dart`, `pixel_icon.dart` + `pixel_icons.dart`, `pixel_text.dart`, `pixel_progress.dart`, `pixel_slider.dart`, `pixel_toggle.dart`, `pixel_choice.dart` (Segment-Auswahl und Liste), `pixel_text_field.dart` (auf `EditableText`), `pixel_overlay.dart` (Dialog, Toast, Trophäen-Pop-up), `pixel_tab_bar.dart`, `pixel_scaffold.dart`, `pixel_route.dart` (Pixel-Wisch-Übergang), `stat_tile.dart`, `trophy_badge.dart`.
- `engine/`: `slicer_channel.dart` (bestehend, erweitert), `profile_catalog.dart`, `slice_settings.dart` (Auswahl → Overrides).
- `model/`: `stl_reader.dart` (binär + ASCII → `Float32List`), `mesh.dart` (Bounding Box, Ausdünnen für die Vorschau).
- `preview/`: `rasterizer.dart` (Software-Z-Buffer, Flat-Shading, läuft in einem Isolate), `model_viewer.dart` (Drehen, Zoomen, Druckbett als Raster).
- `printer/`: `mqtt_client.dart` (MQTT 3.1.1: CONNECT, SUBSCRIBE, PUBLISH, PING über `SecureSocket`), `ftps_client.dart` (implizites TLS auf Port 990, PASV, STOR), `bambu_printer.dart` (Status-Zusammenführung, weil der P1S nur Änderungen schickt, plus Befehle `pushall`, `project_file`, `pause`, `resume`, `stop`), `printer_discovery.dart` (SSDP auf UDP 2021), `printer_config.dart`.
- `data/`: `json_store.dart` (atomar schreiben), `print_history.dart`, `stats.dart`.
- `trophies/`: `trophy_catalog.dart`, `trophy_engine.dart` (prüft nach jedem Verlaufsereignis und meldet neue Trophäen).
- `screens/`: `home_screen.dart` (Werkstatt: Modell öffnen, letzte Modelle, Druckerstatus-Kachel), `model_screen.dart` (Vorschau, Einstellungen, Slicen), `result_screen.dart` (Zeit, Gramm, Schichten, „An P1S senden“), `printer_screen.dart` (Live-Status: Fortschritt, Schicht, Temperaturen, Pause/Abbruch), `printer_setup_screen.dart` (IP, Seriennummer, Zugangscode, Suche), `history_screen.dart`, `trophies_screen.dart`, `settings_screen.dart`.
- Unten eine Tab-Leiste: Werkstatt · Drucker · Verlauf · Trophäen.

### Drucker (LAN)
- Voraussetzung am P1S: **LAN-Only-Modus + Developer-Mode + SD-Karte**. Damit funktioniert die Bambu-Handy-App nicht mehr. Der Einrichtungsbildschirm erklärt das.
- Ablauf: Upload der `.gcode.3mf` per FTPS, dann MQTT-Befehl `project_file` (`url: ftp:///<datei>`, `param: Metadata/plate_1.gcode`, `use_ams: false`). Den Fortschritt liefert `device/<SN>/report`.
- TLS: Der Drucker nutzt ein selbstsigniertes Zertifikat. Ich merke mir beim ersten Verbinden den Fingerabdruck und lasse danach nur noch dieses Zertifikat zu, und nur für die eingetragene IP (Trust-on-first-use). Den Zugangscode speichere ich im privaten App-Ordner.
- Verlauf: Beim Senden entsteht ein Eintrag „gesendet“. Den Status „fertig/abgebrochen“ setzt die App, sobald sie `gcode_state` FINISH oder FAILED für diesen `subtask_name` sieht, auch nachträglich beim nächsten Verbinden.

### Trophäen (erste 14)
Erster Druck · Fünferpack (5) · Serienproduktion (25) · Druckfabrik (100) · Erstes Kilo (1 kg) · Schwergewicht (5 kg) · Zehn Stunden · Hundert Stunden · Marathon (ein Druck > 8 h) · Nachteule (Start zwischen 0 und 5 Uhr) · Kapitän (Datei mit „benchy“ im Namen) · Materialkunde (3 Filamenttypen) · Feinmechaniker (Druck mit 0,08 mm) · Durchhalter (5 erfolgreiche Drucke in Folge). Jede Trophäe hat ein eigenes 16×16-Icon. Gesperrte Trophäen werden grau mit Fortschrittsbalken angezeigt.

## Risiken
- **Developer-Mode/Firmware:** Ohne Developer-Mode lehnt der P1S Befehle von Fremd-Apps ab. Das lässt sich nur am echten Drucker testen. Deshalb kommt der Druckerteil früh als eigener Testschritt.
- **`.gcode.3mf` aus der Engine:** Das `PlateData` muss ich ohne die GUI-Klasse `PartPlate` befüllen. Falls der P1S die Datei ablehnt, schreibe ich in Dart eine minimale 3MF (ZIP ohne Kompression, eigener Schreiber).
- **3D-Vorschau in Dart:** Bei großen Modellen dünne ich für die Vorschau auf etwa 60.000 Dreiecke aus. Slicen nutzt immer das volle Modell.
- **SSDP-Suche:** Manche Router blockieren Broadcasts. Deshalb gibt es immer auch die manuelle Eingabe von IP und Seriennummer.
- Engine-Änderungen brauchen nur einen kurzen Neubau der CLI in WSL (`ENGINE_SKIP_RECIPE=1`).

## Prüfung
- `flutter analyze` ohne Meldungen; `flutter test` mit Tests für jede UI-Komponente (Widget-Tests), STL-Parser, Rasterizer, MQTT-Kodierung, FTPS-Ablauf (gegen einen Test-Server mit austauschbarem Socket), Status-Zusammenführung (aufgezeichnete Report-JSONs), Verlauf und Trophäen-Regeln.
- In WSL: CLI-Neubau, `file` → aarch64; Profilkatalog wird erzeugt.
- `flutter build apk --release --target-platform android-arm64`.
- Auf dem Handy (durch dich): Benchy öffnen → Vorschau drehen → Einstellungen ändern → slicen → an den P1S senden → Druck läuft, Status live → nach Abschluss erscheinen Verlauf und die Trophäe „Erster Druck“.

## Steps
1. Engine-CLI um `--overrides`, `--preview` und `--export-3mf` erweitern und `build-android.sh` mehrere Prozess-/Filamentprofile samt `catalog.json` flach ablegen lassen; CLI in WSL neu bauen und mit `file` prüfen.
2. Pixelify Sans samt OFL-Lizenz als Asset einbinden und das Designsystem in `lib/ui/` (Theme, Rahmen, Button, Icons, Text, Fortschritt, Slider, Toggle, Auswahl, Textfeld, Overlay, Tab-Leiste, Scaffold, Route, StatTile, TrophyBadge) mit Widget-Tests schreiben.
3. App-Gerüst auf `WidgetsApp` umstellen (ohne `material_ui`), Tab-Leiste mit vier Bereichen, alten Test-Bildschirm entfernen.
4. Kotlin erweitern: Preview- und Slice-Jobs mit Overrides, Abbrechen, `pickModel` für STL/3MF, `appDir`, `shareFile`, Multicast-Lock; Kanal in `slicer_channel.dart` nachziehen.
5. `profile_catalog.dart` und `slice_settings.dart` mit Tests für die Overrides schreiben.
6. `stl_reader.dart`, `mesh.dart` und den Isolate-Rasterizer mit Tests schreiben, `model_viewer.dart` mit Drehen/Zoomen bauen.
7. `model_screen.dart` (Vorschau + Einstellungen + Slicen mit Fortschritt) und `result_screen.dart` bauen.
8. `mqtt_client.dart`, `ftps_client.dart` und `bambu_printer.dart` mit Tests schreiben (Kodierung, Ablauf, Status-Zusammenführung, Zertifikats-Pinning).
9. `printer_discovery.dart`, `printer_config.dart`, `printer_setup_screen.dart` und `printer_screen.dart` bauen; Test-APK bauen, damit du Verbindung, Upload und Druckstart am echten P1S prüfst.
10. `json_store.dart`, `print_history.dart` und `stats.dart` mit Tests schreiben; Verlaufseinträge beim Senden anlegen und über den Druckerstatus abschließen.
11. `trophy_catalog.dart` (14 Trophäen mit Pixel-Icons) und `trophy_engine.dart` mit Tests für jede Regel schreiben, Trophäen-Pop-up anbinden.
12. `home_screen.dart`, `history_screen.dart`, `trophies_screen.dart` und `settings_screen.dart` (inklusive Diagnose-Log teilen) bauen.
13. `flutter analyze` und `flutter test` ausführen, Release-APK für arm64 bauen und dir mit Testanleitung übergeben.
