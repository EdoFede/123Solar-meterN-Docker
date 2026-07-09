# 123Solar + meterN — Docker (multi-container)

Docker image/orchestration to run [123Solar](https://123solar.org/) and
[meterN](https://www.metern.net/) in a **multi-container** architecture based on
Docker Compose and the official `nginx` / `php:fpm` images.

The previous version (single 3-layer image with runit/syslog-ng) is archived
on the [`legacy/v1`](../../tree/legacy/v1) branch (tag `v1-final`).

## Architecture

- **`web`** — official `nginx:alpine`, no custom build. Serves static files and
  reverse-proxies PHP to the `php` container over FastCGI (`php:9000`).
- **`php`** — the only custom image (`php:8.3-fpm-alpine` + `rrdtool` + the
  serial C tools `sdm120c`/`aurora`/`libmodbus` + the accessory *comapps*).
  Runs the apps and has access to the RS485 serial device.

On **first boot** the `php` container downloads 123Solar and meterN (at the
pinned versions) into the shared `app-code` volume, seeds a default
`admin`/`admin` login for the `/admin` areas, then starts php-fpm and the
polling bootstrap. The serial daemon `pooler485` is started on demand by
meterN's *config_daemon* once you configure it in the meterN admin UI.

> ⚠️ Change the default `admin`/`admin` credentials after first login.

---

## Quickstart

```sh
cp .env.example .env      # adjust ports, timezone, serial device
docker compose up -d
```

Then open `http://localhost:8080` (or the port set in `HTTP_PORT`).

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `HTTP_PORT` | `8080` | HTTP port exposed by the web container (nginx) |
| `TZ` | `Europe/Rome` | Container timezone |
| `SERIAL_DEVICE` | `/dev/ttyUSB0` | RS485 serial device passed to the php container |
| `AUTO_UPDATE` | `false` | Re-check the apps' releases on every boot when `true` |
| `POLL_BOOTSTRAP` | `true` | Run the `boot123s.php`/`bootmn.php` polling at startup |
| `SOLAR123_VERSION` | `latest` | Pinned 123Solar version (GitHub release tag) |
| `METERN_VERSION` | `latest` | Pinned meterN version (GitHub release tag) |

> **No serial adapter?** Comment out the `devices:` line under the `php`
> service in `docker-compose.yml` so the stack starts without `/dev/ttyUSB0`.

## Volumes

- **app code** — Docker-managed volume (`app-code`), shared between `web`
  (nginx) and `php` (mounted at `/var/www`), populated at first boot.
- **config/data** — **host bind-mounts** relative to the compose file, so the
  apps' configuration and RRD databases live on the host and survive
  `docker compose down -v`:

  ```
  ./config/123Solar  ->  /var/www/123solar/config
  ./config/meterN    ->  /var/www/metern/config
  ./data/123Solar    ->  /var/www/123solar/data
  ./data/meterN      ->  /var/www/metern/data
  ```

## Images

Published multi-arch on:

- Docker Hub: `edofede/123solar-metern`
- GHCR: `ghcr.io/edofede/123solar-metern`

## License

See [LICENSE](LICENSE).
