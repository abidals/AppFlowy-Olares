# PLAN-appflowy.md

Context, architecture, and upgrade playbook for the **AppFlowy** Olares application chart.
Read this before editing anything under `appflowy/`.

---

## 1. What this is

An [Olares Application Chart (OAC)](https://docs.olares.com/developer/develop/package/chart) that
deploys the full **AppFlowy Cloud** self-hosting stack on Olares, adapted from the official
`AppFlowy-IO/AppFlowy-Cloud` `docker-compose.yml` (the upstream self-hosting guide:
https://appflowy.com/docs/Step-by-step-Self-Hosting-Guide---From-Zero-to-Production).

- Chart folder: `appflowy/` (name must stay `appflowy`, matching `metadata.name` and `Chart.yaml name`)
- Current chart version: see `appflowy/Chart.yaml` (`version` must equal `metadata.version` in `OlaresManifest.yaml`)
- Upstream app version: `spec.versionName` (currently AppFlowy Cloud `0.18.9`)
- Submitter / owner: **abidals**
- Repo: https://github.com/abidals/AppFlowy-Olares (source in `main`; packaged charts
  published **only** as GitHub Release assets — `*.tgz` is gitignored, never committed).
  Release automation: push a tag `v<version>` and the workflow lints, packages and attaches
  `appflowy-<version>.tgz` to the release. Admin email for the my@cgtale.com instance:
  `abidal@unbe.at` (changed 2026-09-22 by re-running the installer envs).
- Tested on: Olares 1.12.6, amd64 node, `my@cgtale.com` (owner), deployed 2026-09-21

**Status at time of writing:** `running` on my@cgtale.com, public entrance
`https://9a094675.my.cgtale.com` — AppFlowy Web UI (200), `/api/*` (cloud), `/gotrue/*` (auth),
`/ws/v2/{workspace_id}` (websocket collab), `/minio-api/*` (presigned S3). Admin console
(`/console`) and MinIO console (`/minio/`) are LAN/VPN-only by design.

## 2. Services in the chart (11 workloads)

| Workload (Deployment) | Image | Port | Purpose |
|---|---|---|---|
| `appflowy` | `beclab/aboveos-nginx:1.27.0` | 80 + 8080 | Router (public path routing, adapted from upstream `nginx/nginx.conf`) |
| `appflowy-cloud` | `appflowyinc/appflowy_cloud:0.18.9` | 8000 | Main API + websocket collab server |
| `gotrue` | `appflowyinc/gotrue:0.18.9` | 9999 | Auth (Supabase Auth fork; runs `./auth migrate` at start, uid 1000) |
| `admin-frontend` | `appflowyinc/admin_frontend:0.18.1` | 3000 | Admin console (LAN only) |
| `appflowy-ai` | `appflowyinc/appflowy_ai:0.17.7` | 5001 | AI microservice (OpenAI-compatible providers) |
| `appflowy-worker` | `appflowyinc/appflowy_worker:0.18.9` | 4001 | Background worker (imports, blob compaction) |
| `appflowy-search` | `appflowyinc/appflowy_search:0.18.9` | 4002 | Full-text + semantic search |
| `appflowy-web` | `appflowyinc/appflowy_web:0.18.4` | 80 | AppFlowy Web UI (supervisord: nginx + Bun SSR) |
| `appflowy-pg` | `beclab/pgvector-pgvector:0.8.0-pg15` | 5432 | Bundled PostgreSQL 15 + pgvector (`ssl=off`) |
| `minio` | `beclab/minio-minio:RELEASE.2025-07-23T15-54-02Z` | 9000/9001 | Bundled object storage |
| `redis` | `beclab/aboveos-redis:7` | 6379 | Bundled Redis (streams/queues) |

All replicas are 1; `workloadReplicas` in `OlaresManifest.yaml` must list every workload
(exact names), and each Deployment's `spec.replicas` must reference
`.Values.workloads.<name>.replicaCount` (or `(index .Values.workloads "name").replicaCount`
for dashed names — plain dot notation breaks helm parsing for dashes).

## 3. Why some databases are bundled (deviations from Olares defaults)

The Olares convention is "use system middleware" (PostgreSQL/Redis/MinIO). This chart deviates
deliberately — do not "fix" without re-testing each point:

1. **Bundled PostgreSQL (`appflowy-pg`) instead of system Citus middleware.**
   The system middleware (Postgres 17 Citus at `citus-master-svc.user-system-my`) serves
   **TLS with an auto-generated X.509 v1 certificate** (`CN=citus-auto-ssl`, version 1).
   AppFlowy's Rust services (sqlx 0.8 + rustls) reject v1 certs during TLS:
   `invalid peer certificate: Other(UnsupportedCertVersion)`. libpq (psql, Go) accept it —
   which is why the OLAprobe/debug pod worked while the app didn't.
   Additionally, `appflowy_cloud`'s source **overwrites** the connection's sslmode with
   `Prefer` (TLS-first) unless `APPFLOWY_DATABASE_REQUIRE_SSL=true`, so `?sslmode=disable` in
   the URL has no effect (`src/config/config.rs:128 pg_connect_options()`).
   Forcing `REQUIRE_SSL=true` still fails (rustls parses the v1 cert).
   → bundled PG runs with `ssl=off`; plain TCP inside the app namespace only.
   Also gives us pgvector (`vector` extension) for AI embeddings.
2. **Bundled Redis** (`beclab/aboveos-redis:7`): AppFlowy leans on Redis Streams
   (collab streams, awareness gossip, worker queues). FastGPT and AFFiNE charts also bundle
   Redis for identical reasons (kvrocks-based system Redis compatibility risk).
3. **Bundled MinIO**: presigned URLs are signed against the internal endpoint
   (`APPFLOWY_S3_MINIO_URL=http://minio:9000`) and served publicly via the router's
   `/minio-api/` location which rewrites `Host: minio:9000` so signatures validate.
   Bundling keeps this exact upstream behavior self-contained (FastGPT precedent).

**Version bump discipline:** every chart/manifest/image change bumps
`Chart.yaml version` == `OlaresManifest.yaml metadata.version` (patch increments are fine).

## 4. Storage & identity

- `permission.appData: true` — data lives under the Olares userspace
  `{{ .Values.userspace.appData }}` (hostPath, `DirectoryOrCreate`, per-leaf mounts):
  - `.../pg/pgdata4` — PGDATA (note: **pgdata4** — pgdata/pgdata2/pgdata3 are stale dirs
    from earlier retried installs; safe to delete them manually later)
  - `.../minio` — MinIO backend
  - `.../redis` — Redis appendonly dir
  - `.../keyword-index` — appflowy-search keyword index
- Redis/MinIO/PG run with **no explicit securityContext** (image-default root). Reasons:
  - postgres refuses to start as root itself but its docker-entrypoint gosu's to `postgres`
  - minio/redis official entrypoints chown their own dirs; running uid 1000 caused
    permission races with the platform's root-owned `DirectoryOrCreate` leaves
  - OPA admission only denies **explicit** root-equivalent securityContext for untrusted
    images; implicit (absent) is allowed and these images are `beclab/` trusted
- Rust services (cloud/worker/search/ai) run `securityContext.runAsUser/Group: 1000`.
- gotrue image runs as uid 1000 natively.
- `beclab/aboveos-busybox:1.37.0` initContainer (uid 0) chowns each data leaf **non-recursively**
  for the search keyword index.

## 5. Public entrance & networking

- One entrance: `entrances[0]`, `authLevel: public`, `host: appflowy`, port 80.
  `options.apiTimeout: 0` (websocket + long uploads + slow LLM streams).
- The real URL is injected as `.Values.domain.appflowy` (comma-list, take `_0` — host only,
  no scheme). Derived:
  - `APPFLOWY_BASE_URL = https://<domain>`
  - `APPFLOWY_WEBSOCKET_BASE_URL = wss://<domain>/ws/v2`
  - `API_EXTERNAL_URL = https://<domain>/gotrue`
  - `MINIO_BROWSER_REDIRECT_URL = https://<domain>/minio`
  - `APPFLOWY_S3_PRESIGNED_URL_ENDPOINT = https://<domain>/minio-api`
- Router (`appflowy` deployment) path map (from upstream nginx.conf):
  `/gotrue/`→gotrue:9999 (strip), `/ws`→cloud:8000 (websocket, 86400s), `/api`→cloud:8000,
  `/minio-api/`→minio:9000 (Host rewrite for signature), `/minio/`→minio:9001 (LAN only),
  `/console`→admin-frontend:3000 (LAN only), `/ai/`→cloud, `/`→appflowy-web:80.
- Native clients (desktop/mobile) sync by setting the AppFlowy Cloud server URL to
  `https://9a094675.my.cgtale.com` (public, no VPN needed).

## 6. Secrets & generated values (`appflowy-config` Secret)

- `GOTRUE_JWT_SECRET`, `APPFLOWY_S3_ACCESS_KEY/SECRET_KEY`, `MINIO_ROOT_USER/PASSWORD`,
  `APPFLOWY_PG_PASSWORD` — generated once via `lookup`+`randAlphaNum` in `templates/_helpers.tpl`,
  **kept across reinstalls** with `helm.sh/resource-policy: keep`. Do not rotate casually:
  changing the JWT secret invalidates all client sessions/data signatures.
- User-supplied (install-time envs): `GOTRUE_ADMIN_EMAIL`, `GOTRUE_ADMIN_PASSWORD` (required),
  `GOTRUE_DISABLE_SIGNUP` (default **true** — admin-created accounts only),
  `AI_OPENAI_API_KEY`, `OPENAI_BASE_URL`, `DEFAULT_AI_MODEL`, SMTP host/port/user/pass/admin-email.
- SMTP: when `SMTP_HOST` is empty → `GOTRUE_MAILER_AUTOCONFIRM=true` (sign-ups confirmed
  automatically, no mail needed). When set → autoconfirm off + confirmation emails.
- **gotrue quirk (fixed in chart)**: gotrue's runtime + `./auth admin createuser` read
  `DATABASE_URL` and expect the **`auth` schema search path**, while the main migrate step uses
  the same URL. The gotrue Deployment sets BOTH
  `DATABASE_URL` and `GOTRUE_DATABASE_URL` to the value with `?search_path=auth`.
- **appflowy-ai quirk**: the binary's "JWT_SECRET" panic actually reads
  `APPFLOWY_GOTRUE_JWT_SECRET` env. It wants `DATABASE_URL` (or `AI_DATABASE_URL`).
  Provider enablement is by env presence: only render `OPENAI_API_KEY` /
  `OPENAI_BASE_URL` envs when the user supplied values (empty strings would enable a
  broken provider).

## 7. AI / local-AI status (review outcome)

- **Server-side AI chat/summaries** (`appflowy-ai`) supports OpenAI-compatible endpoints:
  set install envs `AI_OPENAI_API_KEY` + `OPENAI_BASE_URL` (e.g. an Olares Router gateway URL).
  Models are picked via `DEFAULT_AI_MODEL` / `DEFAULT_AI_COMPLETION_MODEL` (default
  `gpt-4.1-mini` — must exist on the target provider).
- **Embeddings/semantic search** inside `appflowy_cloud`/`appflowy_search` is hardcoded to
  `api.openai.com` (no base-URL override upstream); a standard OpenAI key is required for
  embeddings, or leave `AI_OPENAI_API_KEY` empty → keyword search only.
- **Desktop "Local AI" (AppFlowy-LAI)** runs on the client device (e.g. its own Ollama
  plugin) — nothing to configure server-side.
- Chart does NOT set `LLMGatewaySupported` — revisit when Router app-level injection exists.

## 8. Deployment / upgrade runbook

```bash
# 1. edit chart, keep versions in sync (Chart.yaml version == metadata.version)
olares-cli chart lint /path/to/this/repo/appflowy

# 2. package + upload + upgrade
olares-cli chart package appflowy                     # appflowy-<ver>.tgz
olares-cli market upload appflowy-<ver>.tgz
olares-cli market upgrade appflowy -s upload --version <ver>

# 3. watch
olares-cli cluster pod list -n appflowy-my
olares-cli cluster pod logs <ns>/<pod> -c <container>
olares-cli market status appflowy            # state: running

# verify
curl https://9a094675.my.cgtale.com/api/health          # -> OK
curl https://9a094675.my.cgtale.com/gotrue/health       # -> 200
curl https://9a094675.my.cgtale.com/app                 # -> 200 web

# full reset (nuke app data too) — NOTE: may leave stale pgdata dirs,
# see §4; files rm works on drive/Data only
olares-cli market uninstall appflowy --delete-data
olares-cli files rm --recursive --force drive/Data/appflowy   # then reinstall
```

Username/namespace: `appflowy-my` namespace; ApplicationManager name `appflowy-my-appflowy`.

### Known install-state traps (Olares 1.12.6)

- `market uninstall --delete-data` may **not** remove hostPath leaves created by
  `DirectoryOrCreate` (the Files API path ≠ the pod hostPath backend). If a data dir persists,
  change the sub-path (as done: `pgdata` → `pgdata2` → `pgdata3`) or wipe with a one-off job.
- `market upgrade` waits for app startup; a CrashLooping **primary** container (router `nginx`
  or the `appflowy-cloud`) fails the upgrade. Cancel/stop isn't available in 1.12.6 while
  `upgrading` — let it fail to `upgradeFailed`, then re-upgrade after fixing.
- Bare debug Pods in the chart cannot be helm-upgraded in place (pod spec immutable) —
  ended with `upgradeFailed`; removed them all in the final chart.

## 9. Update procedure (new upstream AppFlowy release)

1. Check image tags on Docker Hub (`appflowyinc/*`); the project publishes per-service tags
   (`0.18.9`, `-amd64`, `-arm64v8`) and `latest`. ai uses an independent version line
   (e.g. `0.17.7`); web may have `x.y.z_test` pre-releases — do not use `_test` tags.
   Current pins live in `appflowy/values.yaml`.
2. Verify multi-arch: `docker manifest inspect <image>` (amd64 + arm64 required to keep
   `spec.supportArch: [amd64, arm64]`).
3. Diff upstream `docker-compose.yml` + `deploy.env` vs our `values.yaml`/templates for new
   envs. Notable env surface to watch: `APPFLOWY_*`, `AI_*`, `GOTRUE_*`, worker database blobs.
   Repo: https://github.com/AppFlowy-IO/AppFlowy-Cloud
4. Bump `images:` in `values.yaml`, bump `spec.versionName` in the 3 manifests,
   bump chart version, add `upgradeDescription` (en + zh), lint:
   `olares-cli chart lint appflowy`, package, upload, upgrade, watch pods.
5. Test matrix after upgrade: `/api/health`, `/gotrue/health`, `/app` (web), login via
   native client to `https://9a094675.my.cgtale.com`, doc sync + ws edit from two devices,
   file attachment upload (minio-api presigned), admin console over LAN.

## 10. Known limitations / To-do

- [ ] Semantic search embeddings require a real OpenAI key (see §7). Upstream may add an
      embedding base-URL override — watch `libs/indexer/src/vector/embedder.rs`.
- [ ] PG15 (pgvector 0.8.0) vs upstream PG16 — fine so far; revisit if a migration needs PG16+.
- [ ] `pgdata`/`pgdata2` stale dirs under Data/appflowy (from retried installs) can be
      deleted once comfortable.
- [ ] Redis `maxmemory 512mb` + `noeviction` (values.yaml `redisMaxMemory`) — raise for big teams.
- [ ] OAuth providers (Google/GitHub/Discord) are disabled in the manifest template; to enable,
      add callback envs in `deployment-gotrue.yaml` — redirect URI pattern
      `https://<domain>/gotrue/callback` (per upstream AUTHENTICATION.md).
- [ ] The entrance URL (`9a094675.my.cgtale.com`) is the native-client sync URL; document it
      for users on the app's market page after promotion.
- [ ] Consider `options.LLMGatewaySupported: true` once Olares exposes a documented in-cluster
      Router data-plane URL for app workloads.
- [ ] Backup: appData is JuiceFS-backed and snapshotted by Olares; MnIO/PG/Redis data sits there.