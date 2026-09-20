#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  start-display.sh — Avvia il display kiosk sul monitor scelto
#
#  Uso:
#    ./start-display.sh              → monitor esterno (auto)
#    ./start-display.sh interno      → schermo del portatile
#    ./start-display.sh HDMI-1       → monitor specifico (nome xrandr)
#    ./start-display.sh list         → elenca i monitor disponibili
# ═══════════════════════════════════════════════════════════
cd "$(dirname "$0")"

# ── Carica configurazione ──
if [ -f .env ]; then
    set -a; source .env; set +a
fi
PORT=${PORT:-3000}
URL="http://localhost:$PORT/display.html"

# ── Elenco monitor ──
if [ "$1" = "list" ]; then
    echo ""
    echo "Monitor collegati:"
    echo "──────────────────────────────────────────"
    xrandr --query | grep " connected" | while read -r line; do
        NAME=$(echo "$line" | awk '{print $1}')
        GEOM=$(echo "$line" | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+")
        PRIMARY=$(echo "$line" | grep -q primary && echo " (primario)")
        echo "  $NAME  →  $GEOM$PRIMARY"
    done
    echo ""
    exit 0
fi

# ── Rileva il browser disponibile ──
BROWSER=""
for b in chromium-browser chromium google-chrome firefox; do
    if command -v "$b" &>/dev/null; then BROWSER="$b"; break; fi
done
if [ -z "$BROWSER" ]; then
    echo "❌ Nessun browser trovato. Installa: sudo apt install chromium-browser"
    exit 1
fi

# ── Rileva la geometria del monitor di destinazione ──
# Priorità: argomento CLI → variabile KIOSK_MONITOR in .env → auto
TARGET=${1:-${KIOSK_MONITOR:-auto}}

get_geometry() {
    # $1 = nome monitor oppure "auto" / "interno"
    case "$1" in
        auto)
            # Preferisci un monitor ESTERNO (non eDP/LVDS = schermo portatile)
            xrandr --query | grep " connected" | grep -Ev "^(eDP|LVDS)" \
                | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+" | head -1
            ;;
        interno)
            xrandr --query | grep " connected" | grep -E "^(eDP|LVDS)" \
                | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+" | head -1
            ;;
        *)
            xrandr --query | grep "^$1 connected" \
                | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+" | head -1
            ;;
    esac
}

GEOM=$(get_geometry "$TARGET")

# Fallback: qualsiasi monitor connesso
if [ -z "$GEOM" ]; then
    echo "⚠️  Monitor '$TARGET' non trovato, uso il primo disponibile"
    GEOM=$(xrandr --query | grep " connected" | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+" | head -1)
fi

if [ -z "$GEOM" ]; then
    echo "❌ Impossibile rilevare i monitor (xrandr non disponibile?)"
    exit 1
fi

# Estrai larghezza, altezza, offset X, offset Y  (es. 1920x1080+1920+0)
W=$(echo "$GEOM" | cut -dx -f1)
H=$(echo "$GEOM" | cut -dx -f2 | cut -d+ -f1)
X=$(echo "$GEOM" | cut -d+ -f2)
Y=$(echo "$GEOM" | cut -d+ -f3)

echo "🖥️  Monitor di destinazione: ${W}x${H} @ posizione +${X}+${Y}"

# ── Attendi che il server sia pronto ──
echo "⏳ Attesa avvio server su $URL ..."
for i in $(seq 1 60); do
    curl -s -o /dev/null "$URL" && break
    sleep 1
done

# ── Disabilita screensaver e spegnimento schermo ──
xset s off 2>/dev/null
xset s noblank 2>/dev/null
xset -dpms 2>/dev/null

# ── Chiudi eventuali kiosk precedenti ──
pkill -f "user-data-dir=/tmp/church-kiosk" 2>/dev/null
sleep 0.5

# ── Avvia il browser in kiosk sul monitor scelto ──
# NOTA: --user-data-dir separato è FONDAMENTALE, altrimenti Chromium
#       riusa il profilo esistente e ignora --window-position
"$BROWSER" \
    --kiosk \
    --window-position=$X,$Y \
    --window-size=$W,$H \
    --user-data-dir=/tmp/church-kiosk \
    --no-first-run \
    --disable-translate \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-features=TranslateUI \
    --noerrdialogs \
    --autoplay-policy=no-user-gesture-required \
    "$URL" &

echo "✅ Display avviato in kiosk mode sul monitor selezionato"
echo ""
echo "   Per spostarlo su un altro monitor:  ./move-display.sh"
echo "   Per chiuderlo:                      pkill -f church-kiosk"
