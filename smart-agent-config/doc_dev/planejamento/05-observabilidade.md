# 05 — Observabilidade (logs, métricas e traces)

> **Status:** Concluída (Fase 0 e Fase 1). **Fundação transversal** implementada e em uso.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular. Integração com a crate `contracts` e o barramento `transport::bus`.

---

## 1. Objetivo e princípio

Centralizar a **instrumentação** (logs estruturados, métricas e traces) em uma crate (`server/crates/observability`) reusável por todos os binários, e definir o **stack de coleta/visualização** (LGTM self-hosted).

> **Princípio inviolável:** **todo módulo emite log estruturado + erro rastreável + trace desde o dia 1.** Nada de `println!`/erro silencioso. Cada log/erro carrega correlação por **`tenant_id`** e **`trace_id`**, permitindo seguir uma mensagem do webhook até a resposta. A organização dos **erros** é tratada na crate dedicada [06-tratamento-de-erros.md](./06-tratamento-de-erros.md), que se integra a esta (todo erro é logado com seu `error_code` + correlação).

A crate `observability` é pré-requisito para todos os serviços, garantindo rastreabilidade fim-a-fim da arquitetura distribuída.

## 2. Decisões travadas

| # | Tema | Decisão | Racional |
|---|------|---------|----------|
| Obs1 | Base de instrumentação | **`tracing` + `tracing-subscriber`** | Recomendação do projeto OpenTelemetry para Rust; `Span` casa com spans OTel |
| Obs2 | Export | **OTLP** via `tracing-opentelemetry` + `opentelemetry-otlp` | Padrão neutro; o Collector roteia para Loki/Prometheus/Tempo |
| Obs3 | Hospedagem do stack | **LGTM self-hosted na mesma VM** (Docker Compose) | Custo zero extra; Loki indexa só labels (leve). Atenção ao orçamento de RAM da KVM2 |
| Obs4 | Formato de log | **JSON estruturado** com campos padrão (`service`, `env`, `tenant_id`, `trace_id`) | Consulta/correlação; ordem de adoção métricas→logs→traces |

---

## 3. Crate `observability` (instrumentação Rust)

- `init_telemetry(service_name, env)` reusável pelos binários: instala o subscriber JSON, nível por `RUST_LOG`/env, e o exporter OTLP para o Collector.
- **Span com `tenant_id`** (helper/macro) — alinhado ao `Envelope` gerado em `contracts`.
- **Propagação W3C TraceContext (`traceparent`)**: Injetada no envelope unificado `Envelope` da crate `contracts`. Os metadados de trace são transportados nativamente em cada mensagem RPC via Unix Domain Sockets (UDS) / FlatBuffers e propagados pelo barramento de eventos Redis Streams (`transport::bus`) entre a `runtime_api`, `worker` e serviços de dados.
- **Desacoplamento do Log de Auditoria**: O `AuditLogger` foi desacoplado do acesso direto ao banco. Ele gera mensagens de auditoria estruturadas e as publica de forma assíncrona no barramento Redis Streams (`transport::bus`). O microserviço `data_postgres` consome esses eventos para persistir os logs de auditoria no PostgreSQL, eliminando a dependência síncrona do Postgres na biblioteca de observabilidade.
- **Métricas** (`metrics`/`opentelemetry`): contadores de requisições, latência de processamento RPC por UDS, chamadas gRPC, lag de mensagens no event bus e contadores de erros tipados por `error_code` (integrado com `error_core`).
- **Integração com erros:** expõe hooks onde a crate `error_core` registra e categoriza erros estruturados, injetando automaticamente campos como `error_code`, `severity`, `tenant_id` e `trace_id` nos logs.

## 4. Stack LGTM self-hosted — Fase 9

`docker/compose/observability.yml` (novo), espelhando o tutorial da Hostinger:

- **OpenTelemetry Collector** (OTLP gRPC 4317 / HTTP 4318) — ponto de entrada neutro, roteia métricas→Prometheus, logs→Loki, traces→Tempo.
- **Loki** (3100), **Prometheus** (9090), **Tempo** (3200), **Grafana** (3000).
- **Promtail/Grafana Alloy** (logs de container) + **Node Exporter** + **cAdvisor** (host/containers).
- Datasources e dashboards **provisionados** (as-code em `docker/observability/`).
- **Retenção curta** (logs 7–14 dias, traces 7 dias) por restrição da KVM2.

### Orçamento de recursos (KVM2)
Tabela de RAM por componente; LGTM completo + dados + apps pressiona 8 GB → limites `deploy.resources` apertados e gatilho de upgrade para KVM4 (16 GB) quando os apps Rust subirem. Loki indexa só labels (leve) — ponto a favor.

## 5. Health checks e alertas

- `/health` (liveness/readiness) e `/metrics` em cada binário Rust.
- **Alertmanager** (ou alertas do Grafana): serviço down, taxa de erro alta (por `error_code`), memória/disco, lag do bus. Canal inicial: e-mail/Telegram.

## 6. Segurança da telemetria

- Grafana atrás do proxy reverso (TLS + auth); portas do Collector/Loki/Prometheus/Tempo **não expostas** publicamente (rede Docker interna).
- **Não logar segredos/PII** — sanitizar payloads do WhatsApp e tokens (cruza com a diretriz de segurança e o doc 09).

## 7. Mapeamento para fases

| Entrega | Fase | Status | Escopo |
|---|---|---|---|
| Crate `observability` (logs estruturados, spans, telemetria) | **Fase 0** | **Concluído (✅)** | Crate base para todos os microsserviços e bibliotecas |
| Propagação `traceparent` no `Envelope` + Auditoria Assíncrona no Bus | **Fase 1** | **Concluído (✅)** | Envelopamento de rastreio em contratos e envio de logs de auditoria via Redis Streams |
| Stack LGTM + tracing distribuído + dashboards | **Fase 9** | Planejado | Stack de monitoramento na VM Hostinger |

## 8. DoD

- Binário emite log JSON estruturado com nível configurável.
- Trace de uma mensagem webhook→resposta visível no Tempo, correlacionado por `tenant_id`/`trace_id`.
- Erros aparecem nos logs com `error_code` (integração com doc 06).
- Dashboards provisionados sobem com o compose.

## 9. Próximo passo

A infraestrutura básica de observabilidade e propagação está concluída e integrada com a crate de erros ([06-tratamento-de-erros.md](./06-tratamento-de-erros.md)) e a de contratos ([07-crate-contracts.md](./07-crate-contracts.md)). O stack LGTM completo na Hostinger será configurado na Fase 9.

---

*Documento de observabilidade consolidado e revisado. Referências adicionais para implantação no host podem ser encontradas em [10-plano-cicd-devops.md](./10-plano-cicd-devops.md).*

---

*Fim do documento.*
