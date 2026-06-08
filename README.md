# Smart Core Assistant v2

O **Smart Core Assistant v2** é um assistente digital inteligente, modular e de alta performance construído em Rust. Ele adota uma arquitetura orientada a serviços distribuídos que se comunicam através de gRPC (Tonic/h2c) e filas de mensagens baseadas em Redis.

---

## 1. Arquitetura de Serviços

O sistema é dividido em 7 serviços independentes executados no lado do servidor (Cargo Workspace):

*   **`runtime_api`**: O gateway de entrada gRPC que expõe a API para os clientes.
*   **`control_plane`**: Orquestrador central do estado do assistente e regras de negócio.
*   **`messaging_gateway`**: Gerencia o tráfego de entrada e saída de mensagens (webhooks, integrações).
*   **`worker`**: Processa tarefas em segundo plano assíncronas e demoradas.
*   **`data_postgres`**: Abstração de persistência relacional (PostgreSQL + pgvector).
*   **`data_redis`**: Interface para cache rápido e barramento de eventos/mensagens (Redis).
*   **`data_storage`**: Abstração para armazenamento de arquivos e mídia (compatível com S3/MinIO/Cloudflare R2).

---

## 2. Infraestrutura e Ambientes de Deploy

O provisionamento é realizado em um servidor VPS **Hostinger KVM2** (Ubuntu 22.04 LTS). O fluxo de trabalho de deploy é totalmente automatizado através do **GitHub Actions** rodando em um **Self-Hosted Runner** nativo no próprio servidor (otimizando o tempo de build do Rust com cache de dependências).

### Ambientes

| Aspecto | Desenvolvimento (DEV) | Produção (PROD) |
|---|---|---|
| **Trigger** | Push na branch `dev` | Tag semântica `v*.*.*` |
| **Banco de Dados** | `smartcore_v2_dev` | `smartcore_v2` |
| **Redis DB** | DB 1 | DB 0 |
| **Sockets UDS** | `/run/smartcore-dev/` | `/run/smartcore/` |
| **Caminho dos Binários** | `/opt/smartcore/dev/bin/` | `/opt/smartcore/prod/releases/<tag>/` |
| **Porta gRPC** | `8090` | `8080` |
| **Domínio API** | `dev-api.smartcoreassistant.com.br` | `api.smartcoreassistant.com.br` |
| **Aprovação Manual** | Não (Automático) | Sim (Revisão obrigatória via GitHub) |

---

## 3. Fluxo de Trabalho e Workflows de CI/CD

O repositório conta com os seguintes workflows configurados em `.github/workflows/`:

1.  **`ci.yml`**: Disparado em qualquer push (todas as branches) e em Pull Requests para `main`/`dev`. Realiza validações de formatação (`rustfmt`), análises estáticas (`clippy`), verificação de queries de banco em modo offline (`sqlx prepare --check`) e testes integrados.
2.  **`deploy-dev.yml`**: Compila a workspace em modo release, instala os binários no diretório de desenvolvimento e reinicia os serviços systemd correspondentes.
3.  **`deploy-prod.yml`**: Realiza o backup automático do banco de dados de produção, compila os binários em modo release, versiona o deploy sob uma pasta de release específica (ex: `/opt/smartcore/prod/releases/v0.1.0`), atualiza o symlink `current` e reinicia os serviços em rolling restart. Também empacota o cliente Flutter para Windows e o anexa na GitHub Release criada automaticamente.
4.  **`pr-to-main.yml`**: Abre um Pull Request automático da branch `dev` para a `main` após a conclusão com sucesso do deploy de produção para manter o histórico de branches sincronizado.

---

## 4. Backup, Rollback e Manutenção

### Backup de Banco de Dados
A cada deploy em produção, um backup físico (.dump) é gerado via `pg_dump` no PostgreSQL e armazenado no servidor. O pipeline mantém automaticamente apenas os **últimos 5 backups** para evitar esgotamento de disco.

### Mecanismo de Rollback
*   **Automático (Falha no Deploy)**: Se o smoke test falhar após a cópia dos binários no pipeline do GitHub Actions, o workflow de produção desfaz a alteração do symlink `current` para a versão anterior (`PREV_RELEASE`), reinicia os serviços e remove a release problemática.
*   **Manual (Via SSH)**: Se for necessário reverter para uma release específica no servidor, mude o symlink e reinicie o systemd:
    ```bash
    ln -sfn /opt/smartcore/prod/releases/<tag_anterior> /opt/smartcore/prod/releases/current
    sudo systemctl restart smartcore-prod.target
    ```

### Crons de Manutenção (`/etc/cron.d/smartcore`)
Tarefas automatizadas rodam semanalmente no servidor para manter a saúde do sistema:
*   Limpeza periódica do diretório `target` de build do runner para economizar espaço em disco.
*   Pruning de imagens e containers Docker antigos/órfãos.
*   Compactação e limpeza de logs do journald com retenção máxima de 7 dias.

---

## 5. Observabilidade (LGTM Stack)

A pilha de monitoramento e telemetria é executada via Docker Compose (`docker/compose/observability.yml`):

*   **Grafana** (`https://grafana.smartcoreassistant.com.br`): Visualização centralizada.
*   **Loki / Promtail**: Agregação e indexação de logs de containers Docker e dos serviços de sistema.
*   **Tempo**: Rastreamento distribuído de requisições gRPC (Traces).
*   **Prometheus**: Coleta de métricas de uso de recursos e saúde do sistema.
*   **OpenTelemetry Collector**: Ponto centralizado para recebimento de logs, traces e métricas da aplicação Rust.

---

## 6. Políticas de Segurança Aplicadas

1.  **Firewall (UFW)**: Todas as portas de serviços internos (banco de dados, Redis, gRPC direto) estão bloqueadas para tráfego externo. Apenas as portas `22` (SSH), `80` (HTTP) e `443` (HTTPS/UDP para HTTP/3) estão expostas publicamente.
2.  **Proxy Reverso (Caddy)**: O Caddy atua como reverse proxy na borda, gerenciando automaticamente os certificados TLS (Let's Encrypt) e expondo a API de forma segura. O tráfego gRPC Tonic é roteado de forma nativa utilizando HTTP/2 (`h2c`).
3.  **Variáveis Sensíveis (`.env`)**: Arquivos de configuração de ambiente no servidor possuem permissão exclusiva de leitura e escrita (`chmod 600`) para o usuário de execução do sistema (`smartcore`), evitando qualquer exposição acidental de credenciais.
