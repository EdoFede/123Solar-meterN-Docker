#!/bin/sh
# app/install-apps.sh — recupero/pinning del codice delle app (SCAFFOLD)
#
# Da implementare. Comportamento previsto:
#   - scarica 123Solar e meterN nelle versioni scelte (SOLAR123_VERSION /
#     METERN_VERSION, release GitHub) nel volume condiviso del codice
#   - preserva config/data esistenti tra un update e l'altro
#
# È il punto UNICO dove si concretizza la scelta:
#   populate one-shot al primo avvio  vs  incluso nell'immagine con versioni pinnate.
# Vedi docs/GUIDA-IMPLEMENTAZIONE.md §3.1/§3.2 e docs/ANALISI-PROGETTO.md §3.4.
set -e

echo "install-apps: not yet implemented" >&2
