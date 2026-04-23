# Configuration Reference

All configuration is supplied via environment variables, resolved at boot time in `config/runtime.exs`. No application restart is required to pick up changes — but a container restart is.

## Required

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string. Format: `postgres://user:password@host:5432/dbname` |
| `SECRET_KEY_BASE` | 64-byte random secret used to sign cookies and tokens. Generate with `mix phx.gen.secret`. |
| `PHX_HOST` | Public hostname the app is served from, e.g. `family.example.com`. Used to build URLs in emails. |

## Deployment

| Variable | Default | Description |
|---|---|---|
| `DEPLOYMENT_MODE` | `self_hosted` | `self_hosted` or `commercial`. Controls which feature flags and adapters are active. |
| `PORT` | `4000` | HTTP port the app listens on. |
| `PHX_SERVER` | — | Set to `"true"` to start the HTTP server (required in the `app` container; omit in `worker`). |
| `POOL_SIZE` | `10` | Ecto database connection pool size. |
| `ECTO_IPV6` | — | Set to `"true"` to enable IPv6 database connections. |

## Storage

| Variable | Default | Description |
|---|---|---|
| `STORAGE_ADAPTER` | `local` | `local` or `s3`. |
| `STORAGE_LOCAL_PATH` | `./uploads` | Filesystem path for local storage. Should be a Docker volume mount in production. |
| `STORAGE_S3_BUCKET` | — | S3-compatible bucket name. Required when `STORAGE_ADAPTER=s3`. |
| `STORAGE_S3_REGION` | `auto` | AWS region or `auto` for Cloudflare R2. |
| `STORAGE_S3_ENDPOINT` | — | Custom endpoint URL for S3-compatible services (R2, MinIO, etc.). |
| `STORAGE_S3_ACCESS_KEY` | — | S3 access key ID. |
| `STORAGE_S3_SECRET_KEY` | — | S3 secret access key. |

## Email

| Variable | Default | Description |
|---|---|---|
| `MAIL_ADAPTER` | `smtp` | `smtp` or `local` (prints to console, useful for dev). |
| `SMTP_HOST` | — | SMTP server hostname. |
| `SMTP_PORT` | `587` | SMTP port. |
| `SMTP_USERNAME` | — | SMTP authentication username. |
| `SMTP_PASSWORD` | — | SMTP authentication password. |
| `SMTP_TLS` | `true` | Set to `"false"` to disable TLS (not recommended). |
| `MAIL_FROM` | `notifications@example.com` | From address used for outbound emails. |

## Quotas

These values are applied when a **new family is created**. Existing families retain their current DB values, which can be overridden per-family via the admin dashboard.

| Variable | Default | Description |
|---|---|---|
| `STORAGE_QUOTA_GB` | `10` | Default storage quota per family, in gigabytes. |
| `MEMBER_LIMIT` | `50` | Default maximum members per family. |

## Push Notifications (optional)

| Variable | Default | Description |
|---|---|---|
| `PUSH_ADAPTER` | `noop` | `noop` (disabled) or `web_push`. |
| `VAPID_PUBLIC_KEY` | — | VAPID public key for web push. Generate with a VAPID tool. |
| `VAPID_PRIVATE_KEY` | — | VAPID private key for web push. |
| `VAPID_SUBJECT` | — | Contact email or URL for VAPID, e.g. `mailto:admin@example.com`. |

## Oban (background jobs)

| Variable | Default | Description |
|---|---|---|
| `OBAN_QUEUES_MEDIA` | `4` | Concurrency for the media processing queue. Reduce if CPU-bound. |
| `OBAN_QUEUES_NOTIFICATIONS` | `10` | Concurrency for the notifications queue. |

## Operations

### First-time setup

On first boot with an empty database, navigate to `http://<host>/setup` to create the admin account and first family. The setup page is only accessible when no users exist.

### Running migrations manually

```sh
# Inside the container or via docker exec
bin/share_circle eval "ShareCircle.Release.migrate()"

# Roll back to a specific migration version
bin/share_circle eval "ShareCircle.Release.rollback(ShareCircle.Repo, 20260420135605)"
```

By default, the `app` container runs migrations automatically on startup via the entrypoint script. Set `SKIP_MIGRATIONS=true` on the `worker` container to avoid running migrations twice.

### Upgrading

```sh
# Pull the new image
docker compose pull

# Bring up the new version (entrypoint runs migrations automatically)
docker compose up -d
```

### Backup

Back up the PostgreSQL database and the media volume:

```sh
# Database
docker exec <postgres_container> pg_dump -U sharecircle sharecircle > backup.sql

# Media (if using local storage)
tar -czf media_backup.tar.gz /path/to/media/volume
```
