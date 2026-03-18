# MentisHub

## Gerenciamento de Certificados

### Estrutura de Certificados

Todos os certificados ficam em `certs/` na raiz do monorepo e são montados nos containers via volume.

| Arquivo | Uso |
|---|---|
| `ca.crt` / `ca.key` | CA raiz — assina todos os outros certificados |
| `server.crt` / `server.key` | TLS do SuperLink (gRPC 9091–9093) e mTLS do OTEL Collector (HTTP 4318); também usado como **certificado cliente** do backend ao conectar no SuperLink |

### Gerar Certificados CA e Servidor (mTLS)

```bash
mkdir -p certs

openssl genrsa -out certs/ca.key 4096

openssl req -new -x509 -days 3650 -sha256 -key certs/ca.key -out certs/ca.crt \
  -subj "/C=BR/ST=State/L=City/O=MentisHub/CN=MentisHub CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "subjectKeyIdentifier=hash" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl genrsa -out certs/server.key 4096

openssl req -new -key certs/server.key -out certs/server.csr \
  -subj "/C=BR/ST=State/L=City/O=MentisHub/CN=mentishub"

openssl x509 -req -in certs/server.csr -CA certs/ca.crt -CAkey certs/ca.key \
  -CAcreateserial -out certs/server.crt -days 3650 -sha256 \
  -extfile <(printf "basicConstraints=CA:FALSE\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=DNS:localhost,DNS:backend,DNS:otel-collector,DNS:superlink,IP:127.0.0.1")

rm certs/server.csr certs/ca.srl
```

> **Nota:** `extendedKeyUsage=serverAuth,clientAuth` é necessário porque `server.crt` é usado tanto como certificado TLS do servidor (SuperLink, OTEL Collector) quanto como certificado cliente do backend ao se conectar ao SuperLink via mTLS.

### Verificar Certificados

```bash
openssl x509 -in certs/ca.crt -text -noout
openssl x509 -in certs/server.crt -text -noout

openssl verify -CAfile certs/ca.crt certs/server.crt
```

## Desenvolvimento

### Iniciar Ambiente de Desenvolvimento

```bash
git submodule update --init --recursive

docker compose -f docker/compose/docker-compose.dev.yml --env-file docker/env/.env.dev up -d

docker compose -f docker/compose/docker-compose.dev.yml logs -f
```
