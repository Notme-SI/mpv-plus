#define AppVersion "1.1.0"

[Setup]
AppId={{55794CC2-4BF5-4D67-BF18-AF9DFA0539D3}
AppName=mpv+
AppVersion={#AppVersion}
AppVerName=mpv+ {#AppVersion}
VersionInfoVersion={#AppVersion}.0
VersionInfoDescription=mpv+ {#AppVersion} Setup
DefaultDirName={localappdata}\Programs\mpv-plus
DefaultGroupName=mpv+
UsePreviousGroup=no
DisableProgramGroupPage=no
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
SetupIconFile=payload\portable_config\assets\mpv-monochrome.ico
UninstallDisplayIcon={app}\mpv+.exe
UninstallDisplayName=mpv+ {#AppVersion}
UninstallFilesDir={app}\uninstall
OutputDir=output
OutputBaseFilename=mpv+-{#AppVersion}-Setup
Compression=lzma2/normal
SolidCompression=yes
CloseApplications=yes
CloseApplicationsFilter=mpv+.exe,mpv.exe,mpv.com,ffmpeg.exe
RestartApplications=no
AllowNoIcons=yes
ShowLanguageDialog=yes
SetupLogging=yes
UsedUserAreasWarning=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"; InfoAfterFile: "finish-ru.txt"
Name: "english"; MessagesFile: "compiler:Default.isl"; InfoAfterFile: "finish-en.txt"

[CustomMessages]
russian.DesktopShortcut=Создать ярлык на рабочем столе
english.DesktopShortcut=Create a desktop shortcut
russian.ConfigureTorrServer=Настроить TorrServer
english.ConfigureTorrServer=Configure TorrServer
russian.UpdateMPV=Обновить mpv+
english.UpdateMPV=Update mpv+
russian.LaunchMPV=Запустить mpv+
english.LaunchMPV=Launch mpv+
russian.ReadGuide=Открыть инструкцию
english.ReadGuide=Open the guide
russian.SettingsNote=При повторной установке в эту папку личные настройки сохраняются. Автоматических бэкапов нет.
english.SettingsNote=Reinstalling into this folder preserves your personal settings. No automatic backups are created.

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; Flags: unchecked

[Files]
#include "files.iss"

[InstallDelete]
Type: files; Name: "{app}\Обновить mpv+.cmd"
Type: files; Name: "{app}\Обновить MPV.cmd"
Type: files; Name: "{app}\Настроить TorrServer.cmd"
Type: files; Name: "{app}\Сохранить бэкап.cmd"
Type: files; Name: "{app}\ПРОЧТИ МЕНЯ.txt"
Type: files; Name: "{app}\PUBLIC-AUDIT.txt"
Type: files; Name: "{app}\VERSION.txt"
Type: files; Name: "{app}\SOURCES.txt"
Type: files; Name: "{app}\mpv.com"

[Icons]
Name: "{group}\mpv+"; Filename: "{app}\mpv+.exe"; WorkingDir: "{app}"; IconFilename: "{app}\portable_config\assets\mpv-monochrome.ico"
Name: "{autodesktop}\mpv+"; Filename: "{app}\mpv+.exe"; WorkingDir: "{app}"; IconFilename: "{app}\portable_config\assets\mpv-monochrome.ico"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\portable_config\maintenance\Set-Branding.ps1"" -PlayerRoot ""{app}"" -GroupPath ""{group}"""; Flags: runhidden waituntilterminated
Filename: "{app}\mpv+.exe"; WorkingDir: "{app}"; Description: "{cm:LaunchMPV}"; Flags: nowait postinstall skipifsilent unchecked runasoriginaluser
Filename: "{app}\README.txt"; Description: "{cm:ReadGuide}"; Flags: shellexec postinstall skipifsilent unchecked runasoriginaluser

[Code]
procedure InitializeWizard;
var
  Note: TNewStaticText;
begin
  Note := TNewStaticText.Create(WizardForm);
  Note.Parent := WizardForm.SelectDirPage;
  Note.Left := WizardForm.DirEdit.Left;
  Note.Top := WizardForm.DirEdit.Top + WizardForm.DirEdit.Height + ScaleY(16);
  Note.Width := WizardForm.DirEdit.Width;
  Note.AutoSize := False;
  Note.Height := ScaleY(60);
  Note.WordWrap := True;
  Note.Caption := CustomMessage('SettingsNote');
end;
