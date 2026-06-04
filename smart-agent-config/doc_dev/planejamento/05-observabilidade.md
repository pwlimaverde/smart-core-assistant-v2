# 05 — Observabilidade (logs, métricas e traces)

> **Status:** Planejamento (a implementar). **Fundação transversal** — todo
> módulo depende dela desde o dia 1.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Extraído e aprofundado a partir do plano-mãe operacional
> ([10-plano-cicd-devops.md](./10-plano-cicd-devops.md)) por decisão de **subir a
> observabilidade na ordem** — antes do storage. Corresponde à **Etapa 0.4**
> (mínimo) e **9.1** (completo) de
> [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).

---

## 1. Objetivo e princípio

Centralizar a **instrumentação** (logs estruturados, métricas e traces) em uma
crate (`server/crates/observability`) reusável por todos os binários, e definir o
**stack de coleta/visualização** (LGTM self-hosted).

> **Princípio inviolável:** **todo módulo emite log estruturado + erro rastreável
> + trace desde o dia 1.** Nada de `println!`/erro silencioso. Cada log/erro
> carrega correlação por **`tenant_id`** e **`trace_id`**, permitindo seguir uma
> mensagem do webhook até a resposta. A organização dos **erros** é tratada na
> crate dedicada [06-tratamento-de-erros.md](./06-tratamento-de-erros.md), que se
> integra a esta (todo erro é logado com seu `error_code` + correlação).

Por isso esta crate vem **antes** do storage e dos demais módulos de feature: é
pré-requisito para construir qualquer coisa de forma rastreável.

## 2. Decisões travadas

| # | Tema | Decisão | Racional |
|---|------|---------|----------|
| Obs1 | Base de instrumentação | **`tracing` + `tracing-subscriber`** | Recomendação do projeto OpenTelemetry para Rust; `Span` casa com spans OTel |
| Obs2 | Export | **OTLP** via `tracing-opentelemetry` + `opentelemetry-otlp` | Padrão neutro; o Collector roteia para Loki/Prometheus/Tempo |
| Obs3 | Hospedagem do stack | **LGTM self-hosted na mesma VM** (Docker Compose) | Custo zero extra; Loki indexa só labels (leve). Atenção ao orçamento de RAM da KVM2 |
| Obs4 | Formato de log | **JSON estruturado** com campos padrão (`service`, `env`, `tenant_id`, `trace_id`) | Consulta/correlação; ordem de adoção métricas→logs→traces |

> **Alternativas registradas (não adotadas):** Grafana Cloud (free tier) e VPS
> dedicada para observabilidade.

## 3. Crate `observability` (instrumentação Rust) — F0.4

- `init_telemetry(service_name, env)` reusável pelos binários: instala o
  subscriber JSON, nível por `RUST_LOG`/env, e o exporter OTLP para o Collector.
- **Span com `tenant_id`** (helper/macro) — alinhado ao `TenantEnvelope`
  (`infrastructure_redis`/`contracts`).
- **Propagação W3C TraceContext** entre serviços (gateway → bus → worker →
  ia_engine via metadata gRPC) para rastrear ponta-a-ponta.
- **Métricas** (`metrics`/`opentelemetry`): mensagens recebidas, latência de
  processamento, chamadas gRPC ao `ia_engine`, lag de consumer group do Redis,
  contadores de erro **por `error_code`** (ver doc 06).
- **Integração com erros:** expõe o ponto onde a crate `error_core` registra cada
  erro (campos `error_code`, `severity`, `tenant_id`, `trace_id`).

## 4. Stack LGTM self-hosted — F9.1

`docker/compose/observability.yml` (novo), espelhando o tutorial da Hostinger:

- **OpenTelemetry Collector** (OTLP gRPC 4317 / HTTP 4318) — ponto de entrada
  neutro, roteia métricas→Prometheus, logs→Loki, traces→Tempo.
- **Loki** (3100), **Prometheus** (9090), **Tempo** (3200), **Grafana** (3000).
- **Promtail/Grafana Alloy** (logs de container) + **Node Exporter** + **cAdvisor**
  (host/containers).
- Datasources e dashboards **provisionados** (as-code em `docker/observability/`).
- **Retenção curta** (logs 7–14 dias, traces 7 dias) por restrição da KVM2.

### Orçamento de recursos (KVM2)
Tabela de RAM por componente; LGTM completo + dados + apps pressiona 8 GB →
limites `deploy.resources` apertados e gatilho de upgrade para KVM4 (16 GB)
quando os apps Rust subirem. Loki indexa só labels (leve) — ponto a favor.

## 5. Health checks e alertas

- `/health` (liveness/readiness) e `/metrics` em cada binário Rust.
- **Alertmanager** (ou alertas do Grafana): serviço down, taxa de erro alta
  (por `error_code`), memória/disco, lag do bus. Canal inicial: e-mail/Telegram.

## 6. Segurança da telemetria

- Grafana atrás do proxy reverso (TLS + auth); portas do Collector/Loki/
  Prometheus/Tempo **não expostas** publicamente (rede Docker interna).
- **Não logar segredos/PII** — sanitizar payloads do WhatsApp e tokens (cruza com
  a diretriz de segurança e o doc 09).

## 7. Mapeamento para fases

| Entrega | Fase | Escopo |
|---|---|---|
| Crate `observability` mínima (logs JSON + `init_telemetry`) | **0.4** | base para todos os módulos |
| Spans `tenant_id` + propagação + métricas | **4–6** | conforme os apps surgem |
| Stack LGTM + tracing distribuído + dashboards | **9.1** | produção |

## 8. DoD

- Binário emite log JSON estruturado com nível configurável.
- Trace de uma mensagem webhook→resposta visível no Tempo, correlacionado por
  `tenant_id`/`trace_id`.
- Erros aparecem nos logs com `error_code` (integração com doc 06).
- Dashboards provisionados sobem com o compose.

## 9. Próximo passo

Implementar a crate `observability` (mínima) **antes** dos módulos de feature,
junto com a crate de erros ([06-tratamento-de-erros.md](./06-tratamento-de-erros.md)),
para que storage, auth, worker etc. já nasçam rastreáveis. O stack LGTM completo
entra na F9. CI/CD e DevOps (deploy do stack) em
[10-plano-cicd-devops.md](./10-plano-cicd-devops.md).

---

*Plano da observabilidade. Sujeito a canonização via `plan-restructuring`.*
