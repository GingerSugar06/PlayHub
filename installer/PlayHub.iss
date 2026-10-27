; Play Hub — Windows kurulum sihirbazı (Inno Setup 6)
; Derleme: tool\make_installer.ps1  (ISCC'yi kendisi çağırır)

#define MyAppName "Play Hub"
#define MyAppExe "play_hub.exe"
#define MyAppVersion "1.0.0"
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7B1E2C54-3A0F-4D6B-9C21-5E8A47D10F63}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=PlayHub-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Yönetici izni gerekmez: kullanıcı profiline kurulur.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
turkish.DesktopIcon=Masaüstüne kısayol oluştur
english.DesktopIcon=Create a desktop shortcut
turkish.LaunchApp={#MyAppName} uygulamasını başlat
english.LaunchApp=Launch {#MyAppName}
turkish.SteamMissing=Bu bilgisayarda Steam bulunamadı.%n%n{#MyAppName}, Steam istemcisiyle birlikte çalışır. Steam'i kurup oturum açtıktan sonra uygulamayı kullanabilirsin.%n%nYine de kuruluma devam edilsin mi?
english.SteamMissing=Steam was not found on this computer.%n%n{#MyAppName} works together with the Steam client. Install Steam and sign in before using the app.%n%nContinue with the installation anyway?
turkish.PythonEngine=Başka hesapları kasmak için Python 3.12 ve gerekli paketleri kur (önerilir; "Bu bilgisayar" modu için gerekmez)
english.PythonEngine=Install Python 3.12 and the required packages to idle other accounts (recommended; not needed for "This PC" mode)
turkish.InstallingPython=Python kuruluyor...
english.InstallingPython=Installing Python...
turkish.InstallingPackages=Motor paketleri kuruluyor (internet gerekir)...
english.InstallingPackages=Installing engine packages (internet required)...

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; Flags: unchecked
Name: "pythonengine"; Description: "{cm:PythonEngine}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ çalışma zamanı DLL'leri uygulamayla birlikte (yönetici izni / ayrı kurulum gerektirmez)
Source: "redist\crt\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\python-3.12.10-amd64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsPython; Tasks: pythonengine

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\python-3.12.10-amd64.exe"; Parameters: "/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=0 Include_test=0 Shortcuts=0"; StatusMsg: "{cm:InstallingPython}"; Flags: waituntilterminated; Tasks: pythonengine; Check: NeedsPython
Filename: "{code:GetPythonExe}"; Parameters: "-m pip install --disable-pip-version-check -r ""{app}\engine\requirements.txt"""; StatusMsg: "{cm:InstallingPackages}"; Flags: waituntilterminated runhidden; Tasks: pythonengine
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[Code]
function SteamInstalled(): Boolean;
var
  p: String;
begin
  Result := False;
  if RegQueryStringValue(HKCU, 'Software\Valve\Steam', 'SteamPath', p) then
    Result := DirExists(p)
  else if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath', p) then
    Result := DirExists(p);
end;

function PythonExe(): String;
var
  v: Integer;
  k, p: String;
begin
  Result := '';
  for v := 13 downto 9 do
  begin
    k := Format('Software\Python\PythonCore\3.%d\InstallPath', [v]);
    if RegQueryStringValue(HKCU, k, 'ExecutablePath', p) and FileExists(p) then begin Result := p; Exit; end;
    if RegQueryStringValue(HKLM, k, 'ExecutablePath', p) and FileExists(p) then begin Result := p; Exit; end;
    if RegQueryStringValue(HKCU, k, '', p) and FileExists(AddBackslash(p) + 'python.exe') then begin Result := AddBackslash(p) + 'python.exe'; Exit; end;
  end;
  p := ExpandConstant('{localappdata}\Programs\Python\Python312\python.exe');
  if FileExists(p) then Result := p;
end;

function NeedsPython(): Boolean;
begin
  Result := PythonExe() = '';
end;

function GetPythonExe(Param: String): String;
begin
  Result := PythonExe();
end;


function InitializeSetup(): Boolean;
begin
  Result := True;
  if not SteamInstalled() then
    Result := (MsgBox(CustomMessage('SteamMissing'), mbConfirmation, MB_YESNO) = IDYES);
end;
