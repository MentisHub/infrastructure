# MentisHub

## Gerenciamento de Certificados

### Estrutura de Certificados

O projeto utiliza os seguintes certificados:

- **ca.crt / ca.key**: Certificate Authority (CA) raiz
- **server.crt / server.key**: Certificado do servidor (mTLS)
- **jwt_private.pem / jwt_public.pem**: Par de chaves RSA para JWT

### Gerar Certificados CA e Servidor (mTLS)

```bash
mkdir certs
openssl genrsa -out certs/ca.key 4096

openssl req -new -x509 -days 3650 -key certs/ca.key -out certs/ca.crt \
  -subj "/C=BR/ST=State/L=City/O=MentisHub/CN=MentisHub CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "subjectKeyIdentifier=hash" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl genrsa -out certs/server.key 4096

openssl req -new -key certs/server.key -out certs/server.csr \
  -subj "/C=BR/ST=State/L=City/O=MentisHub/CN=otel-collector"

openssl x509 -req -in certs/server.csr -CA certs/ca.crt -CAkey certs/ca.key \
  -CAcreateserial -out certs/server.crt -days 3650 -sha256 \
  -extfile <(printf "basicConstraints=CA:FALSE\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always,issuer\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,DNS:backend,DNS:otel-collector,DNS:superlink,IP:127.0.0.1")

rm certs/server.csr certs/ca.srl
```

### Gerar Chaves RSA para JWT

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
  -out certs/jwt_private.pem

openssl rsa -pubout -in certs/jwt_private.pem -out certs/jwt_public.pem
```

### Verificar Certificados

```bash
openssl x509 -in certs/ca.crt -text -noout

openssl x509 -in certs/server.crt -text -noout

openssl verify -CAfile certs/ca.crt certs/server.crt

openssl rsa -in certs/jwt_private.pem -check
openssl rsa -pubin -in certs/jwt_public.pem -text -noout
```

### Permissões de Arquivos

```bash
chmod 600 certs/*.key certs/jwt_private.pem
chmod 644 certs/*.crt certs/jwt_public.pem
```

## Desenvolvimento

### Iniciar Ambiente de Desenvolvimento

```bash
docker compose -f docker/compose/docker-compose.dev.yml --env-file docker/env/.env.dev up -d

docker-compose -f docker/compose/docker-compose.dev.yml logs -f
```
