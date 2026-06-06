# 10 — Plano: CI/CD e DevOps (Hostinger)

> **Status:** ✅ Plano consolidado e alinhado com a arquitetura modular por contratos UDS/IPC.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular.

---

## 1. Contexto

A topologia Hostinger roda sob uma VM **KVM2** (~2 vCPU / 8 GB RAM) rodando Ubuntu. Com a refatoração modular, o backend foi dividido em N processos independentes (`data_postgres`, `data_redis`, `data_storage`, `worker`, `runtime_api`, `control_plane`, `messaging_gateway`). 

Este plano define a automação de build e entrega (CI/CD via GitHub Actions) e a orquestração destes múltiplos serviços de forma segura na VM Hostinger.

---

## 2. Orquestração e DevOps de Processos na Hostinger

### 2.1 Comunicação Segura via Unix Domain Sockets (UDS)
Como a comunicação interna entre os microsserviços ocorre nativamente via IPC sobre UDS (`crates/transport`), a superfície de segurança da VM Hostinger é extremamente reduzida:
- **Portas Fechadas**: Os serviços `data_postgres`, `data_redis` e `data_storage` não escutam em nenhuma porta TCP da rede. Eles abrem sockets locais Unix Domain no sistema de arquivos da VM (dentro de `/run/smartcore/` ou similar).
- **Sem Exposição**: Apenas a `runtime_api` e o `control_plane` podem expor portas de rede TCP locais (para gRPC/HTTP sob proxy reverso) ou gRPC-Web externa atrás de TLS configurado por Caddy/Nginx.

### 2.2 Orquestração no Host
O gerenciamento dos múltiplos executáveis binários na VM Hostinger é feito utilizando:
- **Systemd**: Serviços de sistema systemd individuais para cada processo de app do Cargo workspace. Isso garante auto-restart sob falhas e controle ordenado de dependências no boot (ex.: subir `data_redis` antes de `runtime_api`).
- **Env vars**: Systemd injeta chaves criptográficas (`JWT_SECRET`, credenciais S3) no runtime de cada processo a partir de arquivos `.env` locais na VM.

### 2.3 Rastreabilidade Distribuída Coletada no Host
A crate `observability` instalada em todos os microsserviços exporta traces no protocolo OTLP gRPC. Um único agente coletor (OpenTelemetry Collector) rodando na VM recebe as telemetrias e as consolida de forma centralizada nos datastores locais do Grafana Loki/Tempo, preservando a ramificação de spans de cada mensagem.

---

## 3. Pipelines de CI/CD (GitHub Actions)

O pipeline automatizado gerencia a integração dos microsserviços do Cargo workspace de forma integrada:

- **CI (Integração Contínua)**: Testes automatizados do workspace utilizando `cargo test --workspace` e linting `cargo clippy`. O build script do Cargo executa automaticamente a transpilação de schemas `.proto` para FlatBuffers para todos os testes.
- **CD (Entrega Contínua)**: Compilação otimizada (`cargo build --release`) em pipeline de build multi-stage e empacotamento em imagens Docker mínimas (ou deploy direto do binário Rust compilado para Systemd). O deploy executa o restart ordenado das unidades do systemd na VM Hostinger.

---

## 4. Testes e Validação de Implantação

- **Smoke Tests**: Chamadas básicas de gRPC/IPC para `/health` validam o status dos sockets UDS após cada deploy.
- **Rollback**: Binários da versão funcional anterior são mantidos como backup no Host, permitindo desvio imediato via re-apontamento de link simbólico Systemd.


