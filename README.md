# AppFlowy for Olares

[AppFlowy](https://appflowy.io) — open-source Notion alternative — packaged as an Olares Application Chart (OAC).
This chart deploys the complete **AppFlowy Cloud** self-hosting stack so you can sync the AppFlowy
desktop/mobile apps against **your own Olares**, with a public HTTPS sync URL, inbox-strength
defaults, and optional local AI.

> This chart is distributed independently — it is **not** submitted to the official
> `beclab/apps` Market index (no GitBot PR), so anyone may install it from this repo's
> packaged chart. See [PLAN-appflowy.md](./PLAN-appflowy.md) for full context.

## Features

- Full AppFlowy Cloud stack: web UI, realtime collab API (websocket), auth (GoTrue),
  background worker, search, AI service, admin console
- Private real-time sync for **AppFlowy desktop & mobile clients from anywhere** (public entrance,
  Olares-managed TLS)
- Bundled PostgreSQL (pgvector), MinIO object storage and Redis — no external dependencies
- Data persisted in your Olares userspace (`Data`), included in platform backups
- Optional AI: OpenAI-compatible key **or** local AI gateway (e.g. Olares Router) via
  `OPENAI_BASE_URL`; desktop "Local AI" works client-side regardless
- Admin console & MinIO console exposed to LAN/VPN only (`/console`, `/minio`)
- Signup defaults to admin-created accounts (`GOTRUE_DISABLE_SIGNUP=true`), switchable at install

## Versions

| AppFlowy Cloud | Chart |
|---|---|
| 0.18.9 (latest stable of each service pinned per service) | 1.2.1 |

## Install

1. Package the chart (requires [olares-cli](https://olares.com)):
   ```bash
   olares-cli chart lint appflowy
   olares-cli chart package appflowy        # → appflowy-1.2.0.tgz
   ```
2. Download the packaged chart from **Releases**
   (`https://github.com/abidals/AppFlowy-Olares/releases` — pick the latest, e.g.
   `appflowy-1.2.1.tgz`; new versions are always published there, never committed to `main`),
   then either install from your machine:
   ```bash
   olares-cli market upload appflowy-1.2.1.tgz
   olares-cli market install appflowy -s upload \
     --env GOTRUE_ADMIN_EMAIL=you@example.com \
     --env GOTRUE_ADMIN_PASSWORD='your-admin-password' \
     -w
   ```
   or use **Market → Install custom app** in the Olares Desktop and select the downloaded file.
3. After install, open the AppFlowy entrance (e.g. `https://<hash>.<your-id>.<cluster>`) —
   the AppFlowy Web UI. Native apps: set the **AppFlowy Cloud server** to the same URL
   in AppFlowy's *Settings → Sync* and sign in with an account the admin created in
   `<url>/console` (LAN) or via self-signup if you enabled it.

## Repo layout

```
appflowy/            Olares Application Chart (OlaresManifest.yaml, Chart.yaml, templates/)
assets/              icon + product screenshots (market page images)
PLAN-appflowy.md     architecture/upgrade playbook — READ BEFORE EDITING the chart
```

### Releasing a new version

Packaged charts live **only in GitHub Releases** (one release per chart version, asset
`appflowy-<version>.tgz`); `main` carries the latest source only and `*.tgz` is gitignored.
To ship an update:

```bash
# bump appflowy/Chart.yaml version + OlaresManifest metadata.version (+ spec.versionName if needed),
# then:
git commit -am "release 1.2.x"
git tag v1.2.x && git push origin main v1.2.x
```

The `v*` tag triggers the workflow: lint → package → publish the Release with the `.tgz` asset.

## Notes & limits

- Generic x86_64 + arm64 Olares hosts are supported (`spec.supportArch`).
- Semantic search embeddings require an OpenAI key (upstream limitation); everything else
  runs fully self-contained.
- See [PLAN-appflowy.md](./PLAN-appflowy.md) for known limitations, security posture and
  the upgrade runbook.

## License

App upstream: AGPL-3.0 (AppFlowy / AppFlowy-Cloud). Chart files: AGPL-3.0 as well — see the
`owners` file for maintainers (abidals).