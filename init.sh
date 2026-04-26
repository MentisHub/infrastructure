#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[init]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC} $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# --- Prerequisites -----------------------------------------------------------

for cmd in docker git openssl curl; do
  command -v "$cmd" &>/dev/null || die "'$cmd' not found. Please install it before running this script."
done

docker compose version &>/dev/null || die "'docker compose' plugin not found."

# --- Submodules --------------------------------------------------------------

info "Initializing git submodules..."
git -C "$REPO_ROOT" submodule update --init --recursive

# --- Certificates ------------------------------------------------------------

CERTS_DIR="$REPO_ROOT/certs"

if [[ -f "$CERTS_DIR/ca.crt" && -f "$CERTS_DIR/server.crt" ]]; then
  info "Certificates already exist, skipping generation."
else
  info "Generating CA and server certificates..."
  mkdir -p "$CERTS_DIR"

  openssl genrsa -out "$CERTS_DIR/ca.key" 4096 2>/dev/null

  openssl req -new -x509 -days 3650 -sha256 \
    -key "$CERTS_DIR/ca.key" -out "$CERTS_DIR/ca.crt" \
    -subj "/C=BR/ST=State/L=City/O=MentisHub/CN=MentisHub CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "subjectKeyIdentifier=hash" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

  openssl genrsa -out "$CERTS_DIR/server.key" 4096 2>/dev/null

  openssl req -new -key "$CERTS_DIR/server.key" -out "$CERTS_DIR/server.csr" \
    -subj "/C=BR/ST=State/L=City/O=MentisHub/CN=mentishub" 2>/dev/null

  openssl x509 -req \
    -in "$CERTS_DIR/server.csr" \
    -CA "$CERTS_DIR/ca.crt" -CAkey "$CERTS_DIR/ca.key" -CAcreateserial \
    -out "$CERTS_DIR/server.crt" -days 3650 -sha256 \
    -extfile <(printf "basicConstraints=CA:FALSE\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=DNS:localhost,DNS:backend,DNS:otel-collector,DNS:superlink,IP:127.0.0.1") 2>/dev/null

  rm -f "$CERTS_DIR/server.csr" "$CERTS_DIR/ca.srl"
  info "Certificates generated."
fi

# --- Platform ----------------------------------------------------------------

COMPOSE="docker compose -f $REPO_ROOT/docker/compose/docker-compose.dev.yml --env-file $REPO_ROOT/docker/env/.env.dev"

info "Starting platform services..."
$COMPOSE up -d --build

# --- Wait for backend health -------------------------------------------------

info "Waiting for platform backend to be healthy..."
TIMEOUT=180
ELAPSED=0
until $COMPOSE ps platform-backend | grep -q "healthy" 2>/dev/null; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    warn "Backend did not become healthy within ${TIMEOUT}s. Check logs with:"
    echo "  docker compose -f docker/compose/docker-compose.dev.yml logs platform-backend"
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

# --- Build SuperNode image ---------------------------------------------------

info "Building SuperNode image (mentishub/fl-app:latest)..."
docker build \
  -f "$REPO_ROOT/fl-app/docker/Dockerfile" \
  -t mentishub/fl-app:latest \
  "$REPO_ROOT"

# --- Seed database -----------------------------------------------------------

info "Seeding database..."
SEED_OUTPUT=$(docker exec platform-backend sh -c "cd /usr/src/app && pnpm db:seed" 2>&1)
echo "$SEED_OUTPUT"

# --- Parse seed output -------------------------------------------------------

info "Parsing seed output..."

ACCESS_TOKEN=$(printf '%s\n' "$SEED_OUTPUT" | awk '
  /\[AUTH\].*user1@mentishub\.dev/ { found=1; next }
  found && /access:/ { print $NF; exit }
')

PENDING_LINE=$(printf '%s\n' "$SEED_OUTPUT" | grep -n '\[RUN:PENDING\]' | head -1 | cut -d: -f1)
RUN_ID=$(printf '%s\n' "$SEED_OUTPUT" | sed -n "${PENDING_LINE}p" \
  | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
PROJECT_ID=$(printf '%s\n' "$SEED_OUTPUT" | head -n "$PENDING_LINE" \
  | grep '\[PROJECT\]' | tail -1 \
  | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tail -1)

NODE_PSKS=()
while IFS= read -r psk; do
  NODE_PSKS+=("$psk")
done < <(printf '%s\n' "$SEED_OUTPUT" | awk -v start="$PENDING_LINE" '
  NR <= start { next }
  /\[RUN:/ { exit }
  /\[NODE:CREATED\]/ {
    sub(/.*psk: /, ""); print; count++
    if (count >= 3) exit
  }
')

[[ -z "$ACCESS_TOKEN" ]]     && die "Failed to parse user1 access token from seed output"
[[ -z "$PROJECT_ID" ]]       && die "Failed to parse project ID from seed output"
[[ -z "$RUN_ID" ]]           && die "Failed to parse pending run ID from seed output"
[[ ${#NODE_PSKS[@]} -lt 3 ]] && die "Expected at least 3 CREATED node PSKs, got ${#NODE_PSKS[@]}"

info "Project:  $PROJECT_ID"
info "Run:      $RUN_ID"

# --- Start SuperNodes --------------------------------------------------------

info "Starting SuperNode containers..."
for i in 1 2 3; do
  psk="${NODE_PSKS[$((i-1))]}"
  docker rm -f "supernode-${i}" 2>/dev/null || true
  docker run -d \
    --name "supernode-${i}" \
    --network mentishub-network \
    -e NODE_PSK="$psk" \
    -e OTEL_EXPORTER_OTLP_ENDPOINT="otel-collector:4318" \
    -v "supernode-${i}-certs:/app/certs" \
    mentishub/fl-app:latest \
    flower-supernode \
      --superlink superlink:9092 \
      --root-certificates /home/app/.flwr/certificates/ca.crt \
      --auth-supernode-private-key /app/certs/ec_private.key
  info "SuperNode ${i} started"
done

# --- Wait for SuperNodes to activate -----------------------------------------

info "Waiting for SuperNodes to activate and connect (up to 120s)..."
TIMEOUT=120
ELAPSED=0
HEALTHY=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  HEALTHY=0
  for i in 1 2 3; do
    status=$(docker inspect --format='{{.State.Health.Status}}' "supernode-${i}" 2>/dev/null || echo "none")
    [[ "$status" == "healthy" ]] && HEALTHY=$((HEALTHY + 1))
  done
  [[ $HEALTHY -ge 3 ]] && break
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [[ $HEALTHY -lt 3 ]]; then
  warn "$HEALTHY/3 SuperNodes are healthy after ${TIMEOUT}s — proceeding anyway."
else
  info "All 3 SuperNodes are healthy."
fi

# --- Deploy ServerApp --------------------------------------------------------

info "Deploying ServerApp for training run..."
DEPLOY_HTTP=$(curl -s -o /tmp/mh_deploy.json -w "%{http_code}" -X POST \
  "http://localhost:3000/v1/projects/$PROJECT_ID/trainings/$RUN_ID/deploy" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

if [[ "$DEPLOY_HTTP" == "201" ]]; then
  info "ServerApp deployed successfully."
else
  warn "Deploy returned HTTP $DEPLOY_HTTP: $(cat /tmp/mh_deploy.json 2>/dev/null)"
  warn "Retry manually: POST http://localhost:3000/v1/projects/$PROJECT_ID/trainings/$RUN_ID/deploy"
fi

# --- Wait for run to reach READY state ---------------------------------------

info "Waiting for run to reach READY state (up to 60s)..."
TIMEOUT=60
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  RUN_STATUS=$(curl -s \
    "http://localhost:3000/v1/projects/$PROJECT_ID/trainings/$RUN_ID" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    | grep -oE '"status":"[A-Z_]+"' | head -1 | sed 's/"status":"//;s/"//')
  [[ "$RUN_STATUS" == "READY" ]] && break
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [[ "$RUN_STATUS" != "READY" ]]; then
  warn "Run status is '$RUN_STATUS' (expected READY) — attempting to start anyway."
fi

# --- Start training -----------------------------------------------------------

info "Starting training run..."
RUN_HTTP=$(curl -s -o /tmp/mh_run.json -w "%{http_code}" -X POST \
  "http://localhost:3000/v1/projects/$PROJECT_ID/trainings/$RUN_ID/run" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

if [[ "$RUN_HTTP" == "201" ]]; then
  info "Training started successfully."
else
  warn "Run returned HTTP $RUN_HTTP: $(cat /tmp/mh_run.json 2>/dev/null)"
  warn "Retry manually: POST http://localhost:3000/v1/projects/$PROJECT_ID/trainings/$RUN_ID/run"
fi

# --- Done --------------------------------------------------------------------

echo ""
info "Setup complete."
echo ""
echo "  Monitoring:  http://localhost:3001/projects/$PROJECT_ID/monitoring?run=$RUN_ID"
echo ""
echo "  Frontend:    http://localhost:3001"
echo "  Backend:     http://localhost:3000/docs"
echo "  Supabase:    http://localhost:8000"
echo "  Grafana:     http://localhost:3006"
echo "  Prometheus:  http://localhost:9090"
echo ""
info "Logs: docker compose -f docker/compose/docker-compose.dev.yml logs -f"
