Pixel-Slicer für den Bambu Lab P1S – Vorabversion.

## Downloads

| System | Datei |
|---|---|
| Windows 10/11 (64 Bit) | `Mobile-Slice-1.0.0-Windows-Setup.exe` |
| Android 12 oder neuer (arm64) | `Mobile-Slice-1.0.0-Android-arm64.apk` |
| macOS 12 oder neuer (Apple Silicon, M1 und neuer) | `Mobile-Slice-1.0.0-macOS-AppleSilicon.dmg` |

## Installation

- **Windows:** Setup starten. Es braucht keine Administratorrechte. Weil der Installer nicht signiert ist, zeigt SmartScreen beim ersten Start eine Warnung: „Weitere Informationen“ → „Trotzdem ausführen“.
- **Android:** APK auf dem Gerät öffnen und die Installation aus dieser Quelle erlauben.
- **macOS:** DMG öffnen und „Mobile Slice“ in „Programme“ ziehen. Die App ist nur ad hoc signiert: Beim ersten Start per Rechtsklick → „Öffnen“ starten oder im Terminal `xattr -dr com.apple.quarantine "/Applications/Mobile Slice.app"` ausführen. Beim ersten Start den Zugriff aufs lokale Netzwerk erlauben, sonst wird der Drucker nicht gefunden.

Die Prüfsummen stehen in `SHA256SUMS.txt`.
