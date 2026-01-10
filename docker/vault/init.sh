#!/bin/sh
set -e

KEYS_FILE="/vault/file/init-keys.json"
PKI_FLAG="/vault/file/.pki_initialized"

vault status 2>&1 | grep -q "Initialized.*true" || \
  vault operator init -key-shares=1 -key-threshold=1 -format=json > "$KEYS_FILE"

if vault status 2>&1 | grep -q "Sealed.*true"; then
  UNSEAL_KEY=$(awk -F'"' '/"unseal_keys_b64"/{getline; print $2}' "$KEYS_FILE")
  vault operator unseal "$UNSEAL_KEY"
fi

export VAULT_TOKEN=$(awk -F'"' '/"root_token"/{print $4}' "$KEYS_FILE")

if [ ! -f "$PKI_FLAG" ]; then
  vault audit enable file file_path=/vault/logs/audit.log

  vault secrets enable -path=pki pki
  vault secrets tune -max-lease-ttl=87600h pki

  vault write -format=json pki/root/generate/internal \
    common_name="MentisHub Root CA" \
    issuer_name="root-ca" \
    ttl=87600h \
    key_bits=4096 \
    | jq -r '.data.certificate' > /vault/certs/root-ca.crt

  vault write pki/config/urls \
    issuing_certificates="${VAULT_ADDR}/v1/pki/ca" \
    crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

  vault secrets enable -path=pki_int pki
  vault secrets tune -max-lease-ttl=43800h pki_int

  vault write -format=json pki_int/intermediate/generate/internal \
    common_name="MentisHub Intermediate CA" \
    issuer_name="intermediate-ca" \
    key_bits=4096 \
    | jq -r '.data.csr' > /tmp/pki_intermediate.csr

  vault write -format=json pki/root/sign-intermediate \
    issuer_ref="root-ca" \
    csr=@/tmp/pki_intermediate.csr \
    format=pem_bundle \
    ttl=43800h \
    | jq -r '.data.certificate' > /tmp/intermediate.cert.pem

  vault write pki_int/intermediate/set-signed \
    certificate=@/tmp/intermediate.cert.pem

  vault write pki_int/config/urls \
    issuing_certificates="${VAULT_ADDR}/v1/pki_int/ca" \
    crl_distribution_points="${VAULT_ADDR}/v1/pki_int/crl"

  vault write pki_int/config/crl \
    expiry="72h" \
    disable=false

  vault write pki_int/roles/otel-collector \
    allowed_domains="otel-collector,otel-collector.mentishub.local" \
    allow_bare_domains=true \
    allow_subdomains=true \
    max_ttl=2160h \
    ttl=720h \
    key_bits=2048 \
    key_type=rsa \
    require_cn=true \
    generate_lease=true

  vault write pki_int/roles/platform-backend \
    allowed_domains="platform-backend.mentishub.local" \
    allow_bare_domains=true \
    allow_subdomains=true \
    max_ttl=2160h \
    ttl=720h \
    key_bits=2048 \
    key_type=rsa \
    require_cn=true \
    generate_lease=true

  vault policy write otel-collector-policy - <<EOF
path "pki_int/issue/otel-collector" {
  capabilities = ["create", "update"]
}
path "pki_int/cert/ca" {
  capabilities = ["read"]
}
path "pki/cert/ca" {
  capabilities = ["read"]
}
EOF

  vault policy write platform-backend-policy - <<EOF
path "pki_int/issue/platform-backend" {
  capabilities = ["create", "update"]
}
path "pki_int/cert/ca" {
  capabilities = ["read"]
}
path "pki/cert/ca" {
  capabilities = ["read"]
}
path "pki/root/sign-intermediate" {
  capabilities = ["create", "update"]
}
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "pki_org_*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
path "pki_org_*/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

  vault auth enable approle 2>/dev/null || true

  vault write auth/approle/role/otel-collector \
    token_policies="otel-collector-policy" \
    token_ttl=1h \
    token_max_ttl=4h \
    bind_secret_id=true

  vault read -format=json auth/approle/role/otel-collector/role-id | jq -r '.data.role_id' > /vault/certs/otel-role-id
  vault write -format=json -f auth/approle/role/otel-collector/secret-id | jq -r '.data.secret_id' > /vault/certs/otel-secret-id
  chmod 644 /vault/certs/otel-role-id /vault/certs/otel-secret-id

  vault write auth/approle/role/platform-backend \
    token_policies="platform-backend-policy" \
    token_ttl=1h \
    token_max_ttl=4h \
    bind_secret_id=true \
    secret_id_ttl=0 \
    secret_id_num_uses=0

  vault read -format=json auth/approle/role/platform-backend/role-id | jq -r '.data.role_id' > /vault/certs/platform-role-id
  vault write -format=json -f auth/approle/role/platform-backend/secret-id | jq -r '.data.secret_id' > /vault/certs/platform-secret-id
  chmod 644 /vault/certs/platform-role-id /vault/certs/platform-secret-id

  mkdir -p /vault/certs /vault/logs
  chmod 755 /vault/certs

  vault read -format=json pki_int/cert/ca | jq -r '.data.certificate' > /vault/certs/ca.crt
  chmod 644 /vault/certs/ca.crt /vault/certs/root-ca.crt

  rm -f /tmp/pki_intermediate.csr /tmp/intermediate.cert.pem

  touch "$PKI_FLAG"
fi

vault read -format=json pki_int/cert/ca | jq -r '.data.certificate' > /vault/certs/ca.crt
