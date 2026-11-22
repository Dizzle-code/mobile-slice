# Mobile Slice

Pixel-Slicer für den Bambu Lab P1S. Läuft auf Android, Windows und macOS.

## Engine bauen

Die Slicer-Engine (`engine/cli/slicer_cli.cpp` auf Basis von OrcaSlicer, Snapmaker-Fork) wird je Plattform einmal gebaut:

| Plattform | Skript | Ausgabe |
|-----------|--------|---------|
| Android | `engine/build-android.sh` (in WSL) | `android/app/src/main/jniLibs/arm64-v8a/` |
| Windows | `engine\build-windows.ps1` | `windows/engine/` |
| macOS | `engine/build-macos.sh` | `macos/engine/` |

Alle drei nutzen denselben `ENGINE_COMMIT` aus `engine/VERSIONS`. Der erste Lauf baut die Abhängigkeiten und dauert ein bis mehrere Stunden.

## Windows

Voraussetzungen: Visual Studio 2022 oder 2026 mit „Desktopentwicklung mit C++“, CMake 4.2 oder neuer und Strawberry Perl.

```powershell
winget install Kitware.CMake StrawberryPerl.StrawberryPerl
powershell -ExecutionPolicy Bypass -File engine\build-windows.ps1
cd app
flutter build windows --release
```

Die App liegt danach in `build\windows\x64\runner\Release\` (mit dem Ordner `engine\`).

## macOS

Voraussetzungen: Xcode mit Command Line Tools, Flutter, CMake (`brew install cmake`).

```sh
engine/build-macos.sh
cd app
flutter build macos --release
open "build/macos/Build/Products/Release/Mobile Slice.app"
```

- Das Skript baut für den Prozessor des Macs (Apple Silicon oder Intel) und legt `slicer_cli` samt Bibliotheken nach `macos/engine/`.
- Ein Build-Schritt in Xcode („Copy Engine“) kopiert den Ordner nach `Mobile Slice.app/Contents/Resources/engine` und signiert ihn ad hoc.
- Die Sandbox ist aus, damit die Engine starten und die Druckersuche (UDP) laufen kann. Die App ist deshalb nicht für den App Store gedacht.
- Beim ersten Start fragt macOS nach dem Zugriff aufs lokale Netzwerk. Den bitte erlauben, sonst wird der Drucker nicht gefunden.
- Eine unsignierte App startet beim ersten Mal per Rechtsklick → „Öffnen“.

### macOS ohne eigenen Mac (GitHub Actions)

Der Workflow `.github/workflows/macos.yml` baut Engine und App auf einem Apple-Silicon-Mac von GitHub.

1. Das Projekt in ein GitHub-Repository hochladen. Der Workflow startet bei jedem Push, der `app/` oder `engine/` ändert, oder von Hand unter **Actions → macOS → Run workflow**.
2. Der erste Lauf baut die Engine-Abhängigkeiten (1–3 Stunden) und legt sie im Cache ab. Danach dauert ein Lauf etwa 15–20 Minuten.
3. Wenn der Lauf fertig ist, unter **Artifacts** die Datei `Mobile-Slice-macOS` herunterladen und entpacken.
4. Die App ist nur ad hoc signiert. Nach dem Herunterladen blockiert macOS sie deshalb. Einmal im Terminal `xattr -dr com.apple.quarantine "Mobile Slice.app"` ausführen oder die App per Rechtsklick → „Öffnen“ starten.

Die App läuft nur auf Macs mit Apple Silicon (M1 und neuer).
