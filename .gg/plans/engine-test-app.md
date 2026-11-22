# Test-App: Läuft die OrcaSlicer-Engine auf dem Nothing Phone (4a) Pro?

## Ziel
Eine schlichte Android-APK (Flutter), die ein STL-Modell mit dem P1S-Profil von OrcaSlicer sliced und **Dauer, maximalen RAM-Verbrauch und Fehler** anzeigt und protokolliert. Noch kein Pixel-Art-Design, kein Druckerversand.

## Ansatz
- **Build-Umgebung:** WSL2 mit Ubuntu (Admin-Pop-up und Neustart). Darin werden OrcaSlicer und alle Abhängigkeiten mit dem Android-NDK für `arm64-v8a` übersetzt.
- **Vorlage:** Die Android-Patches und Build-Skripte von OrcaXR (`tools/native-engine`, `patches/`, AGPL), angepasst auf eine fest gepinnte OrcaSlicer-Version. Ergebnis ist ein eigenständiges Kommandozeilen-Programm, keine Bibliothek, die in die App geladen wird.
- **Eigener Prozess:** Das Programm liegt als `libslicer_cli.so` in `jniLibs`, weil Android ausführbare Dateien nur aus dem Bibliotheksordner der App erlaubt. Kotlin startet es über `ProcessBuilder` in einem Vordergrunddienst. Stürzt die Engine ab, bleibt die App bestehen und zeigt den Exit-Code an.
- **Messung:** Während des Slicens liest Kotlin regelmäßig `/proc/<pid>/status` (`VmHWM` = maximaler RAM, `VmRSS` = aktueller RAM) und misst die Zeit. Ergebnisse und stderr landen in `slice-log.txt`, das sich über „Teilen“ verschicken lässt.
- **Profile:** Die nötigen Bambu-Lab-Profile (P1S, 0.4-Düse, Generic PLA, 0.20 mm) liegen als Assets in der App und werden beim ersten Start ins App-Verzeichnis kopiert.
- **Flutter-Oberfläche:** ein Bildschirm mit den Knöpfen „Testwürfel slicen“ (mitgeliefert), „STL wählen“ und „Log teilen“ sowie den Messwerten. Kommuniziert über einen `MethodChannel` mit Kotlin.

## Dateien
- `engine/build-android.sh`: Build in WSL (Quellen klonen, Patches anwenden, Abhängigkeiten und CLI bauen, Ergebnis nach `app/android/app/src/main/jniLibs/arm64-v8a/` kopieren)
- `engine/patches/`: übernommene und angepasste Patches
- `engine/VERSIONS`: gepinnte Commits von OrcaSlicer und OrcaXR
- `app/` (Flutter, nur Android, Paket `mobile_slice`)
  - `lib/main.dart`, `lib/slicer_channel.dart`, `lib/test_screen.dart`
  - `android/app/src/main/kotlin/.../SlicerService.kt` (Vordergrunddienst, Prozess, RAM-Messung)
  - `android/app/src/main/kotlin/.../MainActivity.kt` (MethodChannel, Teilen)
  - `assets/profiles/…`, `assets/models/test_cube.stl`
  - `test/slice_result_test.dart` (Auswertung der Messwerte und Logs)
- `LICENSE` (AGPL-3.0, weil die Engine AGPL ist)

## Risiken
- Der Android-Build von OrcaSlicer ist experimentell. Falls die aktuelle Version nicht baut, nehme ich genau den Stand, den OrcaXR nutzt.
- Der erste Build dauert etwa 1 bis 2 Stunden und braucht 30–50 GB Platz in WSL.
- OrcaXR nutzt einen seriellen TBB-Ersatz (ein CPU-Kern), dadurch ist Slicen langsamer. Wenn möglich, nehme ich echtes TBB mit mehreren Kernen.
- Die eigenständige CLI ist neu. Vor dem Bauen der APK prüfe ich mit `file`, dass sie für aarch64 gebaut ist.

## Prüfung
- `file libslicer_cli.so` → ELF 64-bit, ARM aarch64
- `flutter analyze` und `flutter test` laufen sauber durch
- `flutter build apk --release --target-platform android-arm64` erzeugt die APK
- Auf dem Handy (durch dich): Testwürfel und ein echtes Modell slicen, dann Messwerte bzw. Log zurückschicken

## Steps
1. WSL2 mit Ubuntu über `wsl --install` installieren (Admin-Pop-up), Neustart durch den Nutzer, danach Ubuntu-Benutzer anlegen lassen.
2. In Ubuntu die Build-Werkzeuge installieren (build-essential, cmake, ninja, git, python3, autotools, Linux-Android-NDK 30).
3. OrcaSlicer und OrcaXR fest gepinnt nach `~/build` klonen und die Versionen in `engine/VERSIONS` festhalten.
4. `engine/build-android.sh` samt `engine/patches/` schreiben und die Abhängigkeiten für arm64-v8a bauen.
5. Die OrcaSlicer-CLI für arm64-v8a bauen, mit `file` prüfen und als `libslicer_cli.so` (plus `libc++_shared.so` und TBB) nach `jniLibs` kopieren.
6. Das Flutter-Projekt `app/` nur für Android anlegen und die P1S-Profile sowie den Testwürfel als Assets einbinden.
7. `SlicerService.kt` und `MainActivity.kt` schreiben: Prozess starten, RAM-Spitze und Zeit messen, Log schreiben, MethodChannel, Teilen.
8. `test_screen.dart` und `slicer_channel.dart` mit den Knöpfen „Testwürfel slicen“, „STL wählen“ und „Log teilen“ schreiben.
9. `slice_result_test.dart` schreiben, `flutter analyze` und `flutter test` ausführen.
10. Release-APK für arm64 bauen und den Pfad samt Installationsanleitung an den Nutzer geben.
