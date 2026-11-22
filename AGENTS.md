# AGENTS.md

Mobile Slice: Flutter app (Dart) in `app/`, slicer engine (C++, OrcaSlicer fork) built by the scripts in `engine/`. UI texts are German.

## Commands (run in `app/`)

- Install: `flutter pub get`
- Lint: `flutter analyze`
- Test: `flutter test`
- Build: `flutter build apk --release --target-platform android-arm64`, `flutter build windows --release`, `flutter build macos --release`
- Engine: `engine/build-android.sh`, `engine/build-windows.ps1`, `engine/build-macos.sh` (slow; see `app/README.md`)

## Rules

- CI lives in `.github/workflows/ci.yml` and must stay green.
- Never commit with `--no-verify`.
