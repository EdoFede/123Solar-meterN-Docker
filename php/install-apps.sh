#!/bin/bash
# ==========================================================================
#  install-apps.sh — populate the shared app volume (/var/www) with the
#  123Solar and meterN code, at the pinned versions, preserving config/data.
#
#  Called by entrypoint.sh at first boot (empty volume) and, when
#  AUTO_UPDATE=true, on every boot to pull newer releases.
#
#  Release lookup uses the plain github.com web endpoints (redirect + asset
#  listing), NOT api.github.com — the JSON API is rate limited to 60 req/hour
#  per IP and frequently returns HTTP 403, which used to break the check.
#
#  Env:
#    WWW_ROOT          target web root                 (default /var/www)
#    SOLAR123_VERSION  123Solar version or "latest"    (default latest)
#    METERN_VERSION    meterN version or "latest"      (default latest)
#    APP_UID / APP_GID ownership for the installed code (default www-data)
# ==========================================================================
set -euo pipefail

WWW_ROOT="${WWW_ROOT:-/var/www}"
SOLAR123_VERSION="${SOLAR123_VERSION:-latest}"
METERN_VERSION="${METERN_VERSION:-latest}"
APP_UID="${APP_UID:-www-data}"
APP_GID="${APP_GID:-www-data}"
STATIC_SRC="/opt/static"

log()  { echo -e "\033[0;32m[install-apps]\033[0m $*"; }
warn() { echo -e "\033[0;33m[install-apps]\033[0m $*" >&2; }
err()  { echo -e "\033[0;31m[install-apps]\033[0m $*" >&2; }

# Resolve the download URL + tag for a GitHub repo, honouring a pinned version.
# Prints:  "<tag> <tarball_url>"
#
# Uses the plain github.com web endpoints instead of api.github.com, which is
# rate limited to 60 requests/hour per IP for unauthenticated callers and often
# returns HTTP 403 on shared/CGNAT addresses. The web endpoints used here are
# not subject to that quota:
#   - GET /releases/latest         -> 302 redirect whose Location holds the tag
#   - GET /releases/expanded_assets/<tag> -> HTML listing the release downloads
# We prefer the author-attached asset (e.g. 123solar1.8.5.tar.gz) and fall back
# to the auto-generated source archive if no asset is attached.
resolve_release() {
    local repo="$1" want="$2" tag url

    if [ "$want" = "latest" ]; then
        # The "latest" pseudo-release 302-redirects to /releases/tag/<TAG>.
        local loc
        loc="$(curl -fsS -o /dev/null -w '%{redirect_url}' \
                    "https://github.com/${repo}/releases/latest")" || {
            err "Could not query latest release for ${repo}"; return 1; }
        tag="${loc##*/}"
    else
        tag="$want"
    fi
    if [ -z "$tag" ]; then
        err "Could not determine release tag for ${repo} (${want})"
        return 1
    fi

    # Scrape the release's asset list for the first attached .tar.gz/.tgz.
    local assets rel
    assets="$(curl -fsSL "https://github.com/${repo}/releases/expanded_assets/${tag}")" || assets=""
    rel="$(printf '%s' "$assets" \
            | grep -oE "/${repo}/releases/download/[^\"]+\.(tar\.gz|tgz)" \
            | head -n1)"

    if [ -n "$rel" ]; then
        url="https://github.com${rel}"
    else
        # No attached asset: use the auto-generated source archive for the tag.
        warn "[${repo}] no release asset for ${tag}; using source archive"
        url="https://github.com/${repo}/archive/refs/tags/${tag}.tar.gz"
    fi

    printf '%s %s\n' "$tag" "$url"
}

# Read the installed version from an app's scripts/version.php ($VERSION='x.y').
installed_version() {
    local vfile="$1"
    [ -f "$vfile" ] || { echo "0.0"; return; }
    grep VERSION "$vfile" | cut -d "'" -f2 | cut -d ' ' -f2 || echo "0.0"
}

# Install one app: download the release, unpack it, and copy it into place
# WITHOUT clobbering an existing config/ or data/ directory.
install_app() {
    local name="$1" repo="$2" want="$3" dest="$4"
    local tag url tmp instver src

    read -r tag url < <(resolve_release "$repo" "$want")

    instver="$(installed_version "${dest}/scripts/version.php")"
    log "[${name}] installed=${instver} target=${tag}"
    if [ "$tag" = "$instver" ]; then
        log "[${name}] already up to date"
        return 0
    fi

    tmp="$(mktemp -d)"
    log "[${name}] downloading ${tag}…"
    curl -fsSL "$url" -o "${tmp}/app.tar.gz"
    tar -xzf "${tmp}/app.tar.gz" -C "$tmp"
    rm -f "${tmp}/app.tar.gz"

    # The tarball unpacks into a single top-level directory.
    src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"

    mkdir -p "$dest"
    # Never overwrite user config/data once they exist.
    if [ -d "${dest}/config" ]; then rm -rf "${src}/config"; fi
    if [ -d "${dest}/data" ];   then rm -rf "${src}/data";   fi

    cp -Rf "${src}/." "$dest/"
    rm -rf "$tmp"
    log "[${name}] installed ${tag}"
}

log "web root: ${WWW_ROOT}"
mkdir -p "$WWW_ROOT"

install_app "123Solar" "jeanmarc77/123solar" "$SOLAR123_VERSION" "${WWW_ROOT}/123solar"
install_app "meterN"   "jeanmarc77/meterN"   "$METERN_VERSION"   "${WWW_ROOT}/metern"

# Landing page + favicons (served by nginx at "/").
cp -Rf "${STATIC_SRC}/." "${WWW_ROOT}/"

# Seed our patched config files where the app didn't already provide a user
# copy. meterN's config_daemon.php is patched to invoke pooler485 correctly.
SEED_SRC="/opt/seed"
if [ -d "${WWW_ROOT}/metern/config" ] && \
   [ ! -f "${WWW_ROOT}/metern/config/config_daemon.php" ]; then
    cp -f "${SEED_SRC}/metern/config_daemon.php" "${WWW_ROOT}/metern/config/config_daemon.php"
    log "[meterN] seeded config_daemon.php"
fi

# Seed a default admin login (admin/admin) only if none exists yet, so the
# basic-auth areas are reachable on first boot. Users should change it.
for app in 123solar metern; do
    htdir="${WWW_ROOT}/${app}/config"
    if [ -d "$htdir" ] && [ ! -f "${htdir}/.htpasswd" ]; then
        printf 'admin:%s\n' "$(openssl passwd -apr1 admin)" > "${htdir}/.htpasswd"
        warn "[${app}] seeded default admin/admin .htpasswd — CHANGE IT"
    fi
done

chown -R "${APP_UID}:${APP_GID}" "$WWW_ROOT" 2>/dev/null || true
log "done"
