/**
 * Church Display Server
 * ---------------------
 * Server Node.js per il sistema di proiezione chiesa.
 * Gestisce: proxy OpenLP, WebSocket (timer + messaggi), layout config.
 */

// Carica .env se presente
const envPath = require('path').join(__dirname, '.env');
try {
  const envContent = require('fs').readFileSync(envPath, 'utf-8');
  envContent.split('\n').forEach(line => {
    const match = line.match(/^\s*([\w]+)\s*=\s*(.*)\s*$/);
    if (match && !process.env[match[1]]) {
      process.env[match[1]] = match[2].replace(/^["']|["']$/g, '');
    }
  });
} catch {}

const express = require('express');
const { createServer } = require('http');
const { WebSocketServer } = require('ws');
const { createProxyMiddleware } = require('http-proxy-middleware');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

// Ambiente X11 per i comandi di gestione finestre
// (necessario quando il server gira come servizio systemd)
const X11_ENV = {
  ...process.env,
  DISPLAY: process.env.DISPLAY || ':0',
  XAUTHORITY: process.env.XAUTHORITY || path.join(require('os').homedir(), '.Xauthority')
};

// ─── Configurazione ───────────────────────────────────────────
// La versione è letta dal file VERSION (fonte unica, condivisa con l'updater)
let VERSION = '4.5';
try {
  VERSION = require('fs').readFileSync(require('path').join(__dirname, 'VERSION'), 'utf-8').trim() || VERSION;
} catch {}
const PORT = parseInt(process.env.PORT || '3000', 10);
const OPENLP_HOST = process.env.OPENLP_HOST || 'localhost';
const OPENLP_PORT = parseInt(process.env.OPENLP_PORT || '4316', 10);
const CONFIG_FILE = path.join(__dirname, 'config.json');

// ─── Layout Config ────────────────────────────────────────────
function loadConfig() {
  const def = getDefaultConfig();
  try {
    const loaded = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
    // Merge con i default: le config salvate da versioni precedenti
    // acquisiscono i nuovi campi (timerBehavior, elementi live/scene)
    return {
      ...def,
      ...loaded,
      background: { ...def.background, ...(loaded.background || {}) },
      elements: { ...def.elements, ...(loaded.elements || {}) },
      timerBehavior: { ...def.timerBehavior, ...(loaded.timerBehavior || {}) }
    };
  } catch {
    saveConfig(def);
    return def;
  }
}

function saveConfig(config) {
  // Newline finale: necessaria perché il file venga embeddato
  // correttamente negli heredoc dell'installatore monolitico
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2) + '\n');
}

function getDefaultConfig() {
  return {
    preset: 'standard',
    background: { color: '#000000', image: '' },
    // Comportamento del timer allo scadere:
    //   mode: 'overtime' = prosegue in negativo (+MM:SS in rosso)
    //         'blink'    = si ferma e lampeggia per blinkSeconds
    timerBehavior: { mode: 'overtime', blinkSeconds: 10 },
    elements: {
      verse:   { visible: true,  fontSize: 52, fontColor: '#ffffff', fontFamily: 'Georgia, serif', position: 'center', textAlign: 'center', textShadow: true },
      timer:   { visible: true,  fontSize: 40, fontColor: '#ffd700', fontFamily: "'Courier New', monospace", position: 'top-right', textAlign: 'right', textShadow: true },
      clock:   { visible: true,  fontSize: 22, fontColor: '#aaaaaa', fontFamily: "'Courier New', monospace", position: 'top-left', textAlign: 'left', textShadow: false },
      message: { visible: false, fontSize: 28, fontColor: '#00ff88', fontFamily: 'Arial, sans-serif', position: 'bottom-center', textAlign: 'center', textShadow: true },
      title:   { visible: true,  fontSize: 20, fontColor: '#888888', fontFamily: 'Arial, sans-serif', position: 'bottom-left', textAlign: 'left', textShadow: false },
      live:    { visible: true,  fontSize: 26, fontColor: '#ff3333', fontFamily: 'Arial, sans-serif', position: 'top-center', textAlign: 'center', textShadow: true },
      scene:   { visible: true,  fontSize: 20, fontColor: '#66ccff', fontFamily: 'Arial, sans-serif', position: 'bottom-right', textAlign: 'right', textShadow: true }
    }
  };
}

// ─── Timer State ──────────────────────────────────────────────
const timerState = {
  remaining: 0,
  total: 0,
  overtime: 0,        // secondi di sforamento (solo in modalità 'overtime')
  running: false,
  _interval: null
};

function getTimerBehavior() {
  const cfg = loadConfig();
  return cfg.timerBehavior || { mode: 'overtime', blinkSeconds: 10 };
}

function setTimerBehavior(behavior) {
  const cfg = loadConfig();
  cfg.timerBehavior = {
    mode: behavior.mode === 'blink' ? 'blink' : 'overtime',
    blinkSeconds: Math.max(1, Math.min(300, parseInt(behavior.blinkSeconds) || 10))
  };
  saveConfig(cfg);
  return cfg.timerBehavior;
}

function startTimer() {
  if (timerState.running) return;
  if (timerState.remaining <= 0 && timerState.overtime === 0 && timerState.total === 0) return;
  timerState.running = true;
  timerState._interval = setInterval(() => {
    const behavior = getTimerBehavior();
    if (timerState.remaining > 0) {
      timerState.remaining--;
      if (timerState.remaining === 0) {
        // Scadenza raggiunta
        broadcast({ type: 'timer_expired', data: { mode: behavior.mode, blinkSeconds: behavior.blinkSeconds } });
        if (behavior.mode === 'blink') {
          // Ferma il conteggio: lampeggio gestito dai client per blinkSeconds
          timerState.running = false;
          clearInterval(timerState._interval);
        }
        // In modalità 'overtime' il conteggio prosegue in negativo
      }
    } else if (behavior.mode === 'overtime') {
      timerState.overtime++;
    } else {
      // Modalità cambiata a 'blink' durante lo sforamento: fermati
      timerState.running = false;
      clearInterval(timerState._interval);
    }
    broadcast({ type: 'timer', data: getTimerData() });
  }, 1000);
}

function pauseTimer() {
  timerState.running = false;
  clearInterval(timerState._interval);
}

function resetTimer() {
  pauseTimer();
  timerState.remaining = timerState.total;
  timerState.overtime = 0;
}

function setTimer(seconds) {
  pauseTimer();
  timerState.total = seconds;
  timerState.remaining = seconds;
  timerState.overtime = 0;
}

function getTimerData() {
  const behavior = getTimerBehavior();
  return {
    remaining: timerState.remaining,
    total: timerState.total,
    overtime: timerState.overtime,
    running: timerState.running,
    mode: behavior.mode,
    blinkSeconds: behavior.blinkSeconds
  };
}

// ─── Messages ─────────────────────────────────────────────────
let currentSpeakerMessage = { text: '', from: '', timestamp: null };
let currentCongregationMessage = { text: '', from: '', timestamp: null };
const messageHistory = [];

// ─── Proiezione: visibilità separata testo e immagini ─────────
// hideText  = nasconde versetti/canti (contenuto testuale) sul display
// hideImage = nasconde le immagini/presentazioni sul display
// Retrocompatibilità: 'projection.visible' resta come specchio di !(hideText && hideImage)
let hideText = false;
let hideImage = false;

// ─── Stato OBS (live streaming) ───────────────────────────────
// Aggiornato via API dal PC che esegue OBS (bridge o curl)
const obsState = { live: false, scene: '', updatedAt: 0 };

// ─── Express App ──────────────────────────────────────────────
const app = express();
const server = createServer(app);

// JSON body parser
app.use(express.json());

// Proxy verso OpenLP (risolve CORS)
app.use('/openlp', createProxyMiddleware({
  target: `http://${OPENLP_HOST}:${OPENLP_PORT}`,
  changeOrigin: true,
  pathRewrite: { '^/openlp': '' },
  on: {
    error: (err, req, res) => {
      res.status(502).json({ error: 'OpenLP non raggiungibile', detail: err.message });
    }
  }
}));

// API REST per config
app.get('/api/config', (req, res) => res.json(loadConfig()));
app.post('/api/config', (req, res) => {
  saveConfig(req.body);
  broadcast({ type: 'config', data: req.body });
  res.json({ ok: true });
});

app.get('/api/timer', (req, res) => res.json(getTimerData()));
app.get('/api/version', (req, res) => res.json({ version: VERSION }));

// ─── Aggiornamento da GitHub ──────────────────────────────────
// Controlla se c'è una versione più recente (non applica nulla)
app.get('/api/update/check', (req, res) => {
  execFile(path.join(__dirname, 'update.sh'), ['--check'],
    { cwd: __dirname, timeout: 30000 }, (err, stdout, stderr) => {
      const out = (stdout || '') + (stderr || '');
      const avail = out.match(/UPDATE_AVAILABLE\s+(\S+)\s+(\S+)/);
      const uptodate = out.match(/UP_TO_DATE\s+(\S+)/);
      if (avail) {
        res.json({ updateAvailable: true, current: avail[1], latest: avail[2] });
      } else if (uptodate) {
        res.json({ updateAvailable: false, current: uptodate[1] });
      } else {
        res.status(502).json({ error: 'Controllo non riuscito', detail: out.trim().slice(-400) });
      }
    });
});

// Applica l'aggiornamento (backup + pull + npm + riavvio, con rollback automatico).
// Nota: il riavvio del servizio termina anche questo processo, quindi il client
// rileva l'esito ricollegandosi e richiamando /api/version.
app.post('/api/update/apply', (req, res) => {
  // Rispondi subito: l'update riavvia il server e chiuderebbe la connessione
  res.json({ ok: true, message: 'Aggiornamento avviato. Il server si riavvierà tra poco.' });
  const child = require('child_process').spawn(
    path.join(__dirname, 'update.sh'), [],
    { cwd: __dirname, detached: true, stdio: 'ignore' }
  );
  child.unref();
});

// Stato dei backup disponibili
app.get('/api/update/backups', (req, res) => {
  execFile(path.join(__dirname, 'update.sh'), ['--list-backups'],
    { cwd: __dirname, timeout: 10000 }, (err, stdout) => {
      const lines = (stdout || '').split('\n')
        .map(l => l.trim()).filter(l => l.startsWith('backup-'));
      res.json({ backups: lines });
    });
});

// ─── OBS: stato live e scena ──────────────────────────────────
app.get('/api/obs/state', (req, res) => res.json(obsState));
app.post('/api/obs/state', (req, res) => {
  const b = req.body || {};
  if (typeof b.live === 'boolean') obsState.live = b.live;
  if (typeof b.scene === 'string') obsState.scene = b.scene.substring(0, 100);
  obsState.updatedAt = Date.now();
  broadcast({ type: 'obs', data: obsState });
  res.json({ ok: true, state: obsState });
});

// ─── Info per aprire il telecomando OpenLP dal tablet ─────────
app.get('/api/openlp-info', (req, res) => {
  // Se OpenLP è su localhost, dal tablet va raggiunto tramite
  // l'IP del portatile (che è lo stesso host del server)
  let host = OPENLP_HOST;
  if (host === 'localhost' || host === '127.0.0.1') {
    host = req.hostname || getLocalIP();
  }
  res.json({ url: `http://${host}:${OPENLP_PORT}/`, host, port: OPENLP_PORT });
});
app.get('/api/messages', (req, res) => res.json({ speaker: currentSpeakerMessage, congregation: currentCongregationMessage, history: messageHistory }));

// ─── Gestione Monitor (kiosk) ─────────────────────────────────
// Elenca i monitor collegati (via xrandr)
app.get('/api/display/monitors', (req, res) => {
  execFile('xrandr', ['--query'], { env: X11_ENV }, (err, stdout) => {
    if (err) return res.status(500).json({ error: 'xrandr non disponibile', detail: err.message });
    const monitors = [];
    for (const line of stdout.split('\n')) {
      const m = line.match(/^(\S+) connected\s*(primary)?\s*(\d+)x(\d+)\+(\d+)\+(\d+)/);
      if (m) {
        monitors.push({
          name: m[1],
          primary: !!m[2],
          width: parseInt(m[3]),
          height: parseInt(m[4]),
          x: parseInt(m[5]),
          y: parseInt(m[6]),
          internal: /^(eDP|LVDS)/.test(m[1])
        });
      }
    }
    res.json({ monitors });
  });
});

// Sposta il kiosk su un monitor (o cicla se target vuoto)
app.post('/api/display/move', (req, res) => {
  // Sanifica: solo caratteri validi per nomi monitor xrandr
  const target = String(req.body?.target || '').replace(/[^\w.-]/g, '');
  const args = target ? [target] : [];
  execFile(path.join(__dirname, 'move-display.sh'), args, { env: X11_ENV, timeout: 10000 }, (err, stdout, stderr) => {
    if (err) return res.status(500).json({ error: 'Spostamento fallito', detail: (stderr || err.message).trim() });
    res.json({ ok: true, output: stdout.trim() });
  });
});

// (Ri)avvia il kiosk su un monitor specifico
app.post('/api/display/start', (req, res) => {
  const target = String(req.body?.target || '').replace(/[^\w.-]/g, '');
  const args = target ? [target] : [];
  execFile(path.join(__dirname, 'start-display.sh'), args, { env: X11_ENV, timeout: 90000 }, () => {});
  // Non aspettiamo la fine (il kiosk resta in esecuzione): rispondi subito
  res.json({ ok: true, message: 'Avvio kiosk in corso...' });
});

// File statici
app.use(express.static(path.join(__dirname, 'public')));

// ─── WebSocket Server ─────────────────────────────────────────
const wss = new WebSocketServer({ server });
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);

  // Invia stato corrente al nuovo client
  ws.send(JSON.stringify({ type: 'timer', data: getTimerData() }));
  ws.send(JSON.stringify({ type: 'config', data: loadConfig() }));
  ws.send(JSON.stringify({ type: 'projection', data: { hideText, hideImage } }));
  if (obsState.updatedAt) {
    ws.send(JSON.stringify({ type: 'obs', data: obsState }));
  }
  if (currentSpeakerMessage.text) {
    ws.send(JSON.stringify({ type: 'speaker_message', data: currentSpeakerMessage }));
  }
  if (currentCongregationMessage.text) {
    ws.send(JSON.stringify({ type: 'congregation_message', data: currentCongregationMessage }));
  }

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      handleWsMessage(ws, msg);
    } catch (e) {
      console.error('WS parse error:', e.message);
    }
  });

  ws.on('close', () => clients.delete(ws));
  ws.on('error', () => clients.delete(ws));
});

function broadcast(msg, exclude = null) {
  const data = JSON.stringify(msg);
  for (const client of clients) {
    if (client !== exclude && client.readyState === 1) {
      client.send(data);
    }
  }
}

function handleWsMessage(ws, msg) {
  switch (msg.type) {
    // ── Timer ──
    case 'timer_set':
      setTimer(msg.data.seconds);
      broadcast({ type: 'timer', data: getTimerData() });
      break;
    case 'timer_start':
      startTimer();
      broadcast({ type: 'timer', data: getTimerData() });
      break;
    case 'timer_pause':
      pauseTimer();
      broadcast({ type: 'timer', data: getTimerData() });
      break;
    case 'timer_reset':
      resetTimer();
      broadcast({ type: 'timer', data: getTimerData() });
      break;
    case 'timer_add':
      timerState.remaining = Math.max(0, timerState.remaining + (msg.data.seconds || 0));
      if (timerState.remaining > timerState.total) timerState.total = timerState.remaining;
      if (timerState.remaining > 0) timerState.overtime = 0;
      broadcast({ type: 'timer', data: getTimerData() });
      break;
    case 'timer_behavior_set': {
      const b = setTimerBehavior(msg.data || {});
      broadcast({ type: 'timer', data: getTimerData() });
      break;
    }

    // ── OBS ──
    case 'obs_set':
      if (typeof msg.data?.live === 'boolean') obsState.live = msg.data.live;
      if (typeof msg.data?.scene === 'string') obsState.scene = msg.data.scene.substring(0, 100);
      obsState.updatedAt = Date.now();
      broadcast({ type: 'obs', data: obsState });
      break;

    // ── Messaggi ──
    case 'speaker_message':
      currentSpeakerMessage = { text: msg.data.text, from: msg.data.from || 'Regia', timestamp: Date.now() };
      messageHistory.push({ ...currentSpeakerMessage, target: 'speaker' });
      broadcast({ type: 'speaker_message', data: currentSpeakerMessage });
      break;
    case 'congregation_message':
      currentCongregationMessage = { text: msg.data.text, from: msg.data.from || 'Regia', timestamp: Date.now() };
      messageHistory.push({ ...currentCongregationMessage, target: 'congregation' });
      broadcast({ type: 'congregation_message', data: currentCongregationMessage });
      break;
    case 'clear_speaker_message':
      currentSpeakerMessage = { text: '', from: '', timestamp: null };
      broadcast({ type: 'speaker_message', data: currentSpeakerMessage });
      break;
    case 'clear_congregation_message':
      currentCongregationMessage = { text: '', from: '', timestamp: null };
      broadcast({ type: 'congregation_message', data: currentCongregationMessage });
      break;

    // ── Proiezione ON/OFF ──
    case 'projection_set':
      // Retrocompat: se arriva {visible}, agisce su entrambi
      if (typeof msg.data?.visible === 'boolean') {
        hideText = !msg.data.visible;
        hideImage = !msg.data.visible;
      }
      if (typeof msg.data?.hideText === 'boolean') hideText = msg.data.hideText;
      if (typeof msg.data?.hideImage === 'boolean') hideImage = msg.data.hideImage;
      broadcast({ type: 'projection', data: { hideText, hideImage } });
      break;

    // ── Config ──
    case 'config_save':
      saveConfig(msg.data);
      broadcast({ type: 'config', data: msg.data });
      break;
  }
}

// ─── Avvio ────────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
  const ip = getLocalIP();
  console.log('');
  console.log('╔══════════════════════════════════════════════════╗');
  console.log(`║        🎬  CHURCH DISPLAY SERVER  v${VERSION}          ║`);
  console.log('╠══════════════════════════════════════════════════╣');
  console.log(`║  Server:       http://${ip}:${PORT}`);
  console.log(`║  OpenLP:       http://${OPENLP_HOST}:${OPENLP_PORT}`);
  console.log('╠══════════════════════════════════════════════════╣');
  console.log(`║  📺 Display:      http://${ip}:${PORT}/display.html`);
  console.log(`║  🎛️  Controllo:    http://${ip}:${PORT}/control.html`);
  console.log(`║  🎤 Prompter:     http://${ip}:${PORT}/prompter.html`);
  console.log(`║  ⚙️  Configuratore: http://${ip}:${PORT}/config.html`);
  console.log('╚══════════════════════════════════════════════════╝');
  console.log('');
});

function getLocalIP() {
  const nets = require('os').networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) return net.address;
    }
  }
  return 'localhost';
}
