# Documentação Auxiliar — Observabilidade e Auditoria

> Gerado em: 2026-06-04
> Plano canônico: `.context/plans/archive/observabilidade-e-auditoria/observabilidade-e-auditoria.md`
> Plano completo: `.context/plans/archive/observabilidade-e-auditoria/plano_completo_observabilidade-e-auditoria.md`

---

## Libs Rust

### tracing (0.1.40) — USAR LOCAL
- **status:** ✅ ATUALIZADA
- **Recursos usados pelo plano:** `#[instrument]`, macros `info!`/`warn!`/`error!`/`debug!`, spans com metadados (`tenant_id`, `trace_id`).

### tracing-subscriber (0.3.x) — CRIAR
- **status:** ✅ ATUALIZADA
- **Features de Cargo:** `["json", "env-filter", "fmt", "registry"]`

### OpenTelemetry Rust
- **Versões adotadas:** `opentelemetry` 0.24, `opentelemetry_sdk` 0.24, `opentelemetry-otlp` 0.17 e `tracing-opentelemetry` 0.25.

### sqlx (0.9) — USAR LOCAL
- Usado para queries e repositórios sem macro `!` para build estável offline.

---

## Serviços Externos
- **OTel Collector** (4317 gRPC / 4318 HTTP)
- **Grafana Loki** (3100)
- **Grafana Tempo** (3200)
- **Prometheus** (9090)
- **Grafana** (3000)
- **Promtail** (9080)
