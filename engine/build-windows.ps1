# Builds the OrcaSlicer engine (Snapmaker fork, same ENGINE_COMMIT as Android, without the OrcaXR
# Android patches) as slicer_cli.exe and copies it with its DLLs to app/windows/engine/.
# Needs Visual Studio 2022 or 2026 with C++, CMake >= 4.2 (VS 2026) and Strawberry Perl (OpenSSL).
#
#   powershell -ExecutionPolicy Bypass -File engine\build-windows.ps1              full build (first run: hours)
#   powershell -ExecutionPolicy Bypass -File engine\build-windows.ps1 -SkipDeps    reuse built dependencies
#   -Work C:\msbuild\orca   build folder (keep the path short: Windows path limit)
param(
    [string]$Work = 'C:\msbuild\orca',
    [switch]$SkipDeps
)
$ErrorActionPreference = 'Stop'

$Repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$Versions = @{}
Get-Content (Join-Path $Repo 'engine\VERSIONS') | Where-Object { $_ -match '^\s*([A-Z_]+)=(.+)$' } |
    ForEach-Object { $Versions[$Matches[1]] = $Matches[2].Trim() }
$Commit = $Versions['ENGINE_COMMIT']
$Out = Join-Path $Repo 'app\windows\engine'

function Step($text) { Write-Host "=== $text" -ForegroundColor Cyan }
function Run {
    $exe, $rest = $args
    # PowerShell 5.1 turns stderr lines of native tools into errors; only the exit code counts.
    $ErrorActionPreference = 'Continue'
    & $exe @rest 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "$exe beendet mit Exit-Code $LASTEXITCODE" }
}

Step '1/6 Werkzeuge'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio mit C++-Werkzeugen fehlt' }
$vsMajor = [int](& $vswhere -latest -products * -property installationVersion).Split('.')[0]
$generator = switch ($vsMajor) { 18 { 'Visual Studio 18 2026' } 17 { 'Visual Studio 17 2022' } default { throw "Visual Studio $vsMajor wird nicht unterstützt" } }
Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null

# Strawberry Perl ships its own old CMake and MinGW in c\bin; only its perl may be used.
$env:Path = ($env:Path.Split(';') | Where-Object { $_ -and $_ -notmatch 'Strawberry\\c\\bin' }) -join ';'
$perl = Get-Command perl -ErrorAction SilentlyContinue
if (-not $perl -or -not (& perl -e 'print $^O' | Select-String 'MSWin32')) {
    if (Test-Path 'C:\Strawberry\perl\bin\perl.exe') { $env:Path = "C:\Strawberry\perl\bin;$env:Path" }
    else { throw 'Strawberry Perl fehlt (winget install StrawberryPerl.StrawberryPerl)' }
}

$cmake = @(Get-Command cmake -All -ErrorAction SilentlyContinue | ForEach-Object Source) +
    @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Kitware.CMake*\*\bin\cmake.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName) +
    @("$env:ProgramFiles\CMake\bin\cmake.exe") |
    Where-Object { $_ -and (Test-Path $_) } |
    Where-Object { (& $_ --version | Select-Object -First 1) -match 'version (\d+)\.(\d+)' -and ([int]$Matches[1] -gt 4 -or ([int]$Matches[1] -eq 4 -and [int]$Matches[2] -ge 2)) } |
    Select-Object -First 1
if (-not $cmake) { throw 'CMake >= 4.2 fehlt (winget install Kitware.CMake)' }
# Some old dependencies still declare cmake_minimum_required below 3.5.
$env:CMAKE_POLICY_VERSION_MINIMUM = '3.5'
Write-Host "$generator, $cmake, $((Get-Command perl).Source)"

Step "2/6 Engine-Quellen @ $Commit"
if (-not (Test-Path (Join-Path $Work '.git'))) {
    New-Item -ItemType Directory -Force $Work | Out-Null
    Run git -C $Work init -q
    Run git -C $Work remote add origin https://github.com/Snapmaker/OrcaSlicer.git
}
if ((git -C $Work rev-parse HEAD 2>$null) -ne $Commit) {
    Run git -C $Work fetch -q --depth 1 origin $Commit
    Run git -C $Work checkout -q -f $Commit
}

Step '3/6 Desktop-Anpassungen'
# Idempotent text edits instead of patch files: the sources use CRLF line endings.
function Edit-Source([string]$Path, [string]$Marker, [string]$Pattern, [string]$Replacement) {
    $file = Join-Path $Work $Path
    $text = [IO.File]::ReadAllText($file)
    if ($text.Contains($Marker)) { return }
    $new = [regex]::Replace($text, $Pattern, $Replacement)
    if ($new -eq $text) { throw "Anpassung passt nicht mehr: $Path" }
    [IO.File]::WriteAllText($file, $new)
}
# Visual Studio 2026 (MSVC 19.50+) is newer than the fork's dependency script knows.
Edit-Source 'deps\deps-windows.cmake' 'DEP_VS_VER "18"' '(?m)^else \(\)(\r?\n)(\s+message\(FATAL_ERROR "Unsupported MSVC version"\))' `
    "elseif (MSVC_VERSION LESS 1960)`$1# 1950-1959 = VS 18.0 (v145 toolset)`$1    set(DEP_VS_VER `"18`")`$1    set(DEP_BOOST_TOOLSET `"msvc-14.5`")`$1else ()`$1`$2"
# The VS 2026 generator needs CMake >= 4.2; the fork only blocks CMake 4 out of caution (CMAKE_POLICY_VERSION_MINIMUM covers it).
Edit-Source 'CMakeLists.txt' 'CMake 4 allowed for VS 2026' '(?m)^(\s+)message\(FATAL_ERROR "Only cmake versions between 3\.13\.x and 3\.31\.x[^\r\n]*' `
    '$1message(STATUS "CMake 4 allowed for VS 2026: ${CMAKE_VERSION}")'
# Attaches engine/cli as an extra target next to libslic3r.
Edit-Source 'src\CMakeLists.txt' 'SLICER_CLI_DIR' '(?m)^add_subdirectory\(libslic3r\)(\r?\n)' `
    "add_subdirectory(libslic3r)`$1if (SLICER_CLI_DIR)`$1    add_subdirectory(`"`${SLICER_CLI_DIR}`" slicer_cli)`$1endif ()`$1"

# The dependency scripts only apply their patches when CMake's working directory is inside the git checkout.
Set-Location $Work
$deps = Join-Path $Work 'deps\build'
$destdir = Join-Path $deps 'OrcaSlicer_dep'
$prefix = Join-Path $destdir 'usr\local'
if (-not $SkipDeps) {
    Step '4/6 Abhängigkeiten (ohne wxWidgets, Sentry und andere reine GUI-Teile)'
    Run $cmake -S (Join-Path $Work 'deps') -B $deps -G $generator -A x64 "-DDESTDIR=$destdir" -DCMAKE_BUILD_TYPE=Release -DSLIC3R_SENTRY=OFF
    Run $cmake --build $deps --config Release --target dep_Boost dep_TBB dep_OpenSSL dep_CURL dep_Cereal dep_NLopt dep_OpenVDB `
        dep_GLEW dep_GLFW dep_OpenCV dep_CGAL dep_OCCT dep_FREETYPE dep_JPEG dep_PNG dep_ZLIB dep_EXPAT dep_libnoise --parallel
}

Step '5/6 slicer_cli bauen'
$build = Join-Path $Work 'build'
$cli = (Join-Path $Repo 'engine\cli').Replace('\', '/')
Run $cmake -S $Work -B $build -G $generator -A x64 -DSLIC3R_GUI=OFF -DSLIC3R_SENTRY=OFF -DSLIC3R_PCH=ON -DBBL_RELEASE_TO_PUBLIC=1 `
    "-DCMAKE_PREFIX_PATH=$($prefix.Replace('\', '/'))" -DCMAKE_BUILD_TYPE=Release "-DSLICER_CLI_DIR=$cli" `
    "-DOpenCV_DIR=$($prefix.Replace('\', '/'))/staticlib"
Run $cmake --build $build --config Release --target slicer_cli --parallel
$exe = Join-Path $build 'src\slicer_cli\Release\slicer_cli.exe'
if (-not (Test-Path $exe)) { throw "slicer_cli.exe fehlt: $exe" }

Step '6/6 nach app\windows\engine kopieren'
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item $exe $Out
# Non-system DLLs the engine needs, searched in the dependency and build folders.
$searchDirs = @((Join-Path $prefix 'bin'), (Join-Path (Join-Path $prefix 'bin') 'occt'), (Join-Path $prefix 'lib'), (Split-Path $exe))
$crt = Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
$queue = [Collections.Generic.Queue[string]]::new()
$queue.Enqueue((Join-Path $Out 'slicer_cli.exe'))
$seen = @{}
while ($queue.Count -gt 0) {
    $binary = $queue.Dequeue()
    foreach ($line in (& dumpbin /nologo /dependents $binary)) {
        if ($line -notmatch '^\s+(\S+\.dll)\s*$') { continue }
        $dll = $Matches[1]
        if ($seen.ContainsKey($dll.ToLower())) { continue }
        $seen[$dll.ToLower()] = $true
        $found = $searchDirs | ForEach-Object { Join-Path $_ $dll } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) {
            Copy-Item $found $Out
            $queue.Enqueue((Join-Path $Out $dll))
        } elseif ($crt -and (Test-Path (Join-Path $crt.FullName $dll))) {
            # The Visual C++ runtime goes along, so the engine runs without the redistributable installed.
            Copy-Item (Join-Path $crt.FullName $dll) $Out
        }
    }
}
Get-ChildItem $Out | Format-Table Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } -AutoSize
Write-Host "=== fertig: $Out" -ForegroundColor Green
