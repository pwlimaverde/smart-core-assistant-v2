# Padrão de Nomenclatura — Métricas Prometheus/OTEL

**Data**: 2026-10-02  
**Status**: Proposta de Padronização  
**Objetivo**: Consistência em nomes de métrica, atributos OTEL e spans.

---

## Convenção

```
smartcore_{dominio}_{entidade}_{metrica}_{unidade}
```

Onde:
- `smartcore_` — prefixo raiz
- `{dominio}` — `worker`, `ia`, `api`, `scheduler`, `storage`
- `{entidade}` — `message`, `analyse`, `response`, `buffer`, `media`
- `{metrica}` — `latency`, `duration`, `count`, `lag`, `error`
- `{unidade}` — `ms`, `s`, `bytes`, `total`

---

## Exemplos

### Antes (inconsistente)
```
duracao_ms              → não tem prefixo
confianca               → sem unidade
campos_pendentes_count  → sem domínio
fluxos_count            → sem domínio
requisicoes             → sem unidade
```

### Depois (padronizado)
```
smartcore_worker_message_processing_duration_ms
smartcore_ia_response_confidence                    # score 0.0-1.0
smartcore_worker_atendimento_pending_fields_count
smartcore_worker_atendimento_fluxos_total
smartcore_ia_response_openai_requests_total
```

---

## Aplicação Atual

| Arquivo | Escopoo | Status |
|---------|---------|--------|
| `server/apps/worker/src/main.rs` | Spans OTEL (attributes) | ⚠️ Inconsistente |
| `ia_engine/src/ia_engine/telemetry.py` | Spans OTEL (attributes) | ⚠️ Inconsistente |
| `docker/observability/prometheus.yml` | Scrape config | ✅ OK |

---

## Fases de Implementação

**Fase 1 (agora)**:  
Documentação + exemplo em 2 métricas críticas.

**Fase 2 (sprint seguinte)**:  
Refatoração do worker e ia_engine para usar novos nomes.

**Fase 3 (sprint+2)**:  
Atualização de dashboards Grafana e regras de alerta.

---

## Impacto

- ✅ Histórico de métricas antigas permanece no Prometheus (nenhuma perda)
- ✅ Dashboards com nomes antigos continuam funcionando até serem atualizados
- ⚠️ Novos dashboards devem usar novos nomes desde o início
