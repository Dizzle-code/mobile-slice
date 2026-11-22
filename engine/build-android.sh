#!/usr/bin/env bash
# Builds the OrcaSlicer engine (Snapmaker fork, OrcaXR recipe) as a standalone
# arm64-v8a executable and installs it plus profiles into the Flutter app.
# Run inside WSL/Ubuntu x86_64. Needs ANDROID_HOME with ndk/29.0.14206865.
#
#   engine/build-android.sh            full build (first run: 1-2 h)
#   ENGINE_JOBS=4 engine/build-android.sh   fewer parallel compile jobs (less RAM)
#   ENGINE_SKIP_RECIPE=1 engine/build-android.sh   reuse an already prepared OrcaXR build tree
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=VERSIONS
source "$REPO/engine/VERSIONS"
WORK="${ENGINE_WORK:-$HOME/build}"
JOBS="${ENGINE_JOBS:-8}"
# OrcaXR's recipe accepts at most 4 jobs.
RECIPE_JOBS=$(( JOBS < 4 ? JOBS : 4 ))
ABI=arm64-v8a
JNI="$REPO/app/android/app/src/main/jniLibs/$ABI"
ASSETS="$REPO/app/assets/engine"

: "${ANDROID_HOME:?ANDROID_HOME muss auf das Android-SDK zeigen}"
NDK="$ANDROID_HOME/ndk/$NDK_VERSION"
LLVM="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
[[ -x "$LLVM/clang++" ]] || { echo "NDK $NDK_VERSION fehlt unter $NDK" >&2; exit 1; }

echo "=== 1/5 OrcaXR @ $ORCAXR_COMMIT"
mkdir -p "$WORK"
ORCAXR="$WORK/OrcaXR"
[[ -d "$ORCAXR/.git" ]] || git clone https://github.com/ignacio82/OrcaXR.git "$ORCAXR"
git -C "$ORCAXR" fetch -q origin "$ORCAXR_COMMIT" || true
git -C "$ORCAXR" checkout -q "$ORCAXR_COMMIT"
PIN=$(sed -n 's/^PIN = "\(.*\)"$/\1/p' "$ORCAXR/tools/native-engine/build-dependency-probes.py")
[[ "$PIN" == "$ENGINE_COMMIT" ]] || { echo "OrcaXR pinnt $PIN statt $ENGINE_COMMIT" >&2; exit 1; }

echo "=== 2/5 Abhängigkeiten + Engine-Quellen (OrcaXR-Rezept, Patches inklusive)"
if [[ "${ENGINE_SKIP_RECIPE:-0}" != 1 ]]; then
    python3 "$ORCAXR/tools/native-engine/build-engine.py" --abi "$ABI" --jobs "$RECIPE_JOBS"
fi

NE="$ORCAXR/tools/native-engine/build"
one_dir() { local d=("$@"); [[ ${#d[@]} -eq 1 && -d "${d[0]}" ]] || { echo "Erwarte genau ein Verzeichnis: $*" >&2; exit 1; }; echo "${d[0]}"; }
ENGINE_DIR=$(one_dir "$NE"/engine/*/)
DEPS_DIR=$(one_dir "$NE"/geometry/*/)
SOURCE="${ENGINE_DIR%/}/source"
BUILD="${ENGINE_DIR%/}/$ABI/cmake"
PREFIX="${DEPS_DIR%/}/$ABI/deps/destdir/usr/local"

echo "=== 3/5 slicer_cli bauen"
# Reuses OrcaXR's configured libslic3r build; only the added executable is new.
cmake -S "$SOURCE" -B "$BUILD" -DORCAXR_SLICE_PROBE_DIR="$REPO/engine/cli" >/dev/null
nice -n 10 cmake --build "$BUILD" --target slicer_cli -j"$JOBS"
CLI="$BUILD/src/orcaxr-probe/slicer_cli"

echo "=== 4/5 nach jniLibs kopieren"
mkdir -p "$JNI"
"$LLVM/llvm-strip" --strip-unneeded -o "$JNI/libslicer_cli.so" "$CLI"
cp "$PREFIX/lib/libtbb.so" "$PREFIX/lib/libtbbmalloc.so" "$JNI/"
cp "$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$JNI/"
for lib in libtbb.so libtbbmalloc.so libc++_shared.so; do "$LLVM/llvm-strip" --strip-unneeded "$JNI/$lib"; done
file -L "$JNI"/*.so
for lib in "$JNI"/*.so; do
    file -L "$lib" | grep -q "ELF 64-bit LSB.*ARM aarch64" || { echo "Kein aarch64-ELF: $lib" >&2; exit 1; }
done
ALLOWED=" libtbb.so libtbbmalloc.so libc++_shared.so libc.so libm.so libdl.so liblog.so libandroid.so libz.so "
for need in $("$LLVM/llvm-readelf" -d "$JNI/libslicer_cli.so" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
    [[ "$ALLOWED" == *" $need "* ]] || { echo "Unerwartete Abhängigkeit: $need" >&2; exit 1; }
done

echo "=== 5/5 Profile + Ressourcen"
python3 "$REPO/engine/flatten_profiles.py" "$SOURCE/resources/profiles/BBL" "$ASSETS/profiles" \
    --selection "$REPO/engine/profile_selection.json"
rm -rf "$ASSETS/resources/info"
mkdir -p "$ASSETS/resources/info"
cp "$SOURCE"/resources/info/*.json "$ASSETS/resources/info/"

echo "=== fertig: $(du -h "$JNI/libslicer_cli.so" | cut -f1) libslicer_cli.so"
