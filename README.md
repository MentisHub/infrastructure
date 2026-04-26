# MentisHub

Plataforma de gerenciamento de aprendizado federado com observabilidade baseada em OpenTelemetry.

## Pré-requisitos

- Docker com plugin `docker compose`
- `git`, `openssl`, `curl`
- Linux, macOS ou Windows com WSL2

## Início Rápido

```bash
./init.sh
```

O script inicializa os submódulos, gera os certificados, sobe todos os serviços, popula o banco, constrói e inicia 3 SuperNodes e dispara uma execução de treinamento federado. Ao final, exibe a URL de monitoramento.
