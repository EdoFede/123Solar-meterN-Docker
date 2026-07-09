# syntax=docker/dockerfile:1

# ==========================================================================
#  123Solar + meterN — custom php-fpm image (the ONLY image we build)
#
#  Multi-stage:
#    builder  — compiles the serial C tools (libmodbus, sdm120c, aurora)
#    runtime  — php:<ver>-fpm-alpine + rrdtool + the compiled tools
#
#  nginx stays the official image (no custom build); the app code is fetched
#  at first boot into a shared volume by /usr/local/bin/install-apps.sh.
# ==========================================================================

# --------------------------------------------------------------------------
# Stage 1 — build the C tools
# --------------------------------------------------------------------------
FROM alpine:3.20 AS builder

# Pin the upstream sources so builds are reproducible.
ARG LIBMODBUS_VERSION=v3.2.0
ARG AURORA_VERSION=1.9.4

RUN apk add --no-cache \
        linux-headers \
        ca-certificates \
        make \
        file \
        automake \
        autoconf \
        pkgconf \
        libtool \
        gcc \
        g++ \
        git \
        wget

# libmodbus (shared library used by sdm120c)
#
# 3.2.0 adds an optional termios2 code path (TCGETS2/TCSETS2) for *arbitrary*
# custom baud rates, gated by the configure check HAVE_STRUCT_TERMIOS2. On
# Alpine/musl that path does not build portably: the kernel header that carries
# `struct termios2` (<asm/termbits.h>) also redefines `struct termios`, clashing
# with musl's own <termios.h> ("redefinition of struct termios"), and the exact
# breakage varies by architecture and musl version.
#
# We don't need custom baud rates — sdm120c/aurora use standard rates (9600,
# etc.) served fine by the POSIX termios path. So we force the termios2 check
# OFF (ac_cv_type_struct_termios2=no); libmodbus then uses plain <termios.h>
# and builds cleanly and identically on every target arch (amd64, arm64,
# arm/v7, arm/v6, 386, ppc64le). No source patching required.
RUN git clone --depth 1 -b "${LIBMODBUS_VERSION}" https://github.com/stephane/libmodbus /build/libmodbus && \
    cd /build/libmodbus && \
    ./autogen.sh && \
    ac_cv_type_struct_termios2=no ./configure --prefix=/usr && \
    make && \
    make install

# SDM120C — reads SDM120 Modbus energy meters
#
# SDM120C guards the modbus timeout API with a buggy version check:
#   #if MAJOR >= 3 && MINOR >= 1 && MICRO >= 2
# which compares each component independently. For libmodbus 3.2.0 the MICRO is
# 0, so the check is false and SDM120C picks the OLD (struct timeval*) timeout
# API — but 3.2.0 keeps the (ctx, sec, usec) signature, so the build fails with
# "too few arguments". We replace that guard with the proper combined
# LIBMODBUS_VERSION_CHECK, which is correct for both 3.1.x and 3.2.x.
RUN git clone --depth 1 https://github.com/gianfrdp/SDM120C /build/SDM120C && \
    sed -i 's|LIBMODBUS_VERSION_MAJOR >= 3 && LIBMODBUS_VERSION_MINOR >= 1 && LIBMODBUS_VERSION_MICRO >= 2|LIBMODBUS_VERSION_CHECK(3, 1, 2)|g' /build/SDM120C/sdm120c.c && \
    make -s -C /build/SDM120C clean && \
    make -s -C /build/SDM120C

# aurora — Aurora / Power-One inverter interface
RUN wget -q http://www.curtronics.com/Solar/ftp/aurora-${AURORA_VERSION}.tar.gz -O /build/aurora.tar.gz && \
    mkdir -p /build/aurora && \
    tar -xzf /build/aurora.tar.gz -C /build/aurora --strip-components=1 && \
    ln -sf /usr/include/linux/can/error.h /usr/include/error.h && \
    sed -i "s/#ARCH = native/ARCH = NONE/" /build/aurora/Makefile && \
    make -s -C /build/aurora clean && \
    make -s -C /build/aurora check && \
    make -s -C /build/aurora

# --------------------------------------------------------------------------
# Stage 2 — runtime image
# --------------------------------------------------------------------------
FROM php:8.3-fpm-alpine

LABEL org.opencontainers.image.title="123solar-metern" \
      org.opencontainers.image.description="php-fpm image with serial tools (sdm120c, aurora, rrdtool) for 123Solar and meterN" \
      org.opencontainers.image.source="https://github.com/EdoFede/123Solar-meterN" \
      org.opencontainers.image.licenses="GPL-3.0"

# Runtime packages:
#   bash    — comapps and entrypoint scripts are bash
#   curl    — polling bootstrap + GitHub release download
#   rrdtool — RRD databases / graphs used by both apps
#   tzdata  — TZ env support
#   tar/gzip/openssl — install-apps.sh (download/unpack) + htpasswd generation
RUN apk add --no-cache \
        bash \
        curl \
        rrdtool \
        tzdata \
        tar \
        gzip \
        openssl \
        libstdc++

# Copy the compiled tools and the libmodbus shared library from the builder.
COPY --from=builder \
        /build/SDM120C/sdm120c \
        /build/aurora/aurora \
        /usr/local/bin/
COPY --from=builder \
        /usr/lib/libmodbus.so.5 \
        /usr/lib/libmodbus.so.5.1.0 \
        /usr/lib/

# Vendored helper scripts (app code fetcher + accessory "comapps") and the
# config files we seed into the apps on first boot.
COPY install-apps.sh /usr/local/bin/install-apps.sh
COPY comapps/        /opt/comapps/
COPY static/         /opt/static/
COPY seed/           /opt/seed/
COPY entrypoint.sh   /usr/local/bin/entrypoint.sh

# php-fpm runs as user "www-data" in the official image; give it serial access
# (dialout/uucp groups) and make the tool binaries + scripts executable.
# The comapps are exposed on PATH under their short names (pooler485, eflow, …)
# exactly like the legacy image did via /usr/local/bin symlinks.
RUN addgroup www-data dialout && \
    addgroup www-data uucp && \
    chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/install-apps.sh && \
    chmod 4711 /usr/local/bin/sdm120c /usr/local/bin/aurora && \
    sed -i 's/\r$//' /opt/comapps/* && \
    chmod 755 /opt/comapps/* && \
    ln -s /opt/comapps/cleanlog.sh          /usr/local/bin/cleanlog && \
    ln -s /opt/comapps/eflow.php            /usr/local/bin/eflow && \
    ln -s /opt/comapps/eflowlive.php        /usr/local/bin/eflowlive && \
    ln -s /opt/comapps/houseenergy.php      /usr/local/bin/houseenergy && \
    ln -s /opt/comapps/pool123s.php         /usr/local/bin/pool123s && \
    ln -s /opt/comapps/pooler485.sh         /usr/local/bin/pooler485 && \
    ln -s /opt/comapps/poolerconsumi.php    /usr/local/bin/poolerconsumi && \
    ln -s /opt/comapps/poolerproduzione.php /usr/local/bin/poolerproduzione && \
    ln -s /opt/comapps/pooltot.php          /usr/local/bin/pooltot && \
    ln -s /opt/comapps/reqLineValues.php    /usr/local/bin/reqLineValues && \
    ln -s /opt/comapps/reqsdm.php           /usr/local/bin/reqsdm && \
    ln -s /opt/comapps/testcom.php          /usr/local/bin/testcom

# php-fpm pool + php.ini overrides.
COPY fpm/www.conf     /usr/local/etc/php-fpm.d/zz-www.conf
COPY conf.d/zz-app.ini /usr/local/etc/php/conf.d/zz-app.ini

WORKDIR /var/www

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD php-fpm -t || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F"]
