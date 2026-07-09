# Guida allo sviluppo, alle modifiche e alle release

Documento tecnico interno per il repository
[`EdoFede/123Solar-meterN-Docker`](https://github.com/EdoFede/123Solar-meterN-Docker).
Descrive come è fatto il progetto, come apportare modifiche, come testarle in
locale e come pubblicare una nuova release multi-arch su Docker Hub e GHCR.

---

## 1. Panoramica dell'architettura

Il progetto (v2) è **multi-container**, orchestrato da `docker-compose`, e riusa
immagini ufficiali dove possibile. Sostituisce la vecchia catena di 3 immagini
con runit/syslog-ng (archiviata sul branch `legacy/v1`, tag `v1-final`).

| Servizio | Immagine | Custom? |
|---|---|---|
| `web` | `nginx:alpine` (ufficiale) | No — solo `nginx/default.conf` montato |
| `php` | build locale di `./php` | **Sì — unica immagine che costruiamo** |

Il container `php` è l'unica immagine custom: `php:8.3-fpm-alpine` + `rrdtool` +
i tool seriali C (`libmodbus`, `sdm120c`, `aurora`) + i *comapps* vendorizzati.

Il codice delle app (123Solar / meterN) **non è nell'immagine**: viene scaricato
al primo avvio nel volume condiviso `app-code` da `php/install-apps.sh`.

### Struttura del repository

```
.
├── docker-compose.yml           # orchestrazione web + php
├── .env.example                 # variabili (copiare in .env)
├── nginx/
│   └── default.conf             # server block (montato in nginx ufficiale)
├── php/                         # === contesto di build dell'unica immagine ===
│   ├── Dockerfile               # multi-stage: builder (tool C) + runtime
│   ├── entrypoint.sh            # install app + bootstrap polling + exec php-fpm
│   ├── install-apps.sh          # scarica 123Solar/meterN da GitHub (no API)
│   ├── conf.d/zz-app.ini        # override php.ini
│   ├── fpm/www.conf             # pool php-fpm (listen :9000, log→stderr)
│   ├── comapps/                 # script accessori vendorizzati (pooler485, …)
│   ├── seed/metern/             # config_daemon.php patchato (avvio pooler485)
│   └── static/                  # landing page + favicon
├── docs/
│   └── DEVELOPMENT.md           # questo documento
└── .github/workflows/
    ├── ci.yml                   # test amd64 su PR e push (no publish)
    └── release.yml             # build 6-arch + publish sui tag vX.Y.Z
```

### Versioni pinnate (dove si cambiano)

| Cosa | Dove | Valore attuale |
|---|---|---|
| PHP | `php/Dockerfile` — `FROM php:…-fpm-alpine` | `8.3` |
| libmodbus | `php/Dockerfile` — `ARG LIBMODBUS_VERSION` | `v3.2.0` |
| aurora | `php/Dockerfile` — `ARG AURORA_VERSION` | `1.9.4` |
| SDM120C | `php/Dockerfile` (clone HEAD, con patch) | HEAD |
| 123Solar / meterN | `.env` → `SOLAR123_VERSION` / `METERN_VERSION` | `latest` (runtime) |

> Nota: 123Solar e meterN non sono pinnati nell'immagine ma scaricati a runtime.
> Per fissarli, imposta le versioni in `.env` (es. `SOLAR123_VERSION=1.8.5`).

---

## 2. Setup dell'ambiente di sviluppo

Requisiti:

- **Docker** con **Buildx** (incluso in Docker Desktop / Docker Engine recente).
- Per i build multi-arch in locale: **QEMU** via
  `docker run --privileged --rm tonistiigi/binfmt --install all`
  (una tantum; le GitHub Actions lo fanno da sole con `setup-qemu-action`).

Clona e prepara il file di ambiente:

```sh
git clone git@github.com:EdoFede/123Solar-meterN-Docker.git
cd 123Solar-meterN-Docker
cp .env.example .env      # regola HTTP_PORT, TZ, SERIAL_DEVICE, versioni…
```

---

## 3. Ciclo di lavoro per una modifica

### 3.1 Branch

Lavora **sempre su un branch**, mai direttamente su `master`:

```sh
git switch -c fix/nome-descrittivo        # o feat/…, chore/…
```

### 3.2 Fai la modifica

Casi tipici e file toccati:

| Voglio… | Tocco… |
|---|---|
| Aggiornare PHP | `php/Dockerfile` (`FROM php:…`) |
| Aggiornare libmodbus/aurora | `php/Dockerfile` (`ARG …_VERSION`) |
| Cambiare routing / auth web | `nginx/default.conf` |
| Cambiare tuning php-fpm | `php/fpm/www.conf`, `php/conf.d/zz-app.ini` |
| Cambiare avvio / download app | `php/entrypoint.sh`, `php/install-apps.sh` |
| Aggiornare uno script comapp | `php/comapps/…` |
| Aggiungere una variabile d'ambiente | `.env.example` **e** `docker-compose.yml` (+ README) |

### 3.3 Build e test in locale (amd64)

Prima di committare, verifica che l'immagine costruisca e funzioni:

```sh
# build della sola immagine php (amd64)
docker build -t 123solar-metern:dev ./php

# smoke test: config php-fpm + tool seriali presenti e linkati
docker run --rm --entrypoint php-fpm 123solar-metern:dev -t
docker run --rm --entrypoint sh 123solar-metern:dev -c '
  sdm120c 2>&1 | grep -i "Compiled with libmodbus";
  ldd /usr/local/bin/sdm120c | grep modbus;
  command -v aurora rrdtool pooler485 reqLineValues;
  id www-data'          # deve contenere i gruppi dialout e uucp
```

### 3.4 Test end-to-end con compose

Su una macchina **senza** adattatore seriale, commenta la riga `devices:` del
servizio `php` in `docker-compose.yml` (oppure usa un override), poi:

```sh
docker compose up -d --build
docker compose logs -f php        # osserva install-apps + avvio php-fpm
curl -I http://localhost:8080/    # 200 sulla landing page
docker compose down -v            # -v azzera il volume app-code (codice app)
```

> **Nota bind-mount:** `config/` e `data/` sono bind-mount host (path relativi
> al compose), quindi `down -v` **non** li cancella — restano sul filesystem.
> Per un'installazione davvero pulita, svuota anche quelle cartelle a mano:
> `rm -rf config/*/* data/*/*` (mantieni i `.gitkeep`).

Verifica basic-auth (dopo il primo avvio, credenziali di default `admin`/`admin`):

```sh
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/metern/admin/   # 401
curl -s -u admin:admin -o /dev/null -w "%{http_code}\n" http://localhost:8080/metern/admin/index.html
```

### 3.5 (Opzionale ma consigliato) verifica multi-arch localmente

Le architetture "esotiche" (soprattutto `ppc64le` e `arm/v6`) hanno rotto build
in passato per differenze negli header musl. Se hai toccato il **Dockerfile** o
la compilazione dei tool C, prova almeno l'arch storicamente più fragile:

```sh
docker build --platform linux/ppc64le -t 123solar-metern:ppc ./php
```

> Il build emulato via QEMU è lento (diversi minuti): è normale.

---

## 4. Commit e push

### 4.1 Commit

Messaggi in stile [Conventional Commits](https://www.conventionalcommits.org/)
(coerente con la history: `feat:`, `fix:`, `chore:`, `ci:`, `docs:`…):

```sh
git add -A
git commit -m "fix: descrizione sintetica della modifica"
```

### 4.2 Push del branch e Pull Request

```sh
git push -u origin fix/nome-descrittivo
```

Apri una **Pull Request** verso `master`. All'apertura/aggiornamento della PR
parte il workflow **`ci.yml`**, che:

- builda l'immagine `php` su `linux/amd64` (senza pubblicare);
- esegue lo smoke test (config php-fpm, presenza/linking dei tool seriali,
  gruppi seriali dell'utente `www-data`).

**Non fare merge se la CI è rossa.** Una volta verde, fai merge in `master`.

> Anche un push diretto su `master` fa girare `ci.yml` (test amd64), ma la
> pratica corretta è passare da una PR.

---

## 5. Rilascio di una nuova versione (release)

**Il build multi-arch completo e la pubblicazione su Docker Hub/GHCR avvengono
SOLO quando si pusha un tag Git `vX.Y.Z`.** I push su `master` non pubblicano
nulla (fanno solo il test amd64). Questo replica il vecchio flusso Travis
("nuovo tag → build + `latest`").

### 5.1 Prerequisiti (una tantum)

Configurati nel repo GitHub → **Settings → Secrets and variables → Actions**:

| Secret | Valore | Note |
|---|---|---|
| `DOCKERHUB_USERNAME` | `edofede` | utente Docker Hub |
| `DOCKERHUB_TOKEN` | *access token* | Docker Hub → Account Settings → Personal access tokens, permesso **Read & Write**. NON la password. |

GHCR usa il `GITHUB_TOKEN` automatico: nessun secret da creare. Assicurati solo
che il package GHCR sia collegato al repo e abbia visibilità pubblica se serve.

### 5.2 Procedura di release

1. Assicurati che `master` sia verde in CI e aggiornato in locale:

   ```sh
   git switch master && git pull
   ```

2. Crea un **tag annotato** con versione [SemVer](https://semver.org/),
   prefissata da `v`:

   ```sh
   git tag -a v1.0.0 -m "Release 1.0.0"
   git push origin v1.0.0
   ```

3. Il workflow **`release.yml`** parte automaticamente e:
   - builda l'immagine `php` su **6 architetture**
     (`amd64, arm64, arm/v7, arm/v6, 386, ppc64le`);
   - pubblica su **Docker Hub** (`edofede/123solar-metern`) **e GHCR**
     (`ghcr.io/edofede/123solar-metern`);
   - crea i tag Docker derivati dal tag Git (vedi tabella sotto).

4. (Consigliato) crea la **Release** su GitHub dalla UI a partire dal tag, con
   changelog. Non è necessaria per il build, ma tiene ordinata la cronologia.

### 5.3 Mappatura tag Git → tag Docker

Gestita da `docker/metadata-action` (`type=semver` + `flavor: latest=auto`):

| Tag Git pushato | Tag Docker pubblicati |
|---|---|
| `v1.0.0` | `1.0.0`, `1.0`, `1`, **`latest`** |
| `v1.2.3` | `1.2.3`, `1.2`, `1`, **`latest`** |
| `v2.0.0-rc1` | `2.0.0-rc1` — **`latest` NON viene toccato** |

- La `v` iniziale viene rimossa automaticamente.
- `latest` viene aggiornato **solo per release stabili** (non pre-release),
  grazie a `latest=auto`. Così una `-rc`/`-beta` non sovrascrive `latest`.

### 5.4 Verifica post-release

```sh
docker buildx imagetools inspect edofede/123solar-metern:latest
docker buildx imagetools inspect edofede/123solar-metern:1.0.0
```

Controlla che la **manifest list** elenchi tutte le 6 piattaforme attese.

### 5.5 Correggere una release sbagliata

Un tag già pushato **non va riscritto**: pubblica invece una patch release.

```sh
# scenario: v1.0.0 aveva un bug → rilascia v1.0.1
git switch -c fix/... ; ...commit... ; PR ; merge in master
git switch master && git pull
git tag -a v1.0.1 -m "Release 1.0.1" && git push origin v1.0.1
```

`latest` punterà automaticamente alla nuova versione stabile più alta.

> Evita di eliminare/riusare un tag già pubblicato: chi ha già pullato quel tag
> otterrebbe contenuti diversi. In caso estremo, cancella tag Git **e** tag
> Docker e comunica il "richiamo", ma è una procedura da evitare.

---

## 6. Riferimenti rapidi

```sh
# --- sviluppo ---
docker build -t 123solar-metern:dev ./php          # build amd64
docker compose up -d --build                        # stack completo
docker compose logs -f php                           # log del container php
docker compose down -v                               # stop + reset volume app-code
                                                     # (config/ e data/ bind-mount restano sull'host)

# --- multi-arch locale ---
docker run --privileged --rm tonistiigi/binfmt --install all   # QEMU (una tantum)
docker build --platform linux/ppc64le -t x ./php    # prova arch fragile

# --- release ---
git tag -a vX.Y.Z -m "Release X.Y.Z" && git push origin vX.Y.Z
docker buildx imagetools inspect edofede/123solar-metern:latest
```

### Workflow CI/CD in sintesi

| Evento | Workflow | Cosa fa | Pubblica? |
|---|---|---|---|
| PR verso `master` | `ci.yml` | build amd64 + smoke test | No |
| push su `master` | `ci.yml` | build amd64 + smoke test | No |
| push tag `vX.Y.Z` | `release.yml` | build 6-arch + tag `latest` | **Sì** (Docker Hub + GHCR) |
