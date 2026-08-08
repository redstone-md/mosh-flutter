; Windows installer for the Flutter shell.
;
; `flutter build windows` only ever emits a folder, and the port never picked
; up a packaging step -- the Mosh_<version>_x64-setup.exe / .msi named in
; CODE_SIGNING.md were produced by the Tauri shell's bundled NSIS/WiX, which
; did not survive the rewrite. This script is the replacement.
;
; Build (after `flutter build windows --release`):
;   iscc windows\installer\mosh.iss
;   iscc /DAppVersion=1.2.3 windows\installer\mosh.iss
;
; Output: build\installer\mosh-<version>-setup.exe
;
; Per-user by design: PrivilegesRequired=lowest installs under
; %LOCALAPPDATA%\Programs with no UAC prompt, which is what a messenger
; wants -- nothing here needs machine-wide state, and an elevation prompt on
; top of the unsigned-binary SmartScreen warning is two scares instead of one.
;
; NOT signed. Signing happens on tagged releases through SignPath (see
; CODE_SIGNING.md); a locally built installer is unsigned and SmartScreen
; will flag it.

#ifndef AppVersion
  #define AppVersion "0.8.0-dev"
#endif

#define AppName "Mosh"
#define AppExeName "mosh.exe"
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Stable across versions: the uninstaller and every upgrade key off it.
; Changing it would strand previously installed copies.
AppId={{7B3F9C21-4E58-4A6D-9F2A-0C51D7E8B4A3}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion=0.8.0.0
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..\build\installer
OutputBaseFilename=mosh-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
; The Rust core and the Moss FFI layer are built x64-only
; (android/app/build.gradle.kts pins arm64 for the phone; there is no 32-bit
; desktop target), so refuse a 32-bit host outright rather than installing a
; bundle that cannot load its own DLLs.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Everything, recursively. The bundle is not separable: mosh.exe is a 100 KB
; stub, and the app needs flutter_windows.dll, data\app.so, every plugin DLL
; the generated registrant loads at startup, and moss.dll (which mosh_core
; dlopens -- see the install rule in windows\CMakeLists.txt).
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; redb + the attachment store live in the roaming data dir, NOT under {app}.
; They are deliberately left in place: uninstalling must not destroy message
; history, and the at-rest DEK stays in Credential Manager so a reinstall
; picks the history back up. Only the extracted bundle goes.
Type: filesandordirs; Name: "{app}\data"
