#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  update.sh — Aggiornamento di Church Display da GitHub
#
#  Fa in sequenza, in sicurezza:
#    1. Verifica se c'è una versione più recente su GitHub
#    2. Crea un BACKUP completo prima di toccare qualsiasi cosa
#    3. Scarica la nuova versione (git pull)
#    4. Reinstalla le dipendenze (npm install)
#    5. Riavvia il servizio
#    6. Verifica che il server risponda; se NO → ROLLBACK automatico
#
#  I dati dell'utente (config.json, .env) NON vengono mai toccati.
#
#  Uso:
#    ./update.sh --check        solo controlla, non aggiorna (per il pulsante)
#    ./update.sh                controlla e, se c'è un aggiornamento, lo applica
#    ./update.sh --force        applica anche se le versioni sembrano uguali
#    ./update.sh --rollback     ripristina manualmente l'ultimo backup
#    ./update.sh --list-backups elenca i backup disponibili
#
#  Esce con codice:
#    0 = ok / nessun aggiornamento    1 = errore    2 = aggiornamento disponibile (--check)
# ═══════════════════════════════════════════════════════════════
set -o pipefail
cd "$(dirname "$0")"
APP_DIR="$(pwd)"
BACKUP_DIR="$APP_DIR/.backups"
MAX_BACKUPS=5
SERVICE="church-display"

# Carica configurazione (porta del server per l'health-check)
[ -f .env ] && set -a && source .env && set +a
PORT="${PORT:-3000}"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
err()  { echo "[$(date '+%H:%M:%S')] ERRORE: $*" >&2; }

# ─── Lettura versioni ─────────────────────────────────────────
local_version() {
  cat "$APP_DIR/VERSION" 2>/dev/null | tr -d '[:space:]'
}

remote_version() {
  # Legge il file VERSION dal branch remoto senza modificare la working copy
  git fetch --quiet origin 2>/dev/null || return 1
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  git show "origin/${branch}:VERSION" 2>/dev/null | tr -d '[:space:]'
}

# Confronta due versioni tipo 4.5 / 4.10 — ritorna 0 se $1 > $2
version_gt() {
  [ "$1" = "$2" ] && return 1
  local greater
  greater="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)"
  [ "$greater" = "$1" ]
}

# ─── Prerequisiti ─────────────────────────────────────────────
require_git_repo() {
  if [ ! -d "$APP_DIR/.git" ]; then
    err "Questa cartella non è un repository Git."
    err "L'aggiornamento da GitHub richiede un'installazione via 'git clone'."
    err "Vedi il LEGGIMI per convertire un'installazione esistente."
    exit 1
  fi
}

# ─── Controllo aggiornamenti ──────────────────────────────────
do_check() {
  require_git_repo
  local lv rv
  lv="$(local_version)"
  rv="$(remote_version)"
  if [ -z "$rv" ]; then
    err "Impossibile leggere la versione remota (rete? repository?)."
    exit 1
  fi
  log "Versione locale:  ${lv:-sconosciuta}"
  log "Versione remota:  ${rv}"
  if version_gt "$rv" "$lv"; then
    log "→ Aggiornamento disponibile: ${lv} → ${rv}"
    # Output legibile dal server per il pulsante
    echo "UPDATE_AVAILABLE ${lv} ${rv}"
    return 2
  else
    log "→ Sei già aggiornato."
    echo "UP_TO_DATE ${lv}"
    return 0
  fi
}

# ─── Backup ───────────────────────────────────────────────────
create_backup() {
  mkdir -p "$BACKUP_DIR"
  local ts stamp dest
  ts="$(date '+%Y%m%d-%H%M%S')"
  dest="$BACKUP_DIR/backup-${ts}-v$(local_version)"
  log "Backup in corso → $dest"

  mkdir -p "$dest"
  # Salva il commit corrente (per il rollback via git) e i file utente
  git rev-parse HEAD > "$dest/GIT_COMMIT" 2>/dev/null
  cp -a "$APP_DIR/VERSION"     "$dest/" 2>/dev/null
  cp -a "$APP_DIR/config.json" "$dest/" 2>/dev/null
  cp -a "$APP_DIR/.env"        "$dest/" 2>/dev/null
  cp -a "$APP_DIR/package.json" "$dest/" 2>/dev/null
  cp -a "$APP_DIR/package-lock.json" "$dest/" 2>/dev/null

  echo "$dest" > "$BACKUP_DIR/LAST_BACKUP"
  log "Backup completato."

  # Ruota i vecchi backup (tieni gli ultimi MAX_BACKUPS)
  local count
  count="$(ls -1d "$BACKUP_DIR"/backup-* 2>/dev/null | wc -l)"
  if [ "$count" -gt "$MAX_BACKUPS" ]; then
    ls -1dt "$BACKUP_DIR"/backup-* | tail -n +$((MAX_BACKUPS+1)) | while read -r old; do
      log "Rimuovo backup vecchio: $(basename "$old")"
      rm -rf "$old"
    done
  fi
}

# ─── Health check ─────────────────────────────────────────────
health_ok() {
  local i
  for i in $(seq 1 20); do
    if curl -fsS -m 3 "http://localhost:${PORT}/api/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# ─── Rollback ─────────────────────────────────────────────────
do_rollback() {
  local backup="$1"
  [ -z "$backup" ] && backup="$(cat "$BACKUP_DIR/LAST_BACKUP" 2>/dev/null)"
  if [ -z "$backup" ] || [ ! -d "$backup" ]; then
    err "Nessun backup da ripristinare."
    return 1
  fi
  log "ROLLBACK dal backup: $(basename "$backup")"

  # Ripristina il commit git salvato
  local commit
  commit="$(cat "$backup/GIT_COMMIT" 2>/dev/null)"
  if [ -n "$commit" ]; then
    git reset --hard "$commit" >/dev/null 2>&1 || git checkout . >/dev/null 2>&1
  fi
  # Ripristina i file utente
  cp -a "$backup/config.json" "$APP_DIR/" 2>/dev/null
  cp -a "$backup/.env"        "$APP_DIR/" 2>/dev/null

  # git reset può azzerare i permessi: ripristina gli eseguibili
  chmod +x "$APP_DIR"/*.sh 2>/dev/null

  # Reinstalla le dipendenze della versione ripristinata
  npm install --no-audit --no-fund >/dev/null 2>&1

  restart_service
  if health_ok; then
    log "✅ Rollback riuscito. Sistema ripristinato alla versione precedente."
    return 0
  else
    err "Il rollback è stato applicato ma il server non risponde. Intervento manuale necessario."
    return 1
  fi
}

# ─── Riavvio servizio ─────────────────────────────────────────
restart_service() {
  if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE}"; then
    log "Riavvio del servizio ${SERVICE}..."
    sudo systemctl restart "$SERVICE" 2>/dev/null || systemctl --user restart "$SERVICE" 2>/dev/null
  else
    log "Servizio ${SERVICE} non trovato: riavvia il server manualmente."
  fi
}

# ─── Aggiornamento completo ───────────────────────────────────
do_update() {
  require_git_repo
  local force="$1"

  local lv rv
  lv="$(local_version)"
  rv="$(remote_version)"
  if [ -z "$rv" ]; then
    err "Impossibile contattare GitHub. Aggiornamento annullato."
    exit 1
  fi

  if [ "$force" != "--force" ] && ! version_gt "$rv" "$lv"; then
    log "Già aggiornato (v${lv}). Nessuna azione."
    echo "UP_TO_DATE ${lv}"
    exit 0
  fi

  log "═══ Aggiornamento ${lv} → ${rv} ═══"

  # 1. BACKUP prima di tutto
  create_backup
  local backup
  backup="$(cat "$BACKUP_DIR/LAST_BACKUP")"

  # 2. Scarica la nuova versione
  log "Download da GitHub (git pull)..."
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  if ! git pull --ff-only origin "$branch" >/tmp/church-pull.log 2>&1; then
    err "git pull fallito. Contenuto:"
    cat /tmp/church-pull.log >&2
    err "Nessuna modifica applicata (il backup è intatto)."
    # Prova a ripristinare lo stato pulito
    git merge --abort >/dev/null 2>&1
    exit 1
  fi

  # 3. Dipendenze
  log "Installazione dipendenze (npm install)..."
  # git pull può azzerare i permessi degli script: ripristinali
  chmod +x "$APP_DIR"/*.sh 2>/dev/null
  if ! npm install --no-audit --no-fund >/tmp/church-npm.log 2>&1; then
    err "npm install fallito → ROLLBACK"
    do_rollback "$backup"
    exit 1
  fi

  # 4. Riavvio + health check
  restart_service
  if health_ok; then
    log "✅ Aggiornamento completato: ora alla versione $(local_version)"
    echo "UPDATED $(local_version)"
    exit 0
  else
    err "Il server non risponde dopo l'aggiornamento → ROLLBACK automatico"
    do_rollback "$backup"
    echo "ROLLED_BACK"
    exit 1
  fi
}

# ─── Elenco backup ────────────────────────────────────────────
list_backups() {
  if [ ! -d "$BACKUP_DIR" ]; then
    echo "Nessun backup presente."
    return 0
  fi
  echo "Backup disponibili (dal più recente):"
  ls -1dt "$BACKUP_DIR"/backup-* 2>/dev/null | while read -r b; do
    echo "  $(basename "$b")"
  done
}

# ─── Dispatch ─────────────────────────────────────────────────
case "$1" in
  --check)        do_check ;;
  --rollback)     do_rollback "$2" ;;
  --list-backups) list_backups ;;
  --force)        do_update --force ;;
  *)              do_update ;;
esac
