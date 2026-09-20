#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════
#  obs-bridge.py — Ponte tra OBS Studio e Church Display
#
#  Da eseguire sul PC che esegue OBS (Windows, Mac o Linux).
#  Legge lo stato di OBS (diretta attiva + scena corrente) tramite
#  obs-websocket e lo inoltra al server Church Display, che mostra
#  il badge LIVE e il nome della scena sui monitor del palco.
#
#  Requisiti (una volta sola):
#      pip install obsws-python requests
#
#  In OBS: Strumenti -> Impostazioni server WebSocket
#      -> Abilita server WebSocket (porta 4455)
#      -> annota la password (o disabilitala)
#
#  Uso:
#      python obs-bridge.py --server http://IP-PORTATILE:3000
#      python obs-bridge.py --server http://192.168.1.50:3000 --obs-password MIAPASS
#
#  Opzioni:
#      --server        URL del server Church Display (obbligatorio)
#      --obs-host      host di OBS (default: localhost)
#      --obs-port      porta websocket OBS (default: 4455)
#      --obs-password  password websocket OBS (default: nessuna)
#      --live-on       cosa conta come "LIVE": streaming | recording | both
#                      (default: streaming)
# ═══════════════════════════════════════════════════════════════
import argparse
import sys
import time

# Su Windows la console usa cp1252 e va in crash se si stampano caratteri
# non-ASCII (accenti, simboli). Forziamo UTF-8 sull'output.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    import requests
except ImportError:
    print("Manca 'requests'. Installa con:  pip install requests")
    sys.exit(1)

try:
    import obsws_python as obs
except ImportError:
    print("Manca 'obsws-python'. Installa con:  pip install obsws-python")
    sys.exit(1)


def parse_args():
    p = argparse.ArgumentParser(description="Ponte OBS -> Church Display")
    p.add_argument("--server", required=True, help="URL server Church Display, es. http://192.168.1.50:3000")
    p.add_argument("--obs-host", default="localhost")
    p.add_argument("--obs-port", type=int, default=4455)
    p.add_argument("--obs-password", default="")
    p.add_argument("--live-on", choices=["streaming", "recording", "both"], default="streaming")
    return p.parse_args()


class Bridge:
    def __init__(self, args):
        self.args = args
        self.server = self.normalize_server(args.server)
        self.endpoint = self.server + "/api/obs/state"
        self.live = False
        self.scene = ""
        self.streaming = False
        self.recording = False

    # ── Normalizza e valida l'URL del server ──
    @staticmethod
    def normalize_server(raw):
        s = (raw or "").strip()
        # Errori comuni: spazi interni, "/3000" invece di ":3000"
        s = s.replace(" ", "")
        # "http://192.168.1.127/3000" -> "http://192.168.1.127:3000"
        import re
        m = re.match(r"^(https?://)([^/:]+)/(\d{2,5})(/.*)?$", s)
        if m:
            s = f"{m.group(1)}{m.group(2)}:{m.group(3)}"
        # Manca lo schema
        if not s.startswith("http://") and not s.startswith("https://"):
            s = "http://" + s
        # Porta mancante -> assume 3000
        m2 = re.match(r"^(https?://)([^/:]+)(/.*)?$", s)
        if m2 and ":" not in m2.group(2):
            s = f"{m2.group(1)}{m2.group(2)}:3000"
        return s.rstrip("/")

    # ── Test di raggiungibilità del server all'avvio ──
    def check_server(self):
        try:
            r = requests.get(self.server + "/api/version", timeout=4)
            v = r.json().get("version", "?")
            print(f"[OK] Server Church Display raggiungibile ({self.server}) - versione {v}")
            return True
        except requests.RequestException as e:
            print(f"[X] Server Church Display NON raggiungibile: {self.server}")
            print(f"   Dettaglio: {e}")
            print(f"   Verifica: IP corretto? formato http://IP:3000 (due punti, niente spazi)?")
            print(f"   Stesso segmento di rete? Il portatile Linux e' acceso e il servizio attivo?")
            return False

    # ── Invio al server Church Display ──
    def push(self):
        try:
            requests.post(self.endpoint, json={"live": self.live, "scene": self.scene}, timeout=3)
            print(f"-> live={'SI' if self.live else 'no'}  scena='{self.scene}'")
        except requests.RequestException as e:
            print(f"[!]  Server Church Display non raggiungibile: {e}")

    def compute_live(self):
        mode = self.args.live_on
        if mode == "streaming":
            self.live = self.streaming
        elif mode == "recording":
            self.live = self.recording
        else:
            self.live = self.streaming or self.recording

    # ── Loop principale con riconnessione ──
    def run(self):
        print(f"Church OBS Bridge - server: {self.server}")
        self.check_server()  # diagnostica immediata, non blocca comunque l'avvio
        while True:
            try:
                self.session()
            except KeyboardInterrupt:
                print("\nChiusura.")
                return
            except Exception as e:
                print(f"[!]  Connessione OBS persa ({e}). Riprovo tra 5s...")
                time.sleep(5)

    def session(self):
        a = self.args
        print(f"Connessione a OBS su {a.obs_host}:{a.obs_port}...")
        req = obs.ReqClient(host=a.obs_host, port=a.obs_port, password=a.obs_password, timeout=5)
        ev = obs.EventClient(host=a.obs_host, port=a.obs_port, password=a.obs_password, timeout=5)
        print("[OK] Connesso a OBS")

        # Stato iniziale
        self.scene = req.get_current_program_scene().scene_name
        self.streaming = req.get_stream_status().output_active
        try:
            self.recording = req.get_record_status().output_active
        except Exception:
            self.recording = False
        self.compute_live()
        self.push()

        # Eventi
        def on_current_program_scene_changed(data):
            self.scene = data.scene_name
            self.push()

        def on_stream_state_changed(data):
            self.streaming = data.output_active
            self.compute_live()
            self.push()

        def on_record_state_changed(data):
            self.recording = data.output_active
            self.compute_live()
            self.push()

        ev.callback.register(on_current_program_scene_changed)
        ev.callback.register(on_stream_state_changed)
        ev.callback.register(on_record_state_changed)

        # Heartbeat: il display nasconde il badge se non riceve nulla per 30s,
        # quindi rimandiamo lo stato ogni 10s
        while True:
            time.sleep(10)
            # Verifica che OBS risponda ancora (solleva eccezione se caduto)
            self.scene = req.get_current_program_scene().scene_name
            self.push()


if __name__ == "__main__":
    Bridge(parse_args()).run()
