# Mobile Slice auf Windows und macOS

## Ziel
Die App läuft als Desktop-App auf Windows (hier gebaut und getestet) und macOS (Code und Build-Skript fertig, gebaut wird auf deinem Mac). Slicen, Drucker-Verbindung, Verlauf und Trophäen funktionieren dort genauso wie auf Android.

## Ausgangslage
- Alles, was Android-spezifisch ist, steckt hinter `SlicerChannel` (`lib/engine/slicer_channel.dart`). Dessen Gegenstück in Kotlin sind `MainActivity.kt` und `SlicerService.kt`: Assets kopieren, Datei wählen, Engine als Kindprozess starten und die `@@`-JSON-Zeilen auslesen, teilen, Log, Multicast.
- Drucker (MQTT/FTPS über `SecureSocket`), Suche (UDP), Speicher (`JsonStore`) und die gesamte Oberfläche sind reines Dart und laufen auf dem Desktop ohne Änderung.
- Die Engine `engine/cli/slicer_cli.cpp` wird bisher nur über das Android-Rezept von OrcaXR gebaut (`engine/build-android.sh`). Unix-spezifisch daran sind nur `getrusage`/`getpid` und eine Prüfung `NOT ANDROID` in `engine/cli/CMakeLists.txt`.
- Hier installiert: Visual Studio 18 (2026) Community mit MSVC 14.51.

## Vorgehen
1. **Desktop-Gegenstück in Dart statt nativem Code.** Neue Klasse `DesktopSlicer extends SlicerChannel` in `lib/engine/desktop_slicer.dart`. Sie überschreibt `prepare`, `pickModel`, `takeLaunch`, `openUrl`, `updateWidgets`, `run`, `cancel`, `shareFile`, `shareLog`, `appendLog` und `setMulticast`:
   - App-Ordner: `%APPDATA%\MobileSlice` bzw. `~/Library/Application Support/MobileSlice`. Die Engine-Assets werden einmal pro App-Version aus dem `rootBundle` nach `engine/` kopiert, mit `.version`-Stempel wie auf Android.
   - Engine-Programm: unter Windows `<Ordner der exe>\engine\slicer_cli.exe`, unter macOS `Mobile Slice.app/Contents/Resources/engine/slicer_cli`.
   - `run`: `Process.start` mit denselben Argumenten wie `SlicerService.runEngine`, eigenem TMP-Ordner, Auswertung der `@@`-Zeilen und demselben Ergebnis-Format inklusive Log-Eintrag. `cancel` beendet den Prozess. Prüft wie Android, dass Profile und Ausgaben im App-Ordner bleiben.
   - Datei wählen über `file_selector` (stl/3mf). Die Datei wird wie bei `copyModel` nach `models/` kopiert, `.gcode.3mf` wird abgelehnt.
   - Teilen heißt am Desktop **Speichern unter** (`getSaveLocation`): Druckdatei und Diagnose-Log werden kopiert.
   - `openUrl`: nur https, über `rundll32 url.dll,FileProtocolHandler` bzw. `open`.
   - `takeLaunch`: eine Modelldatei aus den Startargumenten (`main(args)`), damit „Öffnen mit“ auch hier funktioniert. Widgets und Multicast sind auf dem Desktop leere Aufrufe.
   - Für Tests lässt sich der Prozessstart von außen einsetzen.
2. **Auswahl der Umsetzung** in `main.dart`: Android nimmt `SlicerChannel()`, Windows und macOS nehmen `DesktopSlicer(args)`. `DeviceInfo.fromMap` nimmt zusätzlich `os` für die Zusammenfassung, z. B. „Windows 11 · 16 Kerne“.
3. **Texte je Plattform:** Wo der Desktop anders funktioniert, ändern sich Beschriftungen. „Druckdatei teilen“ wird zu „Druckdatei speichern“, „Diagnose-Log teilen“ zu „Diagnose-Log speichern“. Die MakerWorld-Anleitung heißt am Desktop: herunterladen, dann „Modell öffnen“. Die Widgets werden dort nicht erwähnt.
4. **Desktop-Runner** mit `flutter create --platforms=windows,macos .` erzeugen:
   - Fenstertitel „Mobile Slice“, Startgröße hochkant (ca. 480×900) mit Mindestgröße, da die App fürs Handy gestaltet ist.
   - Windows: `windows/CMakeLists.txt` installiert `windows/engine/*` (exe und DLLs) neben die App nach `engine/`.
   - macOS: In `project.pbxproj` kommt ein Build-Schritt dazu, der `macos/engine/*` nach `Contents/Resources/engine` kopiert. Sandbox aus, damit die mitgelieferte Engine starten und die UDP-Suche laufen darf; es ist eine private App, nicht für den App Store.
5. **Engine für den Desktop** (OrcaSlicer-Fork von Snapmaker, derselbe `ENGINE_COMMIT`, ohne die Android-Patches von OrcaXR):
   - `engine/cli/slicer_cli.cpp`: Speicherspitze und PID auch unter Windows (`GetProcessMemoryInfo`, `_getpid`).
   - `engine/cli/CMakeLists.txt`: auch ohne Android erlaubt.
   - Neues Skript `engine/build-windows.ps1`: Klon in einen eigenen, neuen Ordner (`C:\msbuild\orca`, kurzer Pfad wegen der Windows-Pfadgrenze), Abhängigkeiten über das Deps-Projekt des Forks, `add_subdirectory` für `engine/cli`, nur das Ziel `slicer_cli` bauen, exe und nötige DLLs nach `app/windows/engine/`.
   - Neues Skript `engine/build-macos.sh`: dasselbe für macOS (nativer Prozessor), Ausgabe nach `app/macos/engine/`.
   - Beide nutzen `engine/VERSIONS` mit.
6. **pubspec:** `file_selector` mit fester Version, die Beschreibung ohne „auf Android“.

## Risiken
- Der Windows-Build der OrcaSlicer-Abhängigkeiten dauert Stunden. Der Fork erwartet Visual Studio 2022, hier ist 2026 installiert; das kann Anpassungen am Generator oder an der CMake-Version brauchen. Dazu werden eventuell Werkzeuge wie Strawberry Perl für OpenSSL benötigt; solche Installationen frage ich vorher ab.
- `slicer_cli.cpp` könnte APIs nutzen, die nur durch die OrcaXR-Patches entstehen. Dann übernehme ich die nötigen Patches gezielt in einen Desktop-Patch.
- macOS kann ich hier weder bauen noch testen. Das Skript und der Xcode-Schritt bleiben ungeprüft, bis du sie auf dem Mac ausführst.
- Eine unsignierte Windows-exe kann eine SmartScreen-Warnung auslösen, und die Firewall fragt einmal wegen der Druckersuche.

## Prüfung
- `flutter analyze` und `flutter test`: Alle bisherigen Tests plus neue Tests für `DesktopSlicer` (Argumente, Auswertung der `@@`-Zeilen, Abbruch, Pfadprüfung, Asset-Kopie, Startargumente) mit einem gefälschten Prozess.
- Echter Engine-Test unter Windows: `slicer_cli.exe` slict den mitgelieferten Testwürfel zu `.gcode.3mf`. Zusätzlich ein `flutter test`, der `DesktopSlicer` mit der echten exe laufen lässt und übersprungen wird, wenn sie fehlt.
- `flutter build windows --release` läuft durch. Die gebaute App startet, ich prüfe Log und Prozess.
- `flutter build apk --release` baut weiterhin, damit Android unverändert bleibt.

## Steps
1. `file_selector` in einer festen Version in `app/pubspec.yaml` eintragen, `flutter pub get` ausführen und die Beschreibung anpassen.
2. Mit `flutter create --platforms=windows,macos .` die Ordner `app/windows` und `app/macos` erzeugen.
3. `lib/engine/desktop_slicer.dart` mit `DesktopSlicer` schreiben: Pfade, Asset-Kopie, Prozessstart mit `@@`-Auswertung, Abbruch, Log, Datei wählen, Speichern unter, openUrl, Startargumente.
4. `DeviceInfo.fromMap` um `os` erweitern und in `main.dart` je nach Plattform `SlicerChannel` oder `DesktopSlicer(args)` wählen.
5. Desktop-Beschriftungen in `result_screen.dart`, `settings_screen.dart`, `model_screen.dart` und `home_screen.dart` (MakerWorld-Anleitung) umsetzen.
6. Tests `test/engine/desktop_slicer_test.dart` mit gefälschtem Prozess schreiben und `flutter analyze` sowie `flutter test` grün bekommen.
7. Windows-Runner einrichten: Titel, Fenstergröße, Install-Regel für `windows/engine/*` in `windows/CMakeLists.txt`.
8. macOS-Runner einrichten: Titel, Fenstergröße, Sandbox aus in beiden Entitlements, Kopierschritt für `macos/engine/*` in `project.pbxproj`.
9. `engine/cli/slicer_cli.cpp` und `engine/cli/CMakeLists.txt` für Windows und macOS portabel machen.
10. `engine/build-windows.ps1` schreiben und die Windows-Engine bauen; fehlende Werkzeuge vorher abfragen.
11. `slicer_cli.exe` direkt mit dem Testwürfel prüfen und den echten `DesktopSlicer`-Test laufen lassen.
12. Mit `flutter build windows --release` bauen und die App einmal starten.
13. `engine/build-macos.sh` schreiben und eine kurze Anleitung zum Bauen auf dem Mac in `app/README.md` aufnehmen.
14. Mit `flutter build apk --release --target-platform android-arm64` prüfen, dass Android weiterhin baut.
