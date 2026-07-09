# 123Solar + meterN — Docker (multi-container)

Docker image/orchestration to run [123Solar](https://123solar.org/) and
[meterN](https://www.metern.net/) in a **multi-container** architecture based on
Docker Compose and the official `nginx` / `php:fpm` images.

> ⚠️ **Work in progress (v2).** This is the new multi-container architecture.
> The previous version (single 3-layer image with runit/syslog-ng) is archived
> on the [`legacy/v1`](../../tree/legacy/v1) branch (tag `v1-final`).

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
| `AUTO_UPDATE` | `false` | Update the apps at boot when `true` |
| `SOLAR123_VERSION` | `latest` | Pinned 123Solar version |
| `METERN_VERSION` | `latest` | Pinned meterN version |

## Volumes

- **app code** — shared between `web` (nginx) and `php` (mounted at `/var/www`)
- **123Solar config/data** — configuration and RRD database
- **meterN config/data** — configuration and RRD database

## Images

Published multi-arch on:

- Docker Hub: `edofede/123solar-metern`
- GHCR: `ghcr.io/edofede/123solar-metern`

## License

See [LICENSE](LICENSE).
