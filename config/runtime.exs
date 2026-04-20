import Config

# runtime.exs is evaluated at boot time (not compile time), so it's
# the right place to read environment variables.

if System.get_env("PHX_SERVER") do
  config :share_circle, ShareCircleWeb.Endpoint, server: true
end

config :share_circle, ShareCircleWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# ---------------------------------------------------------------------------
# Deployment mode
# ---------------------------------------------------------------------------
# "self_hosted" (default) — single family, local storage, no billing
# "commercial"            — multi-tenant, S3 storage, Stripe billing
deployment_mode = System.get_env("DEPLOYMENT_MODE", "self_hosted")
config :share_circle, deployment_mode: deployment_mode

# ---------------------------------------------------------------------------
# Production-only config
# ---------------------------------------------------------------------------
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing."

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing."

  host = System.get_env("PHX_HOST") || raise "environment variable PHX_HOST is missing."

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :share_circle, ShareCircle.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    socket_options: maybe_ipv6

  config :share_circle, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :share_circle, ShareCircleWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base

  # -------------------------------------------------------------------------
  # Storage adapter
  # -------------------------------------------------------------------------
  # STORAGE_ADAPTER=local  — filesystem (default for self-hosted)
  # STORAGE_ADAPTER=s3     — S3-compatible (Cloudflare R2 in commercial)
  case System.get_env("STORAGE_ADAPTER", "local") do
    "s3" ->
      config :share_circle, :storage_adapter, ShareCircle.Storage.S3

      config :share_circle, ShareCircle.Storage.S3,
        bucket: System.get_env("STORAGE_S3_BUCKET") || raise("STORAGE_S3_BUCKET is missing"),
        region: System.get_env("STORAGE_S3_REGION", "auto"),
        endpoint: System.get_env("STORAGE_S3_ENDPOINT"),
        access_key: System.get_env("STORAGE_S3_ACCESS_KEY") || raise("STORAGE_S3_ACCESS_KEY is missing"),
        secret_key: System.get_env("STORAGE_S3_SECRET_KEY") || raise("STORAGE_S3_SECRET_KEY is missing")

    _ ->
      config :share_circle, :storage_adapter, ShareCircle.Storage.Local

      config :share_circle, ShareCircle.Storage.Local,
        path: System.get_env("STORAGE_LOCAL_PATH", "/data/media")
  end

  # -------------------------------------------------------------------------
  # Mail adapter
  # -------------------------------------------------------------------------
  # MAIL_ADAPTER=smtp     — generic SMTP
  # MAIL_ADAPTER=postmark — Postmark API
  # MAIL_ADAPTER=ses      — Amazon SES
  case System.get_env("MAIL_ADAPTER", "smtp") do
    "postmark" ->
      config :share_circle, ShareCircle.Mailer,
        adapter: Swoosh.Adapters.Postmark,
        api_key: System.get_env("POSTMARK_API_KEY") || raise("POSTMARK_API_KEY is missing")

    "ses" ->
      config :share_circle, ShareCircle.Mailer,
        adapter: Swoosh.Adapters.AmazonSES,
        region: System.get_env("AWS_REGION") || raise("AWS_REGION is missing"),
        access_key: System.get_env("AWS_ACCESS_KEY_ID") || raise("AWS_ACCESS_KEY_ID is missing"),
        secret: System.get_env("AWS_SECRET_ACCESS_KEY") || raise("AWS_SECRET_ACCESS_KEY is missing")

    _ ->
      config :share_circle, ShareCircle.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: System.get_env("SMTP_HOST") || raise("SMTP_HOST is missing"),
        port: String.to_integer(System.get_env("SMTP_PORT", "587")),
        username: System.get_env("SMTP_USERNAME"),
        password: System.get_env("SMTP_PASSWORD"),
        tls: :always
  end

  # -------------------------------------------------------------------------
  # Billing adapter
  # -------------------------------------------------------------------------
  # BILLING_ADAPTER=noop   — no-op (default for self-hosted)
  # BILLING_ADAPTER=stripe — Stripe (commercial)
  case System.get_env("BILLING_ADAPTER", "noop") do
    "stripe" ->
      config :share_circle, :billing_adapter, ShareCircle.Billing.Stripe

      config :share_circle, ShareCircle.Billing.Stripe,
        secret_key: System.get_env("STRIPE_SECRET_KEY") || raise("STRIPE_SECRET_KEY is missing"),
        webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET") || raise("STRIPE_WEBHOOK_SECRET is missing")

    _ ->
      config :share_circle, :billing_adapter, ShareCircle.Billing.Noop
  end
end
