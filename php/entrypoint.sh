#!/bin/sh
# php/entrypoint.sh — php container entrypoint (SCAFFOLD)
#
# To be implemented. Expected behavior:
#   - start the serial daemon:  pooler485 &
#   - (optional) trigger the polling bootstrap
#   - (optional) auto-update the apps if AUTO_UPDATE=true (see app/install-apps.sh)
#   - finally:  exec php-fpm
set -e

echo "entrypoint: not yet implemented" >&2
exec "$@"
