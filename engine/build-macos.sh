#!/usr/bin/env bash
# Builds the OrcaSlicer engine (Snapmaker fork, same ENGINE_COMMIT as Android, without the OrcaXR
# Android patches) as slicer_cli for this Mac's processor and copies it to app/macos/engine/.
# Needs Xcode command line tools, CMake >= 3.22, git and perl (macOS ships perl).
#
#   engine/build-macos.sh                  full build (first run: 1-2 h)
#   ENGINE_SKIP_DEPS=1 engine/build-macos.sh   reuse built dependencies
#   ENGINE_ONLY_DEPS=1 engine/build-macos.sh   only build the dependencies (for CI caching)
#   ENGINE_WORK=~/build/orca engine/build-macos.sh   other build folder
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=VERSIONS
source "$REPO/engine/VERSIONS"
WORK="${ENGINE_WORK:-$HOME/build/orca-desktop}"
JOBS="${ENGINE_JOBS:-$(sysctl -n hw.ncpu)}"
ARCH="$(uname -m)"
TARGET="${OSX_DEPLOYMENT_TARGET:-12.0}"
OUT="$REPO/app/macos/engine"
export CMAKE_POLICY_VERSION_MINIMUM=3.5

echo "=== 1/5 Engine-Quellen @ $ENGINE_COMMIT ($ARCH)"
if [[ ! -d "$WORK/.git" ]]; then
    mkdir -p "$WORK"
    git -C "$WORK" init -q
    git -C "$WORK" remote add origin https://github.com/Snapmaker/OrcaSlicer.git
fi
if [[ "$(git -C "$WORK" rev-parse HEAD 2>/dev/null || true)" != "$ENGINE_COMMIT" ]]; then
    git -C "$WORK" fetch -q --depth 1 origin "$ENGINE_COMMIT"
    git -C "$WORK" checkout -q -f "$ENGINE_COMMIT"
fi

echo "=== 2/5 Desktop-Anpassung"
# Attaches engine/cli as an extra target next to libslic3r (same edit as build-windows.ps1).
if ! grep -q SLICER_CLI_DIR "$WORK/src/CMakeLists.txt"; then
    perl -0pi -e 's/^add_subdirectory\(libslic3r\)(\r?\n)/add_subdirectory(libslic3r)$1if (SLICER_CLI_DIR)$1    add_subdirectory("\${SLICER_CLI_DIR}" slicer_cli)$1endif ()$1/m' "$WORK/src/CMakeLists.txt"
    grep -q SLICER_CLI_DIR "$WORK/src/CMakeLists.txt" || { echo "Anpassung passt nicht mehr: src/CMakeLists.txt" >&2; exit 1; }
fi
# Newer Apple clang rejects old OpenVDB templates. The deps build sets CMAKE_CXX_FLAGS itself, so the flag goes there.
if ! grep -q Wno-missing-template-arg-list "$WORK/deps/deps-macos.cmake"; then
    perl -pi -e 's/^(set\(DEP_WERRORS_SDK "[^"]*)"/$1 -Wno-missing-template-arg-list-after-template-kw"/' "$WORK/deps/deps-macos.cmake"
    grep -q Wno-missing-template-arg-list "$WORK/deps/deps-macos.cmake" || { echo "Anpassung passt nicht mehr: deps/deps-macos.cmake" >&2; exit 1; }
fi

DEPS_BUILD="$WORK/deps/build/$ARCH"
DEPS="$DEPS_BUILD/OrcaSlicer_dep"
PREFIX="$DEPS/usr/local"
if [[ "${ENGINE_SKIP_DEPS:-0}" != 1 ]]; then
    echo "=== 3/5 Abhängigkeiten (ohne wxWidgets, Sentry und andere reine GUI-Teile)"
    cmake -S "$WORK/deps" -B "$DEPS_BUILD" -DDESTDIR="$DEPS" -DCMAKE_BUILD_TYPE=Release -DSLIC3R_SENTRY=OFF \
        -DOPENSSL_ARCH="darwin64-$ARCH-cc" -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET"
    cmake --build "$DEPS_BUILD" --config Release -j"$JOBS" --target dep_Boost dep_TBB dep_OpenSSL dep_CURL dep_Cereal \
        dep_NLopt dep_OpenVDB dep_GLEW dep_GLFW dep_OpenCV dep_CGAL dep_OCCT dep_FREETYPE dep_JPEG dep_PNG dep_ZLIB \
        dep_EXPAT dep_libnoise dep_Qhull
fi
if [[ "${ENGINE_ONLY_DEPS:-0}" == 1 ]]; then
    echo "=== fertig: Abhängigkeiten in $PREFIX"
    exit 0
fi

echo "=== 4/5 slicer_cli bauen"
BUILD="$WORK/build/$ARCH"
cmake -S "$WORK" -B "$BUILD" -DSLIC3R_GUI=OFF -DSLIC3R_SENTRY=OFF -DBBL_RELEASE_TO_PUBLIC=1 \
    -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_BUILD_TYPE=Release -DCMAKE_MACOSX_BUNDLE=OFF \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" -DSLICER_CLI_DIR="$REPO/engine/cli"
cmake --build "$BUILD" --config Release -j"$JOBS" --target slicer_cli
CLI="$BUILD/src/slicer_cli/slicer_cli"
[[ -x "$CLI" ]] || CLI="$BUILD/src/slicer_cli/Release/slicer_cli"
[[ -x "$CLI" ]] || { echo "slicer_cli fehlt unter $BUILD/src/slicer_cli" >&2; exit 1; }

echo "=== 5/5 nach app/macos/engine kopieren"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$CLI" "$OUT/slicer_cli"
# Dylibs from the dependency build go along and are loaded next to the executable.
copy_libs() {
    local binary="$1" lib name
    for lib in $(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -E "^($PREFIX|@rpath/)" || true); do
        name="$(basename "$lib")"
        if [[ ! -f "$OUT/$name" ]]; then
            cp -L "$PREFIX/lib/$name" "$OUT/$name"
            chmod u+w "$OUT/$name"
            install_name_tool -id "@loader_path/$name" "$OUT/$name"
            copy_libs "$OUT/$name"
        fi
        install_name_tool -change "$lib" "@loader_path/$name" "$binary"
    done
}
copy_libs "$OUT/slicer_cli"
strip -x "$OUT/slicer_cli"
# Ad-hoc signature so the binary runs on Apple Silicon; Xcode signs it again in the app.
codesign --force --sign - "$OUT"/*
otool -L "$OUT/slicer_cli"
echo "=== fertig: $(du -h "$OUT/slicer_cli" | cut -f1) slicer_cli"
