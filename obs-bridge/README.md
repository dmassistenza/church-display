# Bridge OBS → Church Display (Windows)

Progetto per creare l'installatore Windows del **ponte OBS**, che invia al
display lo stato della diretta (badge LIVE) e il nome della scena attiva.

## File

- `church-obs-bridge.iss` — progetto Inno Setup. Lo script `obs-bridge.py` viene
  preso automaticamente dalla cartella principale del repo (`..\obs-bridge.py`),
  quindi non serve copiarlo: è lo stesso file usato anche dall'installatore Linux.

## Come compilare

1. Apri `church-obs-bridge.iss` con **Inno Setup 6** o superiore
2. **Build → Compile** (o F9)
3. Ottieni `Output\ChurchOBSBridge-Setup.exe`

> Tieni la struttura del repo intatta: il `.iss` cerca `obs-bridge.py` nella
> cartella superiore. Se sposti il `.iss` altrove, aggiorna il percorso della
> riga `Source:`.

## Setup già pronto

Se non vuoi compilare, l'installatore già pronto (`ChurchOBSBridge-Setup.exe`)
è allegato alle **Release** del progetto su GitHub (sezione "Releases" a destra
nella home del repo).

## Cosa fa l'installatore sul PC OBS

- Installa Python se manca (lo scarica da python.org)
- Installa le dipendenze (obsws-python, requests)
- Chiede l'indirizzo del server Church Display e la password WebSocket di OBS
- Registra il bridge come attività di sistema che parte al boot, con riavvio
  automatico in caso di errore
- Avvia subito il bridge

Prerequisito in OBS: **Strumenti → Impostazioni server WebSocket** → abilita
(porta 4455).
