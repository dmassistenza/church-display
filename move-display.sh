#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  move-display.sh — Sposta il display kiosk GIÀ APERTO
#                    su un altro monitor, senza riavviarlo
#
#  Uso:
#    ./move-display.sh            → cicla al monitor successivo
#    ./move-display.sh HDMI-1     → sposta su monitor specifico
#    ./move-display.sh interno    → sposta sullo schermo portatile
#
#  Richiede: wmctrl e xdotool
#    sudo apt install wmctrl xdotool
# ═══════════════════════════════════════════════════════════

# ── Verifica dipendenze ──
for dep in wmctrl xdotool xrandr; do
    if ! command -v $dep &>/dev/null; then
        echo "❌ Manca '$dep'. Installa con: sudo apt install wmctrl xdotool x11-xserver-utils"
        exit 1
    fi
done

# ── Trova la finestra del display ──
WIN_ID=$(xdotool search --name "Church Display" | head -1)
if [ -z "$WIN_ID" ]; then
    echo "❌ Finestra 'Church Display' non trovata. Il kiosk è avviato?"
    echo "   Avvialo con: ./start-display.sh"
    exit 1
fi

# ── Elenca i monitor ──
mapfile -t MONITORS < <(xrandr --query | grep " connected" | awk '{print $1}')
declare -A GEOMS
for M in "${MONITORS[@]}"; do
    GEOMS[$M]=$(xrandr --query | grep "^$M connected" | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+" | head -1)
done

# ── Determina il monitor di destinazione ──
TARGET="$1"

if [ -z "$TARGET" ]; then
    # Cicla: trova su quale monitor è ora la finestra, vai al successivo
    WIN_X=$(xdotool getwindowgeometry --shell "$WIN_ID" | grep "^X=" | cut -d= -f2)
    CURRENT=""
    for M in "${MONITORS[@]}"; do
        G="${GEOMS[$M]}"
        MX=$(echo "$G" | cut -d+ -f2)
        MW=$(echo "$G" | cut -dx -f1)
        if [ "$WIN_X" -ge "$MX" ] && [ "$WIN_X" -lt "$((MX + MW))" ]; then
            CURRENT="$M"
            break
        fi
    done
    # Trova il monitor successivo nella lista
    NEXT_IDX=0
    for i in "${!MONITORS[@]}"; do
        if [ "${MONITORS[$i]}" = "$CURRENT" ]; then
            NEXT_IDX=$(( (i + 1) % ${#MONITORS[@]} ))
            break
        fi
    done
    TARGET="${MONITORS[$NEXT_IDX]}"
elif [ "$TARGET" = "interno" ]; then
    TARGET=$(xrandr --query | grep " connected" | grep -E "^(eDP|LVDS)" | awk '{print $1}' | head -1)
fi

GEOM="${GEOMS[$TARGET]}"
if [ -z "$GEOM" ]; then
    echo "❌ Monitor '$TARGET' non trovato. Monitor disponibili:"
    for M in "${MONITORS[@]}"; do echo "   $M → ${GEOMS[$M]}"; done
    exit 1
fi

W=$(echo "$GEOM" | cut -dx -f1)
H=$(echo "$GEOM" | cut -dx -f2 | cut -d+ -f1)
X=$(echo "$GEOM" | cut -d+ -f2)
Y=$(echo "$GEOM" | cut -d+ -f3)

echo "🖥️  Sposto il display su: $TARGET (${W}x${H} @ +${X}+${Y})"

# ── Sposta: esci da fullscreen → sposta → torna fullscreen ──
wmctrl -i -r "$WIN_ID" -b remove,fullscreen
sleep 0.3
xdotool windowmove "$WIN_ID" "$X" "$Y"
xdotool windowsize "$WIN_ID" "$W" "$H"
sleep 0.3
wmctrl -i -r "$WIN_ID" -b add,fullscreen

echo "✅ Fatto!"
