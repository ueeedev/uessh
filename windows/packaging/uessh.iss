; Inno Setup script for the Windows installer.
; Built by .github/workflows/release.yml:
;   ISCC.exe /DAppVersion=0.1.1 /DSourceDir=build\windows\x64\runner\Release
;            /DOutputDir=dist windows\packaging\uessh.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Keep this id forever: it is how Windows knows a new version upgrades
; the installed one instead of installing a second copy.
AppId={{12B00CEE-5CB8-4013-8D0C-ACD68F698195}
AppName=uessh
AppVersion={#AppVersion}
AppVerName=uessh {#AppVersion}
AppPublisher=dev.ueee
AppPublisherURL=https://github.com/ueeedev/uessh
DefaultDirName={autopf}\uessh
DefaultGroupName=uessh
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\uessh.exe
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=uessh-{#AppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Per-user install works without admin rights; users can choose all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; Not every Inno Setup install ships a Chinese translation; use it if present.
#if FileExists(CompilerPath + "Languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\uessh"; Filename: "{app}\uessh.exe"
Name: "{group}\{cm:UninstallProgram,uessh}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\uessh"; Filename: "{app}\uessh.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\uessh.exe"; Description: "{cm:LaunchProgram,uessh}"; Flags: nowait postinstall skipifsilent
