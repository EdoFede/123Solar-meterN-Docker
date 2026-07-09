# Guida implementativa — rebuild 123Solar + meterN (multi-container)

Guida operativa per preparare il repository e l'infrastruttura **prima** di
scrivere il codice del nuovo progetto. Segue le decisioni prese in
[`ANALISI-PROGETTO.md`](./ANALISI-PROGETTO.md): architettura multi-container
con Docker Compose (§4), immagini ufficiali `nginx`/`php-fpm`, CI su GitHub
Actions (§2.2), pubblicazione multi-arch per tutta la matrice (§4.4).

> **Scope di questo documento**: setup GitHub, archiviazione del progetto
> attuale, e imbastitura (scaffold) del repository. L'**implementazione vera e
> propria** del codice (Dockerfile, compose, config, entrypoint) verrà fatta in
> una chat separata; qui si prepara solo il terreno e si definisce la struttura.

Repository interessati (verificati dai remote Git locali):
- `EdoFede/BaseImage-Docker` (default: `master`, branch extra: `buildx`, `devel`)
- `EdoFede/nginx-php-fpm-Docker` (default: `master`)
- `EdoFede/123Solar-meterN-Docker` (default: `master`, branch extra: `devel`)

---

## 0. Decisione preliminare: quale repository usare

In §4.7 dell'analisi sono emerse due strade. Per questa guida assumo la scelta
**consigliata di riuso del repo applicativo** `123Solar-meterN-Docker`, perché
conserva storia, issue, star e URL già noti, e perché è il repo che gli utenti
finali già conoscono. Concretamente:

- `123Solar-meterN-Docker` → diventa il **nuovo monorepo** (nuova struttura su
  `main`, vecchio contenuto archiviato su un branch `legacy/v1`).
- `BaseImage-Docker` e `nginx-php-fpm-Docker` → **archiviati** (read-only su
  GitHub), non più mantenuti: la loro funzione è assorbita dalle immagini
  ufficiali.

> Se preferisci partire da zero con un repo dal nome nuovo (es.
> `123solar-metern-docker` minuscolo), i passi §2–§4 restano identici: cambia
> solo che crei un repo vuoto invece di riusare quello esistente. La sezione
> §2 copre entrambi i casi.

---

## 1. Setup GitHub necessario per le GitHub Actions

Prima di scrivere i workflow, l'account/repo va predisposto. Tutto ciò che
segue si fa **una volta**.

### 1.1 Scelta del registry: GHCR, Docker Hub o entrambi

Tre opzioni per pubblicare le immagini:

- **GHCR** (`ghcr.io`, GitHub Container Registry): nessun secret esterno, si usa
  il `GITHUB_TOKEN` automatico, integrato con il repo, senza rate limit sui
  pull. Ottimo come registry "tecnico/CI".
- **Docker Hub** (`edofede/...`): l'URL storico delle immagini, dove la gente
  cerca e dove i tuoi utenti già puntano da anni.
- **Entrambi** — **consigliato nel tuo caso**: mantieni la continuità su Docker
  Hub *e* usi GHCR per la CI. È il pattern documentato in §1.4bis.

#### 1.4bis Pubblicare su entrambi i registry (consigliato)

È supportato nativamente da `metadata-action` + `build-push-action`: **una sola
build multi-arch** pubblica gli stessi tag/digest su tutti e due i registry.
Serve solo il **doppio login** e l'elenco di **entrambe le immagini** nei
metadata:

```yaml
# ...entrambi gli step login-action (§1.3 GHCR + §1.4 Docker Hub)...
- uses: docker/metadata-action@v5
  id: meta
  with:
    images: |
      ghcr.io/edofede/123solar-metern
      edofede/123solar-metern
# un solo build-push-action: costruisce una volta, pusha su entrambi
```

**Vantaggi:**
- **Continuità storica**: chi già fa `docker pull edofede/123solar-metern`
  continua a funzionare senza cambiare i propri compose.
- **Discoverability**: Docker Hub resta il posto dove gli utenti cercano.
- **Nessun rate limit** su GHCR (Docker Hub limita i pull anonimi a 100/6h per
  IP): utile per chi tira l'immagine da CI o da molti nodi.
- **Ridondanza**: se un registry ha un disservizio o cambia policy, l'altro
  copre.

**Svantaggi / costi:**
- **Due set di credenziali**: il token Docker Hub va creato e **rinnovato alla
  scadenza** (GHCR no, usa `GITHUB_TOKEN`).
- **Doppia vetrina da mantenere**: description, overview e note di deprecazione
  vanno aggiornate in due posti.
- **Push più lento / più banda**: i layer viaggiano verso due destinazioni (la
  *build* resta una sola, quindi il costo è solo di trasferimento).
- **Rischio di disallineamento** se un push fallisce su un solo registry
  (mitigato: è la stessa build/digest, basta rilanciare il job).

**Ripartizione consigliata dei tag:**
- **Docker Hub** → tag stabili per gli utenti finali (`latest`, `vX.Y.Z`).
- **GHCR** → tutti i tag, inclusi quelli di sviluppo (`main`, `sha-...`).

Per semplicità puoi comunque pubblicare gli stessi tag su entrambi all'inizio;
la ripartizione fine si può aggiungere dopo. Metti nella *description* di Docker
Hub una nota tipo *"immagine disponibile anche su `ghcr.io/edofede/...`"*.

> Il repo Docker Hub `edofede/123solar-metern` viene creato al primo push (il
> namespace `edofede` è già tuo), quindi non serve prepararlo a mano.

### 1.2 Permessi del workflow (Actions)

Nel repo: **Settings → Actions → General → Workflow permissions**:
- Selezionare **"Read and write permissions"** (serve a `GITHUB_TOKEN` per
  pushare su GHCR e per `docker/metadata-action`).
- Spuntare **"Allow GitHub Actions to create and approve pull requests"** se in
  futuro userai Renovate/Dependabot con PR automatiche (vedi §1.5).

### 1.3 Setup per GHCR (se scegli GHCR)

- Nessun secret da creare: il workflow userà `${{ secrets.GITHUB_TOKEN }}`.
- Il package (immagine) eredita la visibilità; dopo il primo push, in
  **Settings del package** su GitHub puoi renderlo **public** e collegarlo al
  repo ("Connect repository").
- Login nel workflow:
  ```yaml
  - uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}
  ```

### 1.4 Setup per Docker Hub (se scegli Docker Hub)

- Su Docker Hub: **Account Settings → Personal access tokens → Generate** un
  token con scope *Read & Write*.
- Nel repo GitHub: **Settings → Secrets and variables → Actions → New
  repository secret**:
  - `DOCKERHUB_USERNAME` = `edofede`
  - `DOCKERHUB_TOKEN` = il token appena generato (**non** la password).
- Login nel workflow:
  ```yaml
  - uses: docker/login-action@v3
    with:
      username: ${{ secrets.DOCKERHUB_USERNAME }}
      password: ${{ secrets.DOCKERHUB_TOKEN }}
  ```

### 1.5 (Opzionale) Aggiornamenti automatici delle dipendenze

Per automatizzare i bump delle versioni pinnate (immagini base, e le release di
123solar/meterN — vedi §3.4 dell'analisi):
- Abilitare **Dependabot** (Settings → Code security) per gli update dei tag
  Docker e delle action GitHub, **oppure**
- Aggiungere **Renovate** (app GitHub) se vuoi anche il tracking delle release
  upstream via regex-manager.

Non è bloccante per il primo rilascio; si può aggiungere dopo.

### 1.6 Riepilogo azioni GitHub usate dai workflow

Le action ufficiali che i workflow richiameranno (nessuna installazione: sono
pubbliche su Marketplace):

| Azione | Scopo |
|---|---|
| `actions/checkout@v4` | checkout del codice |
| `docker/setup-qemu-action@v3` | emulazione multi-arch |
| `docker/setup-buildx-action@v3` | builder buildx |
| `docker/login-action@v3` | login al registry |
| `docker/metadata-action@v5` | tag/label automatici da git |
| `docker/build-push-action@v6` | build multi-arch + push |

---

## 2. Archiviare la versione attuale in un branch separato

Obiettivo: **congelare** il codice attuale del repo applicativo su un branch di
archivio, così che `main`/`master` possa ospitare la nuova struttura senza
perdere la storia. Poi archiviare i due repo di supporto.

> ⚠️ Operazioni distruttive/irreversibili su repo remoti: eseguirle con
> attenzione. Nessuno di questi comandi va lanciato in automatico — sono da
> eseguire tu, consapevolmente, dopo aver letto ogni passo.

### 2.1 Archiviare il codice attuale di `123Solar-meterN-Docker`

Idea: creare un branch `legacy/v1` che punta all'attuale `master`, marcare un
tag `v1-final`, e lasciare `master` (o crearne uno nuovo `main`) libero per il
refactor.

```sh
# Lavora su un clone pulito del repo applicativo
git clone git@github.com:EdoFede/123Solar-meterN-Docker.git
cd 123Solar-meterN-Docker

# 1) Crea il branch di archivio dallo stato attuale e un tag di riferimento
git checkout master
git branch legacy/v1
git tag -a v1-final -m "Ultima versione dell'architettura a 3 immagini + runit"

# 2) Pubblica branch e tag di archivio
git push origin legacy/v1
git push origin v1-final
```

A questo punto lo storico è al sicuro su `legacy/v1` + tag `v1-final`.

### 2.2 Preparare il branch principale per la nuova struttura

Due sottoscelte, equivalenti nel risultato:

**Opzione A — tieni `master` come branch di sviluppo (svuotato e ricostruito).**
```sh
git checkout master
# Rimuovi tutto il vecchio contenuto (resta nella storia e su legacy/v1)
git rm -r .
git commit -m "chore: reset per rebuild v2 (vecchia struttura su legacy/v1 + tag v1-final)"
# NON pushare ancora: prima costruisci lo scaffold (§3), poi push.
```

**Opzione B — passa a un branch di default moderno `main`.**
```sh
git checkout --orphan main       # nuovo branch senza storia pregressa
git rm -rf .                     # pulisce l'index
# ... costruisci lo scaffold (§3) ...
git add -A && git commit -m "feat: scaffold v2 multi-container (compose)"
git push origin main
# Poi su GitHub: Settings → Branches → cambia default branch a "main"
# e infine, se vuoi, elimina il vecchio "master" remoto (lo storico resta su legacy/v1)
```

> Consiglio: **Opzione B** (`main` come default) è più pulita per un rebuild
> totale; `master` storico può essere rimosso perché tutto è preservato su
> `legacy/v1` e nel tag. Se preferisci non toccare il default branch, usa A.

### 2.3 Aggiungere l'avviso di deprecazione sul branch legacy

Sul branch `legacy/v1`, in cima al README, aggiungi un banner tipo:

```markdown
> ⚠️ **Versione archiviata (v1).** Questa è la vecchia architettura a tre
> immagini con runit/syslog-ng. Non più mantenuta. La versione attuale
> (multi-container, Docker Compose) è sul branch `main`.
```

Commit e push **solo** su `legacy/v1` (non su main).

### 2.4 Archiviare i due repository di supporto

`BaseImage-Docker` e `nginx-php-fpm-Docker` non servono più (assorbiti dalle
immagini ufficiali). Per ciascuno:

1. Aggiungi in cima al README un avviso di deprecazione:
   ```markdown
   > ⚠️ **Repository deprecato e archiviato.** Sostituito dalle immagini
   > ufficiali `nginx` e `php:fpm`. Vedi il progetto attuale:
   > https://github.com/EdoFede/123Solar-meterN-Docker
   ```
   (commit + push su `master`).
2. Su GitHub: **Settings → General → Danger Zone → Archive this repository**.
   Diventa **read-only** (issue/PR congelate, niente push). È **reversibile**
   (si può de-archiviare).

> **Non cancellare** le immagini Docker Hub `edofede/baseimage` e
> `edofede/nginx-php-fpm`: se qualcuno le usa come base, cancellarle ne
> romperebbe i build. Lasciarle pubblicate (eventualmente con una nota di
> deprecazione nella description del repo Docker Hub).

### 2.5 Checklist archiviazione

- [ ] `legacy/v1` creato e pushato su `123Solar-meterN-Docker`
- [ ] tag `v1-final` pushato
- [ ] banner deprecazione su `legacy/v1`
- [ ] branch principale (`main` o `master`) pronto per lo scaffold
- [ ] README deprecazione + **Archive** su `BaseImage-Docker`
- [ ] README deprecazione + **Archive** su `nginx-php-fpm-Docker`
- [ ] immagini Docker Hub lasciate pubblicate (non cancellate)

---

## 3. Imbastire il repository (scaffold del refactor)

Questa sezione definisce **la struttura di cartelle e file** del nuovo
progetto e cosa conterrà ciascuno — **senza** ancora scriverne il contenuto
funzionale (quello è per la chat di implementazione). Serve a partire con un
albero coerente e i "segnaposto" giusti.

### 3.1 Struttura di cartelle proposta

```
123Solar-meterN-Docker/            (branch main)
├── README.md                      # doc utente: quickstart, variabili, volumi
├── LICENSE
├── .gitignore
├── .dockerignore
├── .env.example                   # variabili d'ambiente d'esempio (porte, TZ, device, AUTO_UPDATE)
├── docker-compose.yml             # orchestrazione: servizi web + php (+ cron opz.)
│
├── nginx/
│   └── default.conf               # config nginx (montata nel container ufficiale)
│
├── php/                           # UNICA immagine custom (sottile)
│   ├── Dockerfile                 # multi-stage: builder (tool C) + runtime (php:fpm-alpine)
│   ├── entrypoint.sh              # lancia pooler485 & poi exec php-fpm; bootstrap polling
│   ├── conf.d/
│   │   └── zz-app.ini             # override php.ini (log su stderr, ecc.)
│   └── fpm/
│       └── www.conf               # pool php-fpm (listen :9000, log su stderr)
│
├── app/                           # gestione del codice delle due app
│   └── install-apps.sh            # scarica/pinna 123solar+meterN nelle versioni scelte
│
├── docs/
│   ├── ANALISI-PROGETTO.md        # (spostato qui)
│   └── GUIDA-IMPLEMENTAZIONE.md   # (questo file)
│
└── .github/
    └── workflows/
        ├── ci.yml                 # build+test su PR (arch nativa amd64)
        └── release.yml            # build multi-arch + push su tag/main
```

> Nota: `app/` esiste perché nel modello multi-container il **codice delle app**
> sta in un volume condiviso tra `nginx` e `php`. Va deciso in implementazione
> se popolarlo al primo avvio (one-shot) o includerlo nell'immagine `php` con
> versioni pinnate (vedi analisi §3.4). Lo script `install-apps.sh` è il punto
> unico dove questa scelta si concretizza.

### 3.2 Cosa conterrà ciascun file (segnaposto per l'implementazione)

| File | Responsabilità (da implementare) |
|---|---|
| `docker-compose.yml` | Servizi `web` (nginx:alpine ufficiale) e `php` (build ./php); volumi `app-code`, config/data delle due app; `devices: /dev/ttyUSB0`; `env_file: .env` |
| `nginx/default.conf` | Server block: root `/var/www`, routing `/123solar` e `/metern`, basic-auth su `/admin`, `fastcgi_pass php:9000` |
| `php/Dockerfile` | Stage `builder` (compila libmodbus, sdm120c, aurora) + stage runtime `FROM php:8.x-fpm-alpine` con `apk add rrdtool`, copia binari, gruppi `dialout`/`uucp`, entrypoint |
| `php/entrypoint.sh` | Avvio daemon seriale `pooler485 &`, poi `exec php-fpm`; opzionale trigger bootstrap polling; opzionale auto-update se `AUTO_UPDATE=true` |
| `app/install-apps.sh` | Recupero versioni pinnate di 123solar/meterN (release GitHub), preservando config/data |
| `.env.example` | `HTTP_PORT=8080`, `TZ=Europe/Rome`, `SERIAL_DEVICE=/dev/ttyUSB0`, `AUTO_UPDATE=false`, versioni app |
| `.github/workflows/release.yml` | Build multi-arch (tutta la matrice) + push, con le action di §1.6 |
| `.github/workflows/ci.yml` | Build di verifica su PR (solo amd64) + eventuale smoke test |

### 3.3 File "amministrativi" da creare subito

Questi si possono scrivere già ora (non dipendono dall'implementazione):

- **`.dockerignore`**: escludi `.git`, `docs/`, `*.md`, `.github/`.
- **`.gitignore`**: `.env`, artefatti locali, `build_tmp/`.
- **`.env.example`**: le variabili elencate sopra, con valori di default sicuri.
- **`README.md`**: quickstart (`cp .env.example .env` → `docker compose up -d`),
  tabella variabili, elenco volumi, note multi-arch, link a `docs/`.
- **Spostare** `ANALISI-PROGETTO.md` e questo file in `docs/`.

### 3.4 Ordine consigliato dei commit di scaffold

Per avere una storia leggibile sul nuovo `main`:

1. `chore: scaffold struttura cartelle + file amministrativi` (.gitignore,
   .dockerignore, .env.example, README skeleton, docs/).
2. `ci: workflow GitHub Actions (build multi-arch + release)` — vedi §4.
3. Poi, nella **chat di implementazione**: i commit su `php/`, `nginx/`,
   `docker-compose.yml`, `app/`.

### 3.5 Definition of Done dello scaffold (prima dell'implementazione)

- [ ] Albero cartelle §3.1 creato sul branch principale
- [ ] `.gitignore`, `.dockerignore`, `.env.example`, `README` skeleton presenti
- [ ] `docs/` popolata con analisi + guida
- [ ] due workflow in `.github/workflows/` (anche solo lo scheletro build)
- [ ] repo pusha e i workflow **partono** (anche se falliscono per file mancanti)
- [ ] permessi Actions e secret/registry configurati (§1)

---

## 4. Scheletro dei workflow GitHub Actions

Da mettere in `.github/workflows/`. Sono **scheletri** pronti: la parte di
build punterà al `php/Dockerfile` che scriverai in implementazione. Riportano
tutta la matrice di architetture dell'analisi (§4.4).

### 4.1 `release.yml` — build multi-arch + push

```yaml
name: release
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write        # per push su GHCR
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3

      # --- Login (scegli GHCR e/o Docker Hub) ---
      - name: Login GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Login Docker Hub          # rimuovi se pubblichi solo su GHCR
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: |
            ghcr.io/edofede/123solar-metern
            edofede/123solar-metern     # rimuovi se pubblichi solo su GHCR
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=sha,format=short

      - name: Build & push (php image)
        uses: docker/build-push-action@v6
        with:
          context: ./php
          platforms: linux/amd64,linux/arm64,linux/arm/v7,linux/arm/v6,linux/386,linux/ppc64le
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

> `latest` viene aggiunto automaticamente da `metadata-action` sui tag semver.
> Se un tag `-alpine` non coprisse un'arch legacy (verifica §4.4 dell'analisi),
> riduci la riga `platforms:` di conseguenza.

### 4.2 `ci.yml` — verifica su PR (arch nativa)

```yaml
name: ci
on:
  pull_request:
    branches: [main]

jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - name: Build (amd64, no push)
        uses: docker/build-push-action@v6
        with:
          context: ./php
          platforms: linux/amd64
          push: false
          load: true
          tags: 123solar-metern:ci
      # - name: Smoke test
      #   run: docker run --rm 123solar-metern:ci php -v
```

---

## 5. Riepilogo del percorso

1. **§1** — Prepara GitHub: permessi Actions, registry (GHCR e/o Docker Hub),
   secret. *(una tantum)*
2. **§2** — Archivia: `legacy/v1` + `v1-final` sul repo applicativo; **Archive**
   dei due repo di supporto; immagini Docker Hub lasciate pubblicate.
3. **§3** — Scaffold: crea l'albero cartelle, i file amministrativi, sposta la
   documentazione in `docs/`, prepara i workflow.
4. **§4** — Committa gli scheletri dei workflow e verifica che partano.
5. **Chat separata** — Implementazione vera: `php/Dockerfile` (multi-stage),
   `entrypoint.sh`, `nginx/default.conf`, `docker-compose.yml`, gestione del
   codice app.

A fine §1–§4 il repository è **pronto a ricevere l'implementazione**: struttura
in piedi, CI configurata, storico vecchio al sicuro.
