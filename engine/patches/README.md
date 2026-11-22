# Patches

`build-android.sh` applies the Android patches from the pinned OrcaXR checkout
(`engine/VERSIONS`) through OrcaXR's own recipe (`tools/native-engine/build-engine.py`):

- `tools/native-engine/patches/0001`–`0005`: Android dependencies, headless engine and print initialization
- `wasm/patches/snapmaker-fork-wasm-port.diff` (only `src/libslic3r/*`): shared engine fixes
- `server/patches/0003-gcodeprocessor-fullspectrum-oob.patch`

The repo's own `cli/` directory is attached as an extra CMake subdirectory and
needs no source patches. Put any additional engine patches here and apply them
in `build-android.sh`.
