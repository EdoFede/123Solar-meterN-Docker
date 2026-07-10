#!/bin/sh
# healthcheck.sh — container HEALTHCHECK for the php-fpm service.
#
# Pings php-fpm over FastCGI (the same socket nginx uses, 127.0.0.1:9000) via
# the pool's ping.path. A healthy master accepting connections and a worker
# able to answer returns the configured ping.response ("pong"). This verifies
# the real request path, not just that the config parses (`php-fpm -t`).
set -e

REPLY="$(
    SCRIPT_NAME=/ping \
    SCRIPT_FILENAME=/ping \
    REQUEST_METHOD=GET \
    cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null
)"

# cgi-fcgi prints CGI headers followed by the body; match the ping response.
echo "$REPLY" | grep -q pong
