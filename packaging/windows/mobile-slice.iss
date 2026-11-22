; Inno Setup script for the Windows installer (built by .github/workflows/release.yml).
; Compile: ISCC /DAppVersion=1.0.0 /DSourceDir=<flutter Release folder> /DOutputDir=<out> mobile-slice.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\app\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Fixed AppId so later versions update the existing installation.
AppId={{6F1B7A52-3C1E-4F7B-9B0D-5A3E2C8D41A7}
AppName=Mobile Slice
AppVersion={#AppVersion}
AppVerName=Mobile Slice {#AppVersion}
AppPublisher=Mobile Slice
AppPublisherURL=https://github.com/Dizzle-code/mobile-slice
AppSupportURL=https://github.com/Dizzle-code/mobile-slice/issues
DefaultDirName={autopf}\Mobile Slice
DefaultGroupName=Mobile Slice
DisableProgramGroupPage=yes
; Installs for the current user without admin rights; the dialog still offers "for all users".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Mobile-Slice-{#AppVersion}-Windows-Setup
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mobile_slice.exe
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Flutter itself also needs the Visual C++ runtime; the engine folder already ships it app-local.
Source: "{#SourceDir}\engine\MSVCP140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\engine\VCRUNTIME140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\engine\VCRUNTIME140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Mobile Slice"; Filename: "{app}\mobile_slice.exe"
Name: "{autodesktop}\Mobile Slice"; Filename: "{app}\mobile_slice.exe"; Tasks: desktopicon

[Registry]
; Lets "Öffnen mit" offer Mobile Slice for STL and 3MF files.
Root: HKA; Subkey: "Software\Classes\Applications\mobile_slice.exe\SupportedTypes"; ValueType: string; ValueName: ".stl"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\mobile_slice.exe\SupportedTypes"; ValueType: string; ValueName: ".3mf"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.stl\OpenWithProgids"; ValueType: string; ValueName: "MobileSlice.Model"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.3mf\OpenWithProgids"; ValueType: string; ValueName: "MobileSlice.Model"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\MobileSlice.Model"; ValueType: string; ValueName: ""; ValueData: "3D-Modell"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\MobileSlice.Model\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\mobile_slice.exe"" ""%1"""

[Run]
Filename: "{app}\mobile_slice.exe"; Description: "{cm:LaunchProgram,Mobile Slice}"; Flags: nowait postinstall skipifsilent
