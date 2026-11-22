Pixel-Slicer für den Bambu Lab P1S – Vorabversion.

## Neu in 1.1.0

- **Mehrere Druckplatten**, jede mit beliebig vielen Objekten. Geslict wird pro Platte.
- **Objekte verschieben** per Maus, Pfeiltasten oder Zahl, **drehen** um X/Y/Z, **skalieren**, kopieren, flach legen, umdrehen.
- **Anordnen** verteilt alle Objekte ohne Überlappung; was nicht passt, kommt auf neue Platten.
- **Rückgängig/Wiederholen** (Strg+Z / Strg+Y).
- **Desktop-Layout** unter Windows und macOS: Seitenleiste, Platten- und Objektliste, große 3D-Ansicht, Einstellungen daneben. Das Fenster startet maximiert.
- **Eigenes App-Icon** unter Windows und macOS.

## Downloads

| System | Datei |
|---|---|
| Windows 10/11 (64 Bit) | `Mobile-Slice-1.1.0-Windows-Setup.exe` |
| Android 12 oder neuer (arm64) | `Mobile-Slice-1.1.0-Android-arm64.apk` |
| macOS 12 oder neuer (Apple Silicon, M1 und neuer) | `Mobile-Slice-1.1.0-macOS-AppleSilicon.dmg` |

## Installation

- **Windows:** Setup starten. Es braucht keine Administratorrechte. Weil der Installer nicht signiert ist, zeigt SmartScreen beim ersten Start eine Warnung: „Weitere Informationen“ → „Trotzdem ausführen“.
- **Android:** APK auf dem Gerät öffnen und die Installation aus dieser Quelle erlauben.
- **macOS:** DMG öffnen und „Mobile Slice“ in „Programme“ ziehen. Die App ist nur ad hoc signiert: Beim ersten Start per Rechtsklick → „Öffnen“ starten oder im Terminal `xattr -dr com.apple.quarantine "/Applications/Mobile Slice.app"` ausführen. Beim ersten Start den Zugriff aufs lokale Netzwerk erlauben, sonst wird der Drucker nicht gefunden.

Die Prüfsummen stehen in `SHA256SUMS.txt`.
