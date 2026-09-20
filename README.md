# 🎬 Church Display — v4.5

Sistema di proiezione per chiesa con integrazione **OpenLP**: mostra sui monitor
del palco versetti, canti, **immagini e presentazioni**, insieme a orologio,
timer per la predicazione, avvisi per la congregazione e — durante la diretta —
un **badge LIVE** con il nome della scena **OBS**. Il tecnico controlla tutto da
un tablet; l'oratore ha una vista dedicata (prompter).

## Architettura

```
PC con OpenLP ────► REST API (:4316) ────► Portatile Linux Mint
(testi + immagini)                             │
                                               ├── Server Node.js (:3000)
                                               │     ├── Proxy verso OpenLP
                                               │     ├── WebSocket (timer, messaggi, OBS)
                                               │     └── File statici
                                               │
                                               ├── HDMI ──► Splitter ──► Monitor 1
                                               │                    └──► Monitor 2
                                               │
                                               └── LAN ──► Tablet (Pannello Controllo)
                                                       └──► Tablet oratore (Prompter)

PC con OBS (Windows) ──► obs-bridge.py ──► Server (badge LIVE + scena)
```

## Le quattro pagine

| Pagina | URL | Scopo |
|--------|-----|-------|
| **Display** | `/display.html` | Proiezione fullscreen (monitor del palco) |
| **Controllo** | `/control.html` | Pannello regia (tablet tecnico) |
| **Prompter** | `/prompter.html` | Vista oratore (slide, timer, messaggi) |
| **Configuratore** | `/config.html` | Editor layout del display |

## Funzioni principali

- **Versetti e canti** da OpenLP, con transizioni in dissolvenza
- **Immagini e presentazioni** a schermo intero (compatibilità automatica OpenLP 2.4 / 3.x)
- **Timer** predicazione con preset, tempo personalizzato, e comportamento
  configurabile allo scadere (prosegue in rosso oppure lampeggia)
- **Orologio** e **avvisi su schermo** per la congregazione
- **Messaggi privati all'oratore** sul prompter (con indicatori di stato nel pannello)
- **Due interruttori indipendenti** per nascondere testo o immagini
- **Badge LIVE + scena OBS** durante la diretta streaming
- **Gestione monitor dal tablet** (sposta la proiezione, avvia il kiosk)
- **Configuratore layout** con anteprima 16:9, 5 preset (incluso "Palco 24″")
  e avviso di contrasto testo/sfondo
- **Aggiornamenti automatici da GitHub** con backup e rollback

## Installazione

Il sistema è distribuito come **un unico installatore**:

```bash
chmod +x church-display-installer.sh
./church-display-installer.sh
```

Installa da solo Node.js, Chromium e le dipendenze; chiede l'IP di OpenLP, il
monitor di destinazione e (opzionale) il collegamento a GitHub per gli
aggiornamenti. Crea il servizio di sistema e l'avvio automatico.

**Aggiornare** un'installazione esistente:

```bash
./church-display-installer.sh --update
```

## Configurazione

### Variabili d'ambiente (file `.env`)

```bash
PORT=3000              # Porta del server (default: 3000)
OPENLP_HOST=localhost  # IP del computer con OpenLP
OPENLP_PORT=4316       # Porta web remote di OpenLP
KIOSK_MONITOR=auto     # Monitor del kiosk: auto | interno | HDMI-1 ...
```

### OpenLP

Abilita il Web Remote: `Impostazioni → Configura OpenLP → Remote Interface`,
porta `4316`. Per le miniature di immagini/presentazioni sul prompter, attiva
anche *"Show thumbnails of non-text slides in remote and stage view"*.

## Aggiornamenti da GitHub

Dalla v4.5 il sistema si aggiorna da questo repository, con backup automatico
prima di ogni update e ripristino automatico (rollback) in caso di problemi.

```bash
./update.sh --check          # controlla se c'è un aggiornamento
./update.sh                  # aggiorna (con backup e rollback)
./update.sh --list-backups   # elenca i backup
./update.sh --rollback       # ripristina l'ultimo backup
```

L'aggiornamento avviene anche **automaticamente all'avvio** e con un pulsante
**"Cerca aggiornamenti"** nel pannello di controllo.

## Gestione monitor

Il kiosk si apre automaticamente sul **monitor esterno** (HDMI → splitter).

```bash
./start-display.sh          # avvia sul monitor esterno (auto)
./start-display.sh list     # elenca i monitor collegati
./move-display.sh           # sposta il kiosk sul monitor successivo
```

Oppure dal Pannello di Controllo, sezione **Monitor Proiezione**: sposta la
proiezione o riavvia il kiosk con un tap, senza toccare il portatile.

## Diretta OBS (opzionale)

Sul PC Windows che esegue OBS si installa un piccolo **ponte** (`obs-bridge.py`,
distribuito anche come installatore Windows) che invia al display lo stato della
diretta e la scena attiva. Badge LIVE rosso quando si è in onda, nome scena in
sovraimpressione. Vedi la documentazione del bridge.

## Servizio systemd

```bash
sudo systemctl status church-display      # stato del server
sudo systemctl restart church-display     # riavvio
journalctl -u church-display -f           # log in tempo reale
```

## Tecnologie

- **Node.js** + Express (server HTTP)
- **WebSocket** (`ws`) per timer, messaggi e stato OBS in tempo reale
- **http-proxy-middleware** per il proxy verso OpenLP
- **OpenLP REST API** (poll, testo slide, immagine live)
- HTML/CSS/JS vanilla (nessun framework frontend)
- **Git** per gli aggiornamenti

## API interne (REST)

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/version` | Versione installata |
| GET/POST | `/api/config` | Layout del display |
| GET | `/api/timer` | Stato timer |
| GET/POST | `/api/obs/state` | Stato diretta OBS (live, scena) |
| GET | `/api/update/check` | Controlla aggiornamenti |
| POST | `/api/update/apply` | Applica aggiornamento |
| ANY | `/openlp/*` | Proxy verso OpenLP |

## Documentazione

- **Manuale** completo (installazione, uso, risoluzione problemi)
- **Guida GitHub e aggiornamenti** (pubblicare versioni, collegare il PC)

## Licenza

Uso interno chiesa — software libero.
