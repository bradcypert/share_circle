# ShareCircle

A private social network for families. Each family is an isolated group where members can share posts (text, photos, videos), chat, and manage events — with strong privacy guarantees and no cross-family data leakage.

Two deployment modes are supported from the same codebase:

- **Self-hosted** — `docker compose up`, single family, local media storage
- **Commercial** — multi-tenant, Kubernetes, S3-compatible media (Cloudflare R2 recommended)

## Features

- Feed with text, photo, video, and album posts; comments and reactions
- Group and direct messaging with real-time delivery and read receipts
- Family calendar with event RSVPs
- Role-based access control (`owner > admin > member > limited`)
- Web push and email notifications
- PWA-ready (installable, service worker)
- OpenAPI 3.1 spec at `/api/v1/docs`

## Tech stack

| | |
|---|---|
| Language | Elixir 1.19 |
| Web | Phoenix 1.8 + LiveView 1.1 |
| Database | PostgreSQL 16 |
| Background jobs | Oban 2.18 |
| Media | FFmpeg (video) + Vix/libvips (images) |
| Auth | Argon2id passwords; opaque Bearer tokens (API); signed session cookies (web) |

## Self-hosted quick start

**Prerequisites:** Docker + Docker Compose, `openssl`

1. Generate secrets:

   ```bash
   SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')
   DB_PASSWORD=$(openssl rand -hex 32)
   ```

2. Create a `.env` file:

   ```env
   SECRET_KEY_BASE=<value from above>
   DB_PASSWORD=<value from above>
   PHX_HOST=yourdomain.example.com   # or localhost
   MAIL_ADAPTER=smtp
   SMTP_HOST=smtp.example.com
   SMTP_PORT=587
   SMTP_USERNAME=user@example.com
   SMTP_PASSWORD=yourpassword
   ```

3. Start:

   ```bash
   docker compose -f docker/docker-compose.yml up -d
   ```

   The app runs on port `4000`. Put a reverse proxy (nginx, Caddy) in front for TLS.

4. Visit `http://localhost:4000` and create the first account — it becomes the family owner.

## Development setup

**Prerequisites:** Elixir 1.19, Node 22, Docker

```bash
# Start Postgres
docker compose -f docker/docker-compose.dev.yml up -d

# Install deps and set up the database
mix deps.get
mix ecto.reset        # creates, migrates, and seeds

# Install JS tooling (for the changeset CLI)
npm install

# Start the server
mix phx.server
```

Visit `http://localhost:4000`.

### Useful commands

```bash
mix test                                              # run all tests
mix test test/share_circle/accounts_test.exs:42      # single test by line
mix precommit                                         # format + credo + sobelow + deps.audit
iex -S mix phx.server                                 # server with IEx attached
```

### Environment variables (dev)

Dev defaults are in `config/dev.exs`. You can override in a local `.env` file or export them in your shell. Key variables:

| Variable | Default | Purpose |
|---|---|---|
| `DEPLOYMENT_MODE` | `self_hosted` | `self_hosted` or `commercial` |
| `DATABASE_URL` | dev defaults | Postgres connection string |
| `SECRET_KEY_BASE` | dev default | Cookie/token signing (change in prod) |
| `STORAGE_ADAPTER` | `local` | `local` or `s3` |
| `MAIL_ADAPTER` | `local` | `local` (inbox at `/dev/mailbox`) or `smtp` |

## Project layout

```
lib/
  share_circle/           # domain contexts
    accounts/             # users, auth, sessions
    families/             # family entity, memberships, invitations, RBAC
    posts/                # feed posts, comments, reactions
    chat/                 # conversations, messages, read receipts
    events/               # calendar events, RSVPs
    media/                # upload sessions, processing pipeline, variants
    notifications/        # in-app, email, web push
    audit/                # sensitive operation logging
    storage/              # object storage adapter (local / S3)
    mail/                 # email delivery adapter
    push/                 # web push adapter
  share_circle_web/       # Phoenix web layer
    api/v1/               # JSON controllers
    live/                 # LiveView pages
    channels/             # WebSocket channels
    plugs/                # auth, rate limiting
  share_circle_workers/   # Oban background jobs
priv/openapi/v1.yaml      # OpenAPI 3.1 spec (source of truth)
docker/                   # Docker Compose files
test/load/                # k6 load test scripts
```

## Changelog

This project uses [changesets](https://github.com/changesets/changesets). Every PR that changes behaviour must include a changeset:

```bash
npm run changeset   # describe your change
npm run version     # apply changesets → updates CHANGELOG.md
npm run release     # tag the release (after version bump is merged)
```

## API

The REST API is versioned at `/api/v1/`. Interactive docs (Swagger UI) are available at `/api/v1/docs` when the server is running. The OpenAPI spec is the source of truth at `priv/openapi/v1.yaml`.

Pagination is cursor-based (`?cursor=...&limit=25`). All responses use the envelope `{"data": {...}, "meta": {"request_id": "..."}}`. Idempotency is supported via the `Idempotency-Key` request header (24-hour cache).

## License

See `LICENSE`.
