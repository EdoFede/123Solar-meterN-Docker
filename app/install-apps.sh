#!/bin/sh
# app/install-apps.sh — fetch/pin the app code (SCAFFOLD)
#
# To be implemented. Expected behavior:
#   - download 123Solar and meterN at the chosen versions (SOLAR123_VERSION /
#     METERN_VERSION, GitHub releases) into the shared app-code volume
#   - preserve existing config/data across updates
#
# This is the SINGLE place where the choice is made:
#   one-shot populate at first boot  vs  baked into the image with pinned versions.
set -e

echo "install-apps: not yet implemented" >&2
