; ═══════════════════════════════════════════════════════════════
;
;   CHURCH OBS BRIDGE — Installatore per Windows 10/11 (64 bit)
;
;   Da compilare con Inno Setup 6.1 o superiore.
;   Compilazione: apri questo file in Inno Setup → Build → Compile
;   oppure da riga di comando:  ISCC.exe church-obs-bridge.iss
;
;   Cosa fa l'installatore prodotto:
;     1. Verifica se Python (3.10+) è installato; se manca lo
;        scarica da python.org e lo installa in automatico
;     2. Installa le dipendenze pip (obsws-python, requests)
;     3. Chiede: indirizzo del server Church Display, password
;        WebSocket di OBS, cosa conta come "LIVE"
;     4. Registra il bridge come attività di sistema: parte al
;        boot di Windows (senza login) e si riavvia da solo
;        in caso di errore
;     5. Avvia subito il bridge
;
; ═══════════════════════════════════════════════════════════════

#define MyAppName "Church OBS Bridge"
#define MyAppVersion "4.5"
#define MyAppPublisher "Church Display"
#define TaskName "ChurchOBSBridge"
#define PythonVersion "3.12.8"
#define PythonURL "https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe"

[Setup]
AppId={{B7E3D2A4-51C6-4F8B-9A0D-3E7F2C1B8D45}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\ChurchOBSBridge
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputBaseFilename=ChurchOBSBridge-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
SetupLogging=yes

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"

[Files]
Source: "..\obs-bridge.py"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{commonappdata}\ChurchOBSBridge"

[Icons]
Name: "{autoprograms}\{#MyAppName}\Log del bridge"; Filename: "notepad.exe"; Parameters: """{commonappdata}\ChurchOBSBridge\bridge.log"""
Name: "{autoprograms}\{#MyAppName}\Modifica configurazione"; Filename: "notepad.exe"; Parameters: """{app}\run-bridge.bat"""
Name: "{autoprograms}\{#MyAppName}\Riavvia bridge"; Filename: "{app}\restart-bridge.bat"
Name: "{autoprograms}\{#MyAppName}\Disinstalla"; Filename: "{uninstallexe}"

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/End /TN ""{#TaskName}"""; Flags: runhidden; RunOnceId: "StopTask"
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""{#TaskName}"" /F"; Flags: runhidden; RunOnceId: "DelTask"

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\ChurchOBSBridge"

[Code]
var
  ConfigPage: TInputQueryWizardPage;
  LiveOnPage: TInputOptionWizardPage;
  DownloadPage: TDownloadWizardPage;
  PythonExe: String;

// ─── Rilevamento Python nel registro (3.13 → 3.10, HKLM e HKCU) ───
function DetectPython(): String;
var
  Versions: array[0..3] of String;
  i: Integer;
  InstallPath: String;
begin
  Result := '';
  Versions[0] := '3.13';
  Versions[1] := '3.12';
  Versions[2] := '3.11';
  Versions[3] := '3.10';
  for i := 0 to 3 do
  begin
    if RegQueryStringValue(HKLM64, 'SOFTWARE\Python\PythonCore\' + Versions[i] + '\InstallPath', '', InstallPath) or
       RegQueryStringValue(HKCU, 'SOFTWARE\Python\PythonCore\' + Versions[i] + '\InstallPath', '', InstallPath) then
    begin
      if FileExists(AddBackslash(InstallPath) + 'python.exe') then
      begin
        Result := AddBackslash(InstallPath) + 'python.exe';
        Exit;
      end;
    end;
  end;
end;

function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

procedure InitializeWizard;
begin
  // Pagina 1: configurazione connessioni
  ConfigPage := CreateInputQueryPage(wpSelectDir,
    'Configurazione del bridge',
    'Collegamento al server Church Display e a OBS',
    'Inserisci i dati di collegamento. Potrai modificarli in seguito dal menu Start → Church OBS Bridge → Modifica configurazione.');
  ConfigPage.Add('Indirizzo del server Church Display (es. http://192.168.1.100:3000):', False);
  ConfigPage.Add('Password WebSocket di OBS (vuoto se disabilitata):', True);
  ConfigPage.Values[0] := 'http://192.168.1.100:3000';
  ConfigPage.Values[1] := '';

  // Pagina 2: cosa conta come LIVE
  LiveOnPage := CreateInputOptionPage(ConfigPage.ID,
    'Modalità LIVE',
    'Quando mostrare il badge LIVE sui monitor del palco',
    'Scegli quale attività di OBS accende il badge LIVE:',
    True, False);
  LiveOnPage.Add('Streaming (diretta) — consigliato');
  LiveOnPage.Add('Registrazione');
  LiveOnPage.Add('Entrambi (streaming oppure registrazione)');
  LiveOnPage.SelectedValueIndex := 0;

  // Pagina download (usata solo se Python manca)
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing),
    SetupMessage(msgPreparingDesc), @OnDownloadProgress);
end;

// ─── Validazione input ───
function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;

  if CurPageID = ConfigPage.ID then
  begin
    if (Pos('http://', ConfigPage.Values[0]) <> 1) and (Pos('https://', ConfigPage.Values[0]) <> 1) then
    begin
      MsgBox('L''indirizzo del server deve iniziare con http:// (es. http://192.168.1.100:3000)', mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;

  // Alla pagina di riepilogo: se Python manca, scaricalo e installalo
  if CurPageID = wpReady then
  begin
    PythonExe := DetectPython();
    if PythonExe = '' then
    begin
      DownloadPage.Clear;
      DownloadPage.Add('{#PythonURL}', 'python-installer.exe', '');
      DownloadPage.Show;
      try
        try
          DownloadPage.Download;
        except
          MsgBox('Download di Python non riuscito.' + #13#10 +
                 'Verifica la connessione a internet e riprova,' + #13#10 +
                 'oppure installa Python manualmente da python.org' + #13#10 +
                 '(spuntando "Add python.exe to PATH") e rilancia questo setup.',
                 mbError, MB_OK);
          Result := False;
          Exit;
        end;
      finally
        DownloadPage.Hide;
      end;

      WizardForm.StatusLabel.Caption := 'Installazione di Python {#PythonVersion} in corso (1-2 minuti)...';
      if not Exec(ExpandConstant('{tmp}\python-installer.exe'),
                  '/quiet InstallAllUsers=1 PrependPath=1 Include_test=0',
                  '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
      begin
        MsgBox('Avvio dell''installazione di Python non riuscito.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
      if ResultCode <> 0 then
      begin
        MsgBox('L''installazione di Python è terminata con errore (codice ' + IntToStr(ResultCode) + ').',
               mbError, MB_OK);
        Result := False;
        Exit;
      end;

      PythonExe := DetectPython();
      if PythonExe = '' then
      begin
        MsgBox('Python risulta installato ma non è stato trovato nel registro.' + #13#10 +
               'Riavvia il PC e rilancia questo setup.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end;
  end;
end;

// ─── Helpers ───
function LiveOnValue(): String;
begin
  case LiveOnPage.SelectedValueIndex of
    0: Result := 'streaming';
    1: Result := 'recording';
    2: Result := 'both';
  end;
end;

function BuildBridgeCommand(): String;
begin
  Result := '"' + PythonExe + '" "' + ExpandConstant('{app}') + '\obs-bridge.py"' +
            ' --server ' + ConfigPage.Values[0] +
            ' --live-on ' + LiveOnValue();
  if Trim(ConfigPage.Values[1]) <> '' then
    Result := Result + ' --obs-password "' + ConfigPage.Values[1] + '"';
end;

// XML dell'attività pianificata: avvio al boot come SYSTEM,
// riavvio automatico ogni minuto in caso di errore, nessun limite di durata
function BuildTaskXml(): String;
var
  BatPath: String;
begin
  BatPath := ExpandConstant('{app}') + '\run-bridge.bat';
  Result :=
    '<?xml version="1.0"?>' + #13#10 +
    '<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' + #13#10 +
    '  <RegistrationInfo>' + #13#10 +
    '    <Description>Ponte OBS - Church Display: inoltra stato diretta e scena ai monitor del palco</Description>' + #13#10 +
    '  </RegistrationInfo>' + #13#10 +
    '  <Triggers>' + #13#10 +
    '    <BootTrigger><Enabled>true</Enabled><Delay>PT20S</Delay></BootTrigger>' + #13#10 +
    '  </Triggers>' + #13#10 +
    '  <Principals>' + #13#10 +
    '    <Principal id="Author">' + #13#10 +
    '      <UserId>S-1-5-18</UserId>' + #13#10 +
    '      <RunLevel>HighestAvailable</RunLevel>' + #13#10 +
    '    </Principal>' + #13#10 +
    '  </Principals>' + #13#10 +
    '  <Settings>' + #13#10 +
    '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>' + #13#10 +
    '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' + #13#10 +
    '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' + #13#10 +
    '    <StartWhenAvailable>true</StartWhenAvailable>' + #13#10 +
    '    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' + #13#10 +
    '    <RestartOnFailure>' + #13#10 +
    '      <Interval>PT1M</Interval>' + #13#10 +
    '      <Count>999</Count>' + #13#10 +
    '    </RestartOnFailure>' + #13#10 +
    '  </Settings>' + #13#10 +
    '  <Actions Context="Author">' + #13#10 +
    '    <Exec>' + #13#10 +
    '      <Command>"' + BatPath + '"</Command>' + #13#10 +
    '    </Exec>' + #13#10 +
    '  </Actions>' + #13#10 +
    '</Task>' + #13#10;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  BatContent, RestartBat, XmlPath: String;
begin
  if CurStep = ssPostInstall then
  begin
    // 1) Dipendenze pip
    WizardForm.StatusLabel.Caption := 'Installazione dipendenze Python (obsws-python, requests)...';
    if not Exec(PythonExe, '-m pip install --upgrade obsws-python requests',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    begin
      MsgBox('Installazione delle dipendenze pip non riuscita (serve internet).' + #13#10 +
             'Puoi completarla a mano aprendo un Prompt dei comandi come amministratore:' + #13#10#13#10 +
             '  "' + PythonExe + '" -m pip install obsws-python requests' + #13#10#13#10 +
             'poi riavvia il bridge dal menu Start.', mbInformation, MB_OK);
    end;

    // 2) Genera run-bridge.bat (la configurazione modificabile)
    BatContent :=
      '@echo off' + #13#10 +
      'rem ═══ Church OBS Bridge — configurazione ═══' + #13#10 +
      'rem Modifica gli argomenti qui sotto per cambiare server, password o modalita''.' + #13#10 +
      'rem Poi riavvia il bridge dal menu Start (Riavvia bridge).' + #13#10 +
      BuildBridgeCommand() +
      ' > "' + ExpandConstant('{commonappdata}') + '\ChurchOBSBridge\bridge.log" 2>&1' + #13#10;
    SaveStringToFile(ExpandConstant('{app}') + '\run-bridge.bat', BatContent, False);

    // 3) Genera restart-bridge.bat
    RestartBat :=
      '@echo off' + #13#10 +
      'schtasks /End /TN "{#TaskName}" >nul 2>&1' + #13#10 +
      'timeout /t 2 /nobreak >nul' + #13#10 +
      'schtasks /Run /TN "{#TaskName}"' + #13#10 +
      'echo Bridge riavviato. Log: %ProgramData%\ChurchOBSBridge\bridge.log' + #13#10 +
      'pause' + #13#10;
    SaveStringToFile(ExpandConstant('{app}') + '\restart-bridge.bat', RestartBat, False);

    // 4) Registra l'attività pianificata
    WizardForm.StatusLabel.Caption := 'Registrazione avvio automatico...';
    XmlPath := ExpandConstant('{tmp}') + '\church-obs-bridge-task.xml';
    SaveStringToFile(XmlPath, BuildTaskXml(), False);
    Exec('schtasks.exe', '/Delete /TN "{#TaskName}" /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if not Exec('schtasks.exe', '/Create /TN "{#TaskName}" /XML "' + XmlPath + '"',
                '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    begin
      MsgBox('Registrazione dell''avvio automatico non riuscita (codice ' + IntToStr(ResultCode) + ').' + #13#10 +
             'Puoi registrarla a mano: vedi il LEGGIMI.', mbError, MB_OK);
    end
    else
    begin
      // 5) Avvia subito il bridge
      Exec('schtasks.exe', '/Run /TN "{#TaskName}"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;
