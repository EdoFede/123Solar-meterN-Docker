#!/bin/sh
# php/entrypoint.sh — entrypoint del container php (SCAFFOLD)
#
# Da implementare. Comportamento previsto:
#   - avvio del daemon seriale:  pooler485 &
#   - (opz.) trigger bootstrap del polling
#   - (opz.) auto-update delle app se AUTO_UPDATE=true (vedi app/install-apps.sh)
#   - infine:  exec php-fpm
#
# Vedi docs/GUIDA-IMPLEMENTAZIONE.md §3.2.
set -e

echo "entrypoint: not yet implemented" >&2
exec "$@"
