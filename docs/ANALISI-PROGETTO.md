# Analisi del progetto 123Solar + meterN su Docker

Documento di analisi del vecchio progetto di containerizzazione dei due
applicativi PHP [123solar](https://github.com/jeanmarc77/123solar) e
[meterN](https://github.com/jeanmarc77/meterN), con proposta di
modernizzazione.

---

## 1. Riepilogo della struttura del progetto originale

Il progetto è organizzato come **catena di tre immagini Docker**, ognuna nel
proprio repository, dove ciascuna è la base della successiva:

```
alpine:<ver>
   └── BaseImage-Docker            (edofede/baseimage)
          └── nginx-php-fpm-Docker (edofede/nginx-php-fpm)
                 └── 123Solar-meterN-Docker (edofede/123solar-metern)
```

Ogni repo ha la stessa impalcatura: `Dockerfile`, cartella `imageFiles/`
(copiata integralmente nella root del filesystem dell'immagine), `Makefile`,
`scripts/` di build/test/run, `hooks/` per Docker Hub, `.travis.yml`.

### 1.1 BaseImage-Docker — il layer di sistema

Immagine Alpine con un mini "init system" costruito attorno a **runit** e a
**syslog-ng**. È qui che vive la logica più delicata da preservare.

- **`entrypoint.sh`**: se riceve argomenti li esegue (`exec "$@"`), altrimenti
  lancia `/sbin/runit-init` (PID 1).
- **`/etc/runit/1`** (stage 1, one-shot): esegue `run-parts /etc/runit/1.d`
  (setup iniziale).
- **`/etc/runit/2`** (stage 2, servizi): `runsvdir -P /etc/service` — è il
  supervisore che tiene vivi i servizi.
- **`/etc/runit/3`** (stage 3, shutdown): ferma con grazia i servizi
  (`sv force-stop`, `sv exit`) e fa reaping degli zombie.
- **`STOPSIGNAL SIGCONT`**: segnale usato da runit per avviare lo shutdown
  ordinato.
- **Servizi gestiti** (cartelle `/etc/sv/*` linkate in `/etc/service/`):
  - **`syslog-ng`**: gira in foreground; raccoglie i log da `/dev/log`
    (socket unix-dgram) e dal source `internal()` e li **ridireziona su
    STDOUT/STDERR del container** (destinazioni `pipe("/dev/stdout")` e
    `pipe("/dev/stderr")`), filtrando per livello. Questo è il meccanismo che
    permette a `docker logs` di funzionare.
  - **`postScripts-handler`**: servizio "dummy" che attende l'avvio di tutti i
    servizi, poi esegue `run-parts /etc/runit/2.d` (script "post-boot") e
    resta vivo con `while true; sleep 1d`. È il trucco per lanciare azioni
    **dopo** che i servizi sono su, senza far fallire runit.
- Configurazione syslog modulare: `/etc/syslog-ng/conf.d/*.conf` include file
  aggiuntivi (es. `z_systemLogs.conf` inoltra i messaggi da `/dev/log`).

### 1.2 nginx-php-fpm-Docker — il layer web

Aggiunge **nginx** + **php-fpm (PHP 8.1)** più i moduli PHP necessari.

- PHP-FPM riconfigurato: `daemonize = no`, `error_log = syslog`, socket unix
  `/run/php/php8.1-fpm.sock`, utente `nginx` / gruppo `www-data`.
- nginx caricato con moduli dinamici (incluso `http-dav-ext`), site di default
  in `sites-available/default`.
- Due nuovi servizi runit (`/etc/sv/php-fpm`, `/etc/sv/nginx`) con **ordinamento
  di avvio fatto a mano tramite polling**: php-fpm aspetta syslog-ng, nginx
  aspetta php-fpm (loop `sv check ... | grep run`). runit di per sé non ha
  dipendenze tra servizi, quindi l'ordine è emulato così.

### 1.3 123Solar-meterN-Docker — il layer applicativo

Immagine finale, **multi-stage**:

- **Stage `builder`** (Alpine + toolchain C): compila da sorgente tre tool
  esterni usati per parlare con l'hardware:
  - **libmodbus** v3.1.7 (libreria Modbus)
  - **SDM120C** (lettura contatori Modbus SDM120)
  - **aurora** 1.9.4 (interfaccia inverter Aurora/Power-One)
- **Stage finale**: copia i binari compilati + le `.so`, installa `rrdtool`
  (database RRD per i grafici), aggiunge l'utente `nginx` ai gruppi `dialout`
  e `uucp` (accesso alle seriali `/dev/ttyUSB*`), imposta i binari SUID
  (`chmod 4711`).
- **Auto-update all'avvio**: `update123solarAndMetern.sh` interroga la
  **GitHub Releases API**, confronta la versione installata (`version.php`)
  con l'ultima release e, se serve, scarica il tarball e lo scompatta —
  **preservando `config/` e `data/`**. Girava sia in fase di build (prima
  installazione) sia ad ogni boot via `/etc/runit/2.d/05_update...`.
- **`updateComapps.sh`**: scarica un pacchetto di script accessori ("comapps")
  da un URL di terze parti (`flanesi.it`).
- **`start_polling`** (post-script 2.d): fa partire il polling dei due
  applicativi con due chiamate `curl` ai loro endpoint di bootstrap.
- **`sdm120c.conf`**: filtro syslog-ng che scarta (`/dev/null`) i messaggi
  verbosi del programma `sdm120c`.
- **Volumi**: `config` e `data` di entrambe le app.
- Il container serve **entrambe le app da un unico nginx** (`/123solar` e
  `/metern`), con area `/admin` protetta da basic-auth (`.htpasswd`).
- **Daemon seriale**: `config_daemon.php` di meterN avvia/ferma `pooler485`
  che parla sulla seriale (`/dev/ttyUSB0`).

---

## 2. Analisi dei tool di build e alternative

### 2.1 Come funziona oggi (Travis CI)

Ogni repo ha un `.travis.yml` sostanzialmente identico che:

1. Installa Docker CE su Ubuntu bionic.
2. Registra **QEMU** (`multiarch/qemu-user-static`) per l'emulazione
   multi-arch e avvia un **registry locale** (`registry:2` su :5000).
3. `make build`: usa **`docker buildx`** per compilare l'immagine su **6
   architetture** (`amd64, arm/v6, arm/v7, arm64/v8, 386, ppc64le` — vedi
   `multiArchMatrix.sh`) e la pusha nel registry locale.
4. `make test_all`: fa partire un container per ogni arch (via QEMU) e verifica
   tre cose — che syslog-ng parta e che i messaggi arrivino a STDOUT e STDERR
   (`test.sh`).
5. In `deploy`: login su Docker Hub e `make build_push` verso `edofede/*`.
   Su push a `master` pubblica il tag della branch; su **git tag** pubblica
   anche `latest`.

La versione dell'immagine è derivata dal nome della branch/tag Git
(`DOCKER_TAG = branch senza la "v" iniziale`). Il concatenamento tra le tre
immagini avviene tramite l'ARG `BASEIMAGE_BRANCH`.

**Punti di forza dell'impianto attuale:**
- Multi-arch reale già con buildx.
- Test di fumo sull'immagine emulata prima del push.
- Metadati OCI/label-schema ben curati.

**Punti deboli:**
- **Travis CI**: dopo il cambio del modello di pricing (2020-2021) è di fatto
  inutilizzabile a costo zero per progetti hobbistici; molti repo hanno
  migrato. Il `.travis.yml` usa `dist: bionic` (EOL) e installa Docker a mano.
- **Gestione QEMU manuale** e download del binario statico da GitHub con
  fallback su versione hard-coded (`v6.0.0-2`): fragile e datato. Oggi
  `docker/setup-qemu-action` fa tutto.
- **Registry locale** per passare artefatti tra build e test: complessità che
  con buildx moderno (`--load`) non serve più.
- **Tre pipeline separate** da tenere sincronizzate, con trigger a cascata
  manuali quando la base cambia.
- Architetture come `arm/v6`, `386`, `ppc64le` probabilmente inutili per il
  target reale (NAS Synology, Raspberry Pi, mini-PC x86).

### 2.2 Alternative consigliate (obiettivo: multi-piattaforma)

**Scelta raccomandata: GitHub Actions + `docker/build-push-action` con Buildx.**

Motivi: gratuito per repo pubblici, integrazione nativa con GHCR
(GitHub Container Registry), ecosistema di action ufficiali Docker che
sostituiscono tutto lo scripting custom:

| Necessità attuale | Azione GitHub moderna |
|---|---|
| Setup QEMU manuale + download statico | `docker/setup-qemu-action` |
| `docker buildx create/inspect` in `build.sh` | `docker/setup-buildx-action` |
| Login Docker Hub in `before_deploy` | `docker/login-action` |
| Tag da nome branch (`sed 's/^v//'`) | `docker/metadata-action` (tag/semver/sha automatici) |
| `docker buildx build --platform ... --push` | `docker/build-push-action` con `platforms:` |
| Cache di build assente | `cache-from/to: type=gha` |

Con `docker/build-push-action` il **multi-arch è una sola riga**
(`platforms: linux/amd64,linux/arm64,linux/arm/v7`) e la manifest list viene
creata e pushata automaticamente — si può eliminare tutto
`multiArchMatrix.sh`, `build.sh`, `run.sh`, `travisDockerSetup.sh`.

Suggerisco di **restringere le architetture** a quelle realmente usate
(tipicamente `linux/amd64` + `linux/arm64`, eventualmente `linux/arm/v7` per
Raspberry Pi vecchi). Ogni arch aggiuntiva emulata via QEMU allunga molto i
tempi (la compilazione di libmodbus/aurora sotto QEMU è lenta).

**Altre opzioni valutate:**
- **GitLab CI/CD**: valido e con registry integrato; sensato solo se si sposta
  l'hosting su GitLab.
- **Drone CI / Woodpecker**: ottimi se si vuole self-hostare la CI, overhead
  di gestione non giustificato qui.
- **Build locale con `make` + buildx**: già possibile oggi; utile come
  fallback ma non come pipeline pubblica.

**Testing**: il `test.sh` attuale (smoke test su syslog/STDOUT) può restare
concettualmente, ma conviene riscriverlo come step della action che gira solo
su `linux/amd64` nativo (niente QEMU) con
[Goss](https://github.com/goss-org/goss)/[container-structure-test](https://github.com/GoogleContainerTools/container-structure-test)
oppure un semplice `docker run` + `healthcheck`. Testare tutte le 6 arch
emulate ad ogni push è costoso e poco utile.

**Firma/SBOM (bonus moderno)**: `build-push-action` può generare provenance e
SBOM; opzionale ma "gratis".

---

## 3. Proposta di modernizzazione (una sola immagine da mantenere)

Obiettivo: **un unico repository / un unico Dockerfile multi-stage**, senza la
catena di tre immagini, mantenendo funzionalità identiche. La chiave è che le
tre immagini oggi non offrono un vero riuso esterno: sono solo strati logici.
Diventano **stage** di un solo Dockerfile.

### 3.1 Struttura proposta del Dockerfile

```dockerfile
# --- Stage 1: build dei tool C (invariato concettualmente) ---
FROM alpine:3.20 AS builder
#   toolchain -> libmodbus, sdm120c, aurora

# --- Stage 2: immagine finale ---
FROM alpine:3.20
#   1) pacchetti sistema (bash, curl, tzdata, rrdtool...)
#   2) nginx + php-fpm + moduli PHP
#   3) COPY --from=builder dei binari e .so
#   4) COPY della config (ex "imageFiles/" unificati)
#   5) init/process supervisor
#   6) utenti/gruppi seriali, SUID, volumi
```

Un solo `Dockerfile`, un solo `imageFiles/`, un solo pipeline. Sparisce l'ARG
`BASEIMAGE_BRANCH` e il triplo push.

### 3.2 Il nodo critico: runit + syslog-ng

Questa è la parte da trattare con attenzione perché è ciò che oggi rende
funzionante `docker logs` e l'avvio ordinato dei servizi. Tre strade:

**Opzione A — Mantenere runit + syslog-ng (minimo cambiamento, rischio minimo).**
Si conserva l'attuale meccanismo (stage 1/2/3, `postScripts-handler`,
redirect syslog→STDOUT/STDERR). Funziona già e le funzionalità restano
identiche. Svantaggio: si porta dietro complessità (init custom, ordering via
polling). **Consigliata se la priorità è "non rompere nulla".**

**Opzione B — Sostituire runit con `s6-overlay` v3 (modernizzazione bilanciata).**
[s6-overlay](https://github.com/just-containers/s6-overlay) è oggi lo standard
de-facto per multi-processo in un container Alpine. Vantaggi rispetto a runit
custom:
- **Dipendenze tra servizi native** (`dependencies.d/`): elimina i loop di
  polling `sv check ... | grep run` in nginx/php-fpm/postScripts.
- **Oneshot** e **`s6-rc`** per gli script di boot (update, start_polling):
  sostituiscono `postScripts-handler` in modo pulito.
- **Reaping degli zombie e shutdown ordinato** già gestiti (via
  `S6_KILL_GRACETIME` ecc.): si può eliminare lo stage 3 fatto a mano.
- Gestisce lo STDOUT/STDERR e l'`init` come PID 1 in modo robusto.

**Opzione C — Niente supervisor: log diretti a STDOUT, un processo per
container.** L'approccio "docker-native" puro. Problema concreto: qui servono
davvero più processi cooperanti (php-fpm, nginx, il daemon seriale
`pooler485`, i cron/polling). Splittare in più container complica l'accesso
alla **stessa seriale** e ai volumi condivisi. **Sconsigliata** per questo
caso d'uso: perderebbe la semplicità del "container unico".

> **Raccomandazione: Opzione B (s6-overlay).** Mantiene il modello "un
> container, più servizi" richiesto, ma elimina l'init-system custom e i
> workaround di ordering. È il miglior compromesso tra modernità e parità
> funzionale.

### 3.3 Il syslog e i log

Oggi syslog-ng serve a due cose:
1. **Portare i log dei servizi su `docker logs`** (STDOUT/STDERR).
2. **Filtrare** il rumore (es. buttare via i messaggi di `sdm120c`).

Con s6-overlay, i servizi scrivono già su STDOUT/STDERR raccolti da s6 → il
punto (1) è coperto **senza syslog-ng**. Restano due dettagli da gestire:

- **php-fpm** oggi logga con `error_log = syslog`. Va cambiato in
  `error_log = /proc/self/fd/2` (STDERR) o `catch_workers_output = yes`.
- I programmi che usano `logger`/`/dev/log` (gli script bash, `sdm120c`)
  presuppongono un socket syslog. Se si vuole eliminare syslog-ng del tutto,
  bisogna **sostituire le chiamate `logger`** con `echo` verso STDERR, oppure
  mantenere un piccolo forwarder. Il filtro `sdm120c` (che silenzia il rumore)
  si può replicare a livello di come viene lanciato quel processo
  (redirect `>/dev/null`).

  Se questa migrazione risulta troppo invasiva, si può **tenere syslog-ng come
  singolo servizio s6** (solo per raccogliere `/dev/log` e inoltrarlo a
  STDOUT/STDERR con i filtri) — molto più semplice degli stage runit attuali.
  È una via di mezzo pragmatica.

### 3.4 L'auto-update all'avvio: da ripensare

Lo script che ad ogni boot scarica l'ultima release da GitHub è comodo ma ha
controindicazioni note (build/avvii non riproducibili, dipendenza da rete e
dalla GitHub API, possibili rotture silenziose se cambia il formato dei
release asset). Opzioni:

- **Consigliata**: "pinnare" le versioni di 123solar/meterN come **ARG nel
  Dockerfile** e installarle **in fase di build**. L'aggiornamento diventa:
  bump dell'ARG → nuova immagine → nuovo tag. Riproducibile e versionato.
  L'automazione dei bump si può fare con **Renovate/Dependabot** o una action
  schedulata che apre una PR quando esce una release upstream.
- **Se si vuole tenere l'update a runtime** (es. per non ricostruire): isolarlo
  in uno script oneshot s6 **opzionale, disattivabile via variabile
  d'ambiente** (es. `AUTO_UPDATE=false` di default), con logging chiaro e
  fallback sicuro se la rete non c'è. Mantiene il comportamento vecchio ma lo
  rende opt-in.

Nota: `updateComapps.sh` scarica da un URL di terze parti in HTTP con
`--no-check-certificate`. In fase di modernizzazione andrebbe **vendorizzato**
(committare i comapps nel repo) o quantomeno scaricato via HTTPS con verifica.

### 3.5 Altri ammodernamenti minori

- **Aggiornare PHP** (8.1 è a fine supporto) alla versione Alpine corrente e
  rinominare i riferimenti hard-coded al socket `php8.1-fpm.sock`.
- **HEALTHCHECK** nel Dockerfile (es. `curl -f localhost/` o un endpoint delle
  app) — oggi assente.
- **Timezone via `TZ` env** invece di copiare `Europe/Rome` fisso nel layer.
- **Segreti**: le password admin di default (`admin:admin` create in build)
  andrebbero generate al primo avvio o forzate via env, non cotte nell'immagine.
- **`.dockerignore`** già presente: bene, mantenerlo.
- I binari SUID `sdm120c`/`aurora` (`chmod 4711`): valutare se il SUID è
  ancora necessario o se basta aggiungere l'utente ai gruppi
  `dialout`/`uucp` (già fatto) per l'accesso seriale.

### 3.6 Sintesi della migrazione

| Aspetto | Oggi | Proposto |
|---|---|---|
| Immagini da mantenere | 3 repo concatenati | 1 repo, Dockerfile multi-stage |
| Init / supervisor | runit custom (stage 1/2/3) | s6-overlay v3 |
| Ordinamento servizi | polling `sv check` a mano | dipendenze native s6 |
| Log a `docker logs` | syslog-ng → STDOUT/STDERR | servizi → STDOUT/STDERR (s6); syslog-ng opzionale |
| Post-boot scripts | `postScripts-handler` dummy | oneshot `s6-rc` |
| CI/CD | Travis CI (obsoleto) | GitHub Actions + build-push-action |
| Multi-arch | QEMU manuale + registry locale | `setup-qemu`/`setup-buildx` (1 riga) |
| Architetture | 6 (molte inutili) | amd64 + arm64 (+arm/v7 se serve) |
| Update app | script a ogni boot (GitHub API) | versioni pinnate come ARG in build (update = opt-in) |
| Registry | Docker Hub | GHCR (o Docker Hub) |

Il risultato è **funzionalmente equivalente** (stessi due applicativi, stessi
tool seriali, stessi volumi, stesso container unico, stessi log su
`docker logs`) ma con **un solo artefatto da mantenere**, una pipeline
moderna e gratuita, e senza init-system fatto in casa.

---

## 4. Proposta di rebuild con Docker Compose e container multipli

Questa è la proposta **raccomandata** e nasce da due vincoli espliciti:

1. **No build "monolitico" che integra ogni prodotto.** Si vogliono usare
   **immagini ufficiali già pronte** (nginx, php-fpm) invece di ricompilare
   nginx/php dentro un layer custom.
2. **Compatibilità con tutte le architetture della matrice** — inclusi
   Raspberry datati e NAS — quindi Alpine per leggerezza ma con attenzione a
   quali arch le immagini upstream supportano davvero.

L'idea di fondo: **separare le responsabilità in più container orchestrati da
`docker-compose`**, riusando il più possibile immagini pubbliche e limitando
il "custom" alla sola parte che *non esiste* come pacchetto (i tool seriali C).

### 4.1 Il vincolo che decide l'architettura

123solar e meterN non sono "solo PHP": a runtime invocano — via
`exec()` dal codice PHP e via polling/cron — i binari **`sdm120c`**,
**`aurora`**, **`pooler485`** (accesso alle seriali `/dev/ttyUSB*`) e
**`rrdtool`** (generazione grafici/database RRD). Questo ha due conseguenze:

- Non si può usare l'immagine **`php:8-fpm-alpine` "nuda"**: le servono
  quei binari e l'accesso al device seriale. Il container PHP-FPM va comunque
  **esteso** con un Dockerfile minimale (installa `rrdtool` da apk, copia i
  tool seriali compilati, aggiunge l'utente ai gruppi `dialout`/`uucp`).
- **nginx** invece resta **immagine ufficiale pura** (`nginx:alpine`): serve
  solo file statici e fa da reverse-proxy verso php-fpm, senza personalizzazioni
  se non il file di configurazione montato come volume.

Quindi il "custom" si riduce da 3 immagini a **una sola immagine sottile**
(php-fpm + tool), e tutto il resto è composizione di immagini ufficiali.

### 4.2 Topologia dei container proposta

```
┌──────────────────────────────────────────────────────────────┐
│  docker-compose                                                │
│                                                                │
│  ┌────────────┐   fastcgi    ┌─────────────────────────────┐  │
│  │  nginx     │ ───────────▶ │  php-fpm  (immagine custom   │  │
│  │ nginx:     │  (socket TCP │  sottile: php:8-fpm-alpine + │  │
│  │  alpine    │   :9000)     │  rrdtool + sdm120c/aurora)   │  │
│  │  (ufficiale)│             │  → serve 123solar + meterN   │  │
│  └────────────┘              │  → accede a /dev/ttyUSB0     │  │
│        │                     └─────────────────────────────┘  │
│        │ :80/:443                        │                     │
│        ▼                                 │ exec pooler485      │
│   host / rete                            ▼                     │
│                              (device seriale, volumi config/data)│
└──────────────────────────────────────────────────────────────┘
        volumi condivisi: app-code, 123solar/{config,data}, metern/{config,data}
```

**Servizi in `docker-compose.yml`:**

- **`web`** → `nginx:alpine` (ufficiale, nessun build). Monta la config nginx e
  il codice delle app in sola lettura; espone `80` (e opzionale `443`).
- **`app`** → immagine custom sottile (build locale del solo Dockerfile
  php-fpm). Contiene php-fpm + i tool seriali + rrdtool; ha accesso a
  `/dev/ttyUSB0` e ai volumi `config`/`data`. È anche il container che lancia il
  **daemon seriale `pooler485`** e il **polling** delle due app.

**Perché php-fpm e nginx condividono il codice via volume:** con FastCGI, nginx
deve poter leggere i file `.php` per costruire i path, e php-fpm deve
eseguirli. Il codice delle app sta quindi in un **volume condiviso** montato in
entrambi (read-only su nginx, read-write su php dove serve per config/data).

### 4.3 Dove finiscono runit, syslog e il polling

Il grande vantaggio del multi-container è che **runit e syslog-ng spariscono**:

- **Un processo per container** → niente supervisor custom. nginx è già PID 1
  nella sua immagine ufficiale; php-fpm idem. I log vanno **nativamente su
  STDOUT/STDERR** → `docker compose logs` funziona senza syslog-ng.
- **php-fpm**: configurare `error_log = /proc/self/fd/2`,
  `catch_workers_output = yes` e `access.log = /proc/self/fd/2` (l'immagine
  ufficiale è già predisposta per loggare su stderr).
- Il filtro che silenziava `sdm120c` diventa un semplice redirect
  (`>/dev/null`) nel punto in cui il binario viene invocato.

**Il polling e il daemon seriale** (oggi in `start_polling` e
`config_daemon.php`) restano nel container `php`. Due modi puliti per gestirli
senza runit:

- **Daemon `pooler485`**: avviato come processo gestito. Poiché il container
  `php` ha comunque bisogno di far girare *php-fpm* + *pooler485*, questo è
  l'**unico punto dove serve ancora un mini-supervisore**. Qui conviene una
  soluzione leggera: **s6-overlay** (già discusso) *oppure*, ancora più
  semplice, uno **script di entrypoint** che lancia `pooler485 &` in background
  e poi `exec php-fpm`. Per un daemon singolo l'entrypoint basta e avanza; s6
  ha senso solo se i processi secondari crescono.
- **Polling / bootstrap** (`curl .../boot123s.php`, `bootmn.php`): un servizio
  compose separato **`init`/`cron`** *oppure* un one-shot nell'entrypoint del
  container `php` dopo che php-fpm è su. In alternativa un piccolo container
  con `crond` di Alpine se serve schedulazione periodica.

> In pratica: **2 container** (`web` + `php`) coprono il caso base; se si vuole
> isolare la schedulazione si aggiunge un terzo container `cron` — ma non è
> obbligatorio.

### 4.4 Compatibilità multi-architettura

La matrice originale (`multiArchMatrix.sh`) elenca:
`amd64, arm32v6 (arm/v6), arm32v7 (arm/v7), arm64v8 (arm64), i386 (386), ppc64le`.

**Le immagini ufficiali `nginx` e `php` coprono tutta la matrice.** Verificato
sui repository ufficiali Docker Hub — l'elenco "Supported architectures"
riportato è:

- **`nginx`**: `amd64, arm32v5, arm32v6, arm32v7, arm64v8, i386, ppc64le,
  riscv64, s390x`.
- **`php`**: `amd64, arm32v5, arm32v6, arm32v7, arm64v8, i386, mips64le,
  ppc64le, riscv64, s390x`.

Quindi **tutte** le architetture della matrice (compreso `arm32v6` per i
Raspberry Pi 1 / Zero e `ppc64le`) sono presenti:

| Arch (matrice) | Target reale | `nginx` ufficiale | `php` ufficiale |
|---|---|---|---|
| `amd64` | mini-PC / NAS x86 | ✅ | ✅ |
| `arm64v8` | RPi 3/4/5, NAS ARM recenti | ✅ | ✅ |
| `arm32v7` | RPi 2/3, NAS ARM 32-bit | ✅ | ✅ |
| `arm32v6` | RPi 1 / Zero (datati) | ✅ | ✅ |
| `i386` (386) | vecchi x86 32-bit | ✅ | ✅ |
| `ppc64le` | NAS/server IBM | ✅ | ✅ |

> **Correzione rispetto a una prima stesura**: avevo indicato `arm32v6` come
> non supportato dai tag Alpine. È **errato** per queste immagini ufficiali,
> che pubblicano manifest multi-arch comprensive di armv6. La confusione nasce
> dal fatto che *Alpine come distribuzione* ha nel tempo ridotto il supporto
> armhf/armv6 per alcuni pacchetti, ma ciò **non** si riflette sui manifest dei
> tag `nginx`/`php` sopra elencati.

**Unica verifica residua consigliata prima di fissare la matrice finale:**
controllare che la copertura arch valga per lo **specifico tag** che si sceglie
(es. `php:8.3-fpm-alpine` vs `php:8.3-fpm` Debian): la lista "Supported
architectures" della pagina Docker Hub è a livello di repository, mentre il
singolo tag può avere un sottoinsieme. Si verifica con:

```sh
docker buildx imagetools inspect php:8.3-fpm-alpine
docker buildx imagetools inspect nginx:stable-alpine
```

Se un particolare tag `-alpine` non includesse un'arch legacy (es. armv6),
restano due ripieghi **senza compilare nulla**:
- usare la variante **Debian slim** ufficiale per quella arch (stessa immagine
  ufficiale, solo base diversa), oppure
- installare php-fpm/nginx via **`apk`** su una base `arm32v6/alpine` (pacchetti
  precompilati della distro).

**I tool C** (`sdm120c`, `aurora`, `libmodbus`) vanno **comunque compilati** per
ogni arch nello stage `builder` con `docker buildx` multi-arch (come già oggi):
questa parte non dipende da upstream ed è sotto il nostro controllo.

**Raccomandazione:** pubblicare la manifest list multi-arch per **tutta la
matrice** (`linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6, linux/386,
linux/ppc64le`) usando le immagini ufficiali come base, previa verifica
`imagetools inspect` del tag scelto. Così si onora il vincolo "deve girare su
Raspberry datati e NAS" restando su immagini ufficiali per tutte le arch.

> Nota: il `docker-compose.yml` è **arch-agnostico** — Docker seleziona
> automaticamente il layer giusto dalla manifest list multi-arch. La
> compatibilità si gioca tutta in fase di **build/publish** delle immagini, non
> nel compose.

### 4.5 Esempio di `docker-compose.yml` (schematico)

```yaml
services:
  web:
    image: nginx:alpine                     # immagine ufficiale, nessun build
    ports:
      - "${HTTP_PORT:-8080}:80"
    volumes:
      - app-code:/var/www:ro                # codice app in sola lettura
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - php
    restart: unless-stopped

  php:
    build: ./php                            # unico Dockerfile custom (sottile)
    devices:
      - "/dev/ttyUSB0:/dev/ttyUSB0"         # accesso seriale
    environment:
      - TZ=Europe/Rome
      - AUTO_UPDATE=false                   # update app opt-in
    volumes:
      - app-code:/var/www
      - s123_config:/var/www/123solar/config
      - s123_data:/var/www/123solar/data
      - mn_config:/var/www/metern/config
      - mn_data:/var/www/metern/data
    restart: unless-stopped

volumes:
  app-code:
  s123_config:
  s123_data:
  mn_config:
  mn_data:
```

Il `Dockerfile` in `./php` è l'**unica cosa custom** e resta minuscolo:
`FROM php:8-fpm-alpine`, `apk add rrdtool`, `COPY --from=builder` dei tool
seriali, gruppi seriali, entrypoint che lancia `pooler485 &` + `php-fpm`.
Il **codice delle app** può essere popolato nel volume `app-code` al primo
avvio (init-container/one-shot) o incluso nell'immagine `php` con versioni
pinnate (vedi §3.4).

### 4.6 Confronto con la proposta a immagine singola (§3)

| Criterio | §3 Immagine singola (s6) | §4 Multi-container (compose) |
|---|---|---|
| Immagini ufficiali riusate | no (build custom nginx/php) | **sì (nginx, php-fpm)** |
| Componenti custom | 1 immagine completa | **1 immagine sottile** (solo php+tool) |
| Supervisor | s6-overlay | quasi assente (1 entrypoint per pooler485) |
| syslog-ng | opzionale | **eliminato** |
| Log | via s6 → stdout | **nativo** per servizio |
| Multi-arch | dipende dal nostro build | **tutta la matrice** via immagini ufficiali (§4.4) |
| Deploy su NAS/Synology | 1 container | compose (supportato da DSM 7 / Portainer) |
| Isolamento / manutenzione | monolite | **servizi separati, aggiornabili singolarmente** |

La proposta §4 è **preferibile** dato il vincolo "no build monolitico + usa
pacchetti pronti": massimizza il riuso di immagini ufficiali (che coprono tutta
la matrice di arch, §4.4) e minimizza il codice da mantenere.

### 4.7 Repository: aggiornare l'esistente o crearne uno nuovo?

Consiglio: **un nuovo repository monorepo**, archiviando i tre vecchi.

Motivazioni:
- Il vecchio progetto è **tre repository distinti** (`BaseImage-Docker`,
  `nginx-php-fpm-Docker`, `123Solar-meterN-Docker`) concatenati. La nuova
  architettura è **un unico progetto** (compose + un Dockerfile sottile +
  workflow CI): non mappa più sulla vecchia struttura, quindi "aggiornare un
  branch" di uno dei tre repo sarebbe forzato.
- La storia Git dei vecchi repo (Travis, buildx custom, runit) ha **poco valore
  di riuso** per il nuovo assetto: tenerla come archivio di riferimento è
  meglio che trascinarla in un branch attivo.
- Le immagini `edofede/baseimage` e `edofede/nginx-php-fpm` erano pensate come
  **riusabili da terzi**: se qualcuno le usa, vanno lasciate dove sono
  (archiviate, non cancellate) per non rompere i loro build.

**Piano operativo consigliato:**

1. Creare **`123solar-metern-docker`** (nuovo repo monorepo) con:
   `docker-compose.yml`, `php/Dockerfile` (+ stage builder per i tool C),
   `nginx/default.conf`, `.github/workflows/` (GitHub Actions).
2. **Archiviare** i tre repo vecchi su GitHub (flag *Archived*, sola lettura) e
   aggiungere in cima al loro README un avviso *"Deprecato → vedi nuovo repo"*.
3. Sulle immagini Docker Hub `edofede/baseimage` e `edofede/nginx-php-fpm`:
   lasciarle pubblicate; sul repo `edofede/123solar-metern` aggiungere una nota
   di deprecazione e pubblicare la nuova immagine (nuovo nome o nuovo tag major,
   es. `edofede/123solar-metern:2` o pubblicazione su **GHCR**).

**Alternativa** (se si vuole conservare storia/issue/stelle del repo
applicativo): riusare **`123Solar-meterN-Docker`** creando un branch
`v2`/`develop`, spostando il vecchio contenuto sotto `legacy/` (o su un branch
`v1` mantenuto per riferimento) e mettendo la nuova struttura in `main`. È
accettabile ma più disordinato del monorepo nuovo; la scelta dipende da quanto
si tiene alla storia di *quel* repo.

> Sintesi: **repo nuovo (monorepo) + archiviazione dei tre vecchi** è la strada
> più pulita; il riuso del repo applicativo con branch `v2` è il ripiego se
> conta preservarne storia e visibilità.
