---
"share_circle": minor
---

Phase 7: Polish & launch prep — security hardening, release tooling, load tests, documentation

- Security headers: CSP, Referrer-Policy, and Permissions-Policy added to all browser responses via put_secure_browser_headers; HSTS already enforced via force_ssl in prod
- Added sobelow (Phoenix SAST) and mix_audit (dependency CVE scanning) to deps and precommit alias
- ShareCircle.Release module for running migrations from a Docker release (no Mix required)
- Docker entrypoint.sh auto-runs migrations on app container startup; worker sets SKIP_MIGRATIONS=true
- k6 load test scripts in test/load/: WebSocket connections (1000 concurrent), chat throughput (100 msg/s), media upload two-phase flow
- docs/CONFIGURATION.md: complete environment variable reference for self-hosters including quotas, storage, email, push, and operations runbook
- CLAUDE.md updated to reflect implemented state (was still marked pre-implementation)
