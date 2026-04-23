# Stage 1: Build
FROM hexpm/elixir:1.19.5-erlang-28-debian-bookworm-20250317-slim AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Fetch deps first so this layer is cached unless mix.exs/mix.lock change
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Compile deps with config (config changes invalidate dep compilation)
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Build assets
COPY priv priv
COPY assets assets
RUN mix assets.deploy

# Compile app
COPY lib lib
RUN mix compile

# runtime.exs is copied last — it doesn't affect compilation
COPY config/runtime.exs config/

RUN mix release

# ---------------------------------------------------------------------------
# Stage 2: Run
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/share_circle ./
COPY --chown=nobody:root docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

USER nobody

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["start"]
