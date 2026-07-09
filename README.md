# 123Solar + meterN — Docker (multi-container)

Immagine/orchestrazione Docker per eseguire [123Solar](https://123solar.org/) e
[meterN](https://www.metern.net/) in un'architettura **multi-container** basata
su Docker Compose e immagini ufficiali `nginx` / `php:fpm`.

> ⚠️ **Work in progress (v2).** Questa è la nuova architettura multi-container.
> La versione precedente (immagine unica a 3 layer con runit/syslog-ng) è
> archiviata sul branch [`legacy/v1`](../../tree/legacy/v1) (tag `v1-final`).

---

## Quickstart

```sh
cp .env.example .env      # adatta porte, timezone, device seriale
docker compose up -d
```

Poi apri `http://localhost:8080` (o la porta impostata in `HTTP_PORT`).

## Variabili d'ambiente

| Variabile | Default | Descrizione |
|---|---|---|
| `HTTP_PORT` | `8080` | Porta HTTP esposta dal container web (nginx) |
| `TZ` | `Europe/Rome` | Timezone del container |
| `SERIAL_DEVICE` | `/dev/ttyUSB0` | Device seriale RS485 passato al container php |
| `AUTO_UPDATE` | `false` | Aggiorna le app al boot se `true` |
| `SOLAR123_VERSION` | `latest` | Versione pinnata di 123Solar |
| `METERN_VERSION` | `latest` | Versione pinnata di meterN |

## Volumi

- **codice app** — condiviso tra `web` (nginx) e `php` (montato su `/var/www`)
- **config/data 123Solar** — configurazione e database RRD
- **config/data meterN** — configurazione e database RRD

## Immagini

Pubblicate multi-arch su:

- Docker Hub: `edofede/123solar-metern`
- GHCR: `ghcr.io/edofede/123solar-metern`

## Documentazione

- [Analisi del progetto](docs/ANALISI-PROGETTO.md)
- [Guida implementativa](docs/GUIDA-IMPLEMENTAZIONE.md)

## Licenza

Vedi [LICENSE](LICENSE).
