# php/Dockerfile — the ONLY custom image, multi-stage (SCAFFOLD)
#
# To be implemented. Expected structure:
#   Stage `builder`: compiles the C tools (libmodbus, sdm120c, aurora)
#   Runtime stage:   FROM php:8.x-fpm-alpine
#                    apk add rrdtool; copy binaries from the builder;
#                    dialout/uucp groups for serial access; entrypoint.sh
