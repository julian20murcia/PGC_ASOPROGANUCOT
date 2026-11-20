; Instalador de ASOPROGANUCOTT para Windows (Inno Setup 6).
; Compilar:  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\asoproganucott.iss
; Requiere antes:  flutter build windows --release
; Incluye las DLL del runtime de Visual C++ (despliegue local) para que
; funcione en un Windows limpio sin instalar nada más.

#define AppName "ASOPROGANUCOTT"
#define AppVersion "1.0.0"
#define AppExe "pgc_asoproganucot.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{7C1F3E52-9B7A-4D5E-8A41-A50B0A0A0001}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=ASOPROGANUCOTT
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=Instalador_ASOPROGANUCOTT_{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "runtime\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent
