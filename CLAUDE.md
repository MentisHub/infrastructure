# CLAUDE.md

## Project

MentisHub is a federated learning platform for distributed AI collaboration across institutions. Monorepo with Git submodules.

**Submodules:** `platform/` (NestJS + Next.js), `fl-app/` (flower application), `flower/` (forked Flower framework).

## Key Ports

| Service | Port |
|---|---|
| Backend (NestJS) | 3000 |
| Frontend (Next.js) | 3001 |
| Supabase Kong | 8000 |
| Flower SuperLink | 9091–9093 |
| OTEL Collector | 4317 (gRPC), 4318 (HTTP) |
| Prometheus | 9090 |

## Certificates

| Cert | Usage |
|---|---|
| ca.crt / ca.key | Root CA, signs node certificates via CertificateService |
| server.crt / server.key | SuperLink TLS and OTEL Collector mTLS; backend client auth to SuperLink |

## Infrastructure

File: docker/compose/docker-compose.dev.yml
- **Observability:** FABs -> OTEL Collector → Prometheus
- **Auth (Supabase):** PostgreSQL + GoTrue + Kong gateway; init scripts in `docker/supabase/`

## Architecture Constraints

- **Platform ↔ Flower:** start and stop runs, create federations via gRPC to SuperLink

## Notes

- FAB (Federated Application Bundle) = packaged fl-app (flwr build) deployed to platform for training runs
