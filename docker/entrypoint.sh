#!/bin/sh
# Runs database migrations then starts the application.
# Set SKIP_MIGRATIONS=true to skip (e.g. worker containers where web handles it).
set -e

if [ "${SKIP_MIGRATIONS}" != "true" ]; then
  echo "Running database migrations..."
  /app/bin/share_circle eval "ShareCircle.Release.migrate()"
fi

exec /app/bin/share_circle "$@"
