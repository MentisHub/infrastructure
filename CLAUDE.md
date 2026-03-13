# CLAUDE.md

## Project

MentisHub is a federated learning platform for distributed AI collaboration across institutions. Monorepo with Git submodules.

**Submodules:** `platform/` (NestJS + Next.js), `fl-app/` (Flower/PyTorch), `flower/` (forked Flower framework).

> Each submodule has its own `CLAUDE.md` with component-specific context.

## Quick Start

```bash
git submodule update --init --recursive
docker compose -f docker/compose/docker-compose.dev.yml --env-file docker/env/.env.dev up -d
```

## Key Ports

| Service | Port |
|---|---|
| Backend (NestJS) | 3000 |
| Frontend (Next.js) | 3001 |
| Supabase Auth | 9999 |
| Supabase Studio | 3005 |
| Supabase REST | 3004 |
| Grafana | 3006 |
| Flower SuperLink | 9091–9093 |
| OTEL Collector | 4317 (gRPC), 4318 (HTTP) |
| Prometheus | 9090 |

## Infrastructure

- **Observability:** OTEL Collector → Prometheus → Grafana (all pre-provisioned)
- **Auth (Supabase):** PostgreSQL + GoTrue + Kong gateway; init scripts in `docker/supabase/`
- **Storage:** Supabase Storage with local file backend; FAB bundles stored here
- **Network:** all services on `mentishub-network`; always use service hostnames, never `localhost`

## Architecture Constraints

- **Platform ↔ Flower:** orchestration via gRPC to SuperLink only — never direct HTTP
- **Observability:** instrument everything → OTEL Collector → Prometheus → Grafana

## Notes

- `flower/` is a fork; check branch `mentishub` before touching proto generation
- FAB (Federated Application Bundle) = packaged fl-app deployed to SuperLink for training runs
