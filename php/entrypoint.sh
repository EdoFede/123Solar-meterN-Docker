#!/bin/bash
# ==========================================================================
#  entrypoint.sh — php container entrypoint
#
#  1. install / update the app code into the shared /var/www volume
#  2. kick off the polling bootstrap of both apps (against the web service)
#  3. exec php-fpm as PID 1
#
#  The serial daemon (pooler485) is NOT started here: meterN starts/stops it
#  on demand from its config_daemon.php (exec "pooler485 …") once configured.
#
#  Env (see .env.example):
#    WWW_ROOT      web root shared with nginx        (default /var/www)
#    AUTO_UPDATE   re-check releases every boot        (default false)
#    POLL_BOOTSTRAP  run the boot123s/bootmn polling  (default true)
#    WEB_HOST      hostname of the nginx service       (default web)
#    WEB_PORT      internal http port of nginx         (default 80)
# ==========================================================================
set -euo pipefail

WWW_ROOT="${WWW_ROOT:-/var/www}"
AUTO_UPDATE="${AUTO_UPDATE:-false}"
POLL_BOOTSTRAP="${POLL_BOOTSTRAP:-true}"
WEB_HOST="${WEB_HOST:-web}"
WEB_PORT="${WEB_PORT:-80}"

log() { echo -e "\033[0;36m[entrypoint]\033[0m $*"; }

# --- 1. app code -----------------------------------------------------------
# Install when the volume is empty (first boot) or when AUTO_UPDATE is on.
if [ ! -f "${WWW_ROOT}/123solar/scripts/version.php" ] || \
   [ ! -f "${WWW_ROOT}/metern/scripts/version.php" ] || \
   [ "$AUTO_UPDATE" = "true" ]; then
    log "populating app code (AUTO_UPDATE=${AUTO_UPDATE})"
    if ! /usr/local/bin/install-apps.sh; then
        log "WARNING: install-apps.sh failed; continuing with whatever is on the volume"
    fi
else
    log "app code present; skipping install (set AUTO_UPDATE=true to refresh)"
fi

# --- 2. polling bootstrap --------------------------------------------------
# Legacy behaviour: hit each app's boot script so it starts its polling loop.
# nginx now lives in a separate container, so we call it by service name once
# it is reachable.
if [ "$POLL_BOOTSTRAP" = "true" ]; then
    (
        base="http://${WEB_HOST}:${WEB_PORT}"
        # Wait for nginx (up to ~30s) before bootstrapping.
        for _ in $(seq 1 30); do
            if curl -fsS -o /dev/null "${base}/index.html" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        log "bootstrapping polling via ${base}"
        curl -fsS -o /dev/null "${base}/123solar/scripts/boot123s.php" || \
            log "WARNING: 123solar bootstrap failed"
        curl -fsS -o /dev/null "${base}/metern/scripts/bootmn.php" || \
            log "WARNING: metern bootstrap failed"
    ) &
fi

# --- 3. hand off to php-fpm ------------------------------------------------
log "starting: $*"
exec "$@"
