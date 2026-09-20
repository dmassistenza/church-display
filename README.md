# 🎬 Church Display — v3.0

Sistema di proiezione per chiesa con integrazione OpenLP, timer configurabile,
orologio e comunicazione in tempo reale con l'oratore.

## Architettura

```
PC con OpenLP ────► REST API (:4316) ────► Portatile Linux Mint
                                               │
                                               ├── Server Node.js (:3000)
                                               │     ├── Proxy verso OpenLP
                                               │     ├── WebSocket (timer + messaggi)
                                               │     └── File statici
                                               │
                                               ├── HDMI ──► Splitter ──► Monitor 1
                                               │                    └──► Monitor 2
                                               │
                                               └── LAN ──► Tablet (Pannello Controllo)
                                                       └──► Laptop/Tablet oratore (Prompter)
```

## Pagine

| Pagina | URL | Scopo |
|--------|-----|-------|
| **Display** | `/display.html` | Proiezione fullscreen (monitors) |
| **Controllo** | `/control.html` | Pannello regia (tablet tecnico) |
| **Prompter** | `/prompter.html` | Vista oratore (slide + messaggi) |
| **Configuratore** | `/config.html` | Editor layout display |

## Installazione rapida

```bash
# 1. Clona o copia la cartella nel portatile Linux Mint
# 2. Esegui il setup
chmod +x setup.sh
./setup.sh

# 3. Avvia il server
node server.js

# 4. Avvia il display in kiosk mode
./start-display.sh
```

## Installazione manuale

```bash
# Prerequisiti
sudo apt install nodejs npm chromium-browser

# Dipendenze
cd church-display
npm install

# Avvia
node server.js
```

## Configurazione

### Variabili d'ambiente

Puoi creare un file `.env` oppure passarle direttamente:

```bash
PORT=3000              # Porta del server (default: 3000)
OPENLP_HOST=localhost  # IP del computer con OpenLP
OPENLP_PORT=4316       # Porta web remote di OpenLP
```

Se OpenLP gira sullo **stesso** portatile, le impostazioni di default vanno bene.

Se OpenLP gira su un **altro** computer:

```bash
OPENLP_HOST=192.168.1.100 node server.js
```

### OpenLP

In OpenLP, abilita il Web Remote:
1. `Impostazioni` → `Configura OpenLP` → `Remote Interface`
2. Verifica che la porta sia `4316`
3. Se richiesto, premi `Check for Updates` / `Upgrade`

### Layout Display

Apri il Configuratore Layout da qualsiasi browser in LAN:

```
http://<ip-portatile>:3000/config.html
```

Funzionalità:
- **4 preset**: Standard, Minimale, Completo, Focus Timer
- **Per ogni elemento** (versetto, timer, orologio, titolo, avviso):
  - Visibile / nascosto
  - Posizione (9 zone: angoli, centri, centro)
  - Font, dimensione, colore
  - Allineamento testo
  - Ombra testo
- **Sfondo**: colore + immagine opzionale
- **Anteprima live** a 16:9
- Salvataggio in tempo reale (broadcast a tutti i display connessi)

## Utilizzo

### Display (proiezione)

- Apri `http://localhost:3000/display.html` su Chromium
- Doppio click per fullscreen
- Il cursore si nasconde automaticamente dopo 3 secondi
- Indicatore LED in alto a destra: verde = OpenLP connesso

### Pannello di Controllo (tablet/telefono)

- Apri `http://<ip>:3000/control.html` dal tablet
- **Timer**: preset rapidi (5/10/15/30 min), tempo personalizzato, ±1 minuto
- **Messaggi oratore**: testo libero + bottoni rapidi predefiniti
- **Avviso su schermo**: messaggi visibili sui monitor della congregazione
- **Stato OpenLP**: mostra la slide corrente

### Prompter (oratore)

- Apri `http://<ip>:3000/prompter.html` su un tablet/laptop
- Mostra: slide corrente + slide successiva + tag versetto
- Timer ben visibile con avviso colore (giallo → arancione → rosso)
- Banner messaggi dalla regia con vibrazione (se supportata)
- Barra progresso slide
- Doppio click per fullscreen

## Tecnologie

- **Node.js** + Express (server HTTP)
- **WebSocket** (`ws`) per comunicazione real-time
- **http-proxy-middleware** per proxy verso OpenLP
- **OpenLP REST API** v1 (`/api/poll`, `/api/controller/live/text`)
- HTML/CSS/JS vanilla (nessun framework frontend)

## API interne

### REST

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/config` | Layout corrente |
| POST | `/api/config` | Salva layout |
| GET | `/api/timer` | Stato timer |
| GET | `/api/messages` | Messaggi correnti |
| ANY | `/openlp/*` | Proxy verso OpenLP |

### WebSocket

Messaggi JSON su `ws://<ip>:3000`:

**Dal client:**
- `{ type: "timer_set", data: { seconds: 600 } }`
- `{ type: "timer_start" }` / `timer_pause` / `timer_reset`
- `{ type: "timer_add", data: { seconds: 60 } }`
- `{ type: "speaker_message", data: { text: "...", from: "Regia" } }`
- `{ type: "congregation_message", data: { text: "..." } }`
- `{ type: "clear_speaker_message" }` / `clear_congregation_message`
- `{ type: "config_save", data: { ... } }`

**Dal server (broadcast):**
- `{ type: "timer", data: { remaining, total, running } }`
- `{ type: "timer_expired" }`
- `{ type: "speaker_message", data: { text, from, timestamp } }`
- `{ type: "congregation_message", data: { text, from, timestamp } }`
- `{ type: "config", data: { ... } }`

## Gestione monitor (kiosk sul secondo schermo)

Il kiosk viene aperto **automaticamente sul monitor esterno** (HDMI → splitter),
non sullo schermo del portatile. Rilevamento via `xrandr`.

### Da terminale

```bash
./start-display.sh              # avvia sul monitor esterno (auto)
./start-display.sh interno      # avvia sullo schermo del portatile
./start-display.sh HDMI-1       # avvia su un monitor specifico
./start-display.sh list         # elenca i monitor collegati
./move-display.sh               # sposta il kiosk GIÀ APERTO al monitor successivo
./move-display.sh HDMI-1        # sposta su un monitor specifico
```

### Dal Pannello di Controllo (tablet) 🆕

Nella sezione **🖥️ Monitor Proiezione** del pannello di controllo puoi:
- Vedere l'elenco dei monitor collegati (interno/esterno, risoluzione)
- **Spostare la proiezione** su qualsiasi monitor con un tap
- Ciclare tra i monitor
- (Ri)avviare il kiosk da remoto

Non serve più toccare il portatile: tutto dal tablet.

### Monitor predefinito

La scelta fatta durante il setup viene salvata in `.env` (`KIOSK_MONITOR=auto`).
Valori: `auto` (esterno), `interno`, oppure il nome xrandr (es. `HDMI-1`).

## Avvio automatico completo

Dopo il setup, all'accensione del portatile:

1. **Server** → parte come servizio systemd (anche senza login)
2. **Kiosk** → parte al login della sessione grafica (con delay di 8s)

Per un'esperienza "accendi e vai", attiva il **login automatico** su Linux Mint:
`Menu → Finestra di login → Impostazioni → Login automatico`

## Servizio systemd

Il servizio viene creato automaticamente dal setup:

```bash
sudo systemctl start church-display     # Avvia
sudo systemctl stop church-display      # Ferma
sudo systemctl restart church-display   # Riavvia
sudo systemctl status church-display    # Stato
journalctl -u church-display -f         # Log live
```

## Troubleshooting

**OpenLP non si connette**
- Verifica che il Web Remote sia attivo in OpenLP
- Controlla che il firewall permetta la porta 4316
- Se OpenLP è su un altro PC: `curl http://<ip-openlp>:4316/api/poll`

**Display non si aggiorna**
- Controlla il pallino LED verde in alto a destra del display
- Verifica la console del browser (F12) per errori

**WebSocket disconnesso**
- Il sistema si riconnette automaticamente ogni 2 secondi
- Verifica che il server sia in esecuzione

**Il kiosk si apre sul monitor sbagliato**
- Usa `./move-display.sh` o il bottone "Sposta qui" dal pannello di controllo
- Verifica i monitor con `./start-display.sh list`
- Imposta il monitor predefinito in `.env`: `KIOSK_MONITOR=HDMI-1`

**"Sposta qui" dal pannello non funziona**
- Installa le dipendenze: `sudo apt install wmctrl xdotool x11-xserver-utils`
- Se il server gira come systemd, verifica che DISPLAY sia corretto:
  `systemctl cat church-display | grep DISPLAY` (deve essere `:0`)
- Riavvia il servizio: `sudo systemctl restart church-display`

**Lo schermo si spegne durante il culto**
- Il display usa la Wake Lock API + `xset -dpms` nello script di avvio
- Se persiste: disattiva il risparmio energetico nelle impostazioni di Mint

## Licenza

Uso interno chiesa — software libero.
