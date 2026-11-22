@echo off
rem Runs engine/build-android.sh in its own window so the build progress ([n/N] steps) stays visible.
rem   build-window.cmd        full build
rem   build-window.cmd skip   reuse the prepared OrcaXR tree (quick CLI rebuild)
set SKIP=0
if /I "%~1"=="skip" set SKIP=1
set REPO=%~dp0..
start "Mobile Slice: Engine-Build" wsl.exe -e bash -lc "cd \"$(wslpath -a '%REPO%')\" && export ANDROID_HOME=${ANDROID_HOME:-$HOME/android/sdk} ENGINE_SKIP_RECIPE=%SKIP% && bash engine/build-android.sh; echo; read -p 'Build beendet. Enter schliesst das Fenster.'"
