# Análise de enforce de quota (N8.3)

Ferramental de análise **offline/read-only** para embasar a decisão de ligar
`SMARTCORE_QUOTA_ENFORCE=true` em produção (fase N8.3 —
`doc_dev/planejamento/23-fase-N8-migracao-e-cutover.md`). Não escreve nada no
banco, não chama nenhum RPC de aplicação, não flipa nenhuma flag — só lê.

> Pasta separada de `infra/migracao-v1/` (raiz), de propósito. O pacote ETL
> Python de N8.1 vive na raiz de `infra/migracao-v1/` (provavelmente com nome
> em `snake_case`); este subdiretório com hífen (`analise-enforce/`) evita
> qualquer colisão de nome/import com aquele pacote. Os dois scripts aqui são
> SQL standalone, sem dependência do pacote ETL.

## Por que isto existe

O plano do N7 (`.context/plans/archive/n7-endurecimento-residual/`) descreve a
instrumentação esperada como um contador `quota_excedida_total{recurso}`
exposto via OTel/Prometheus. **Isso não existe no código atual** — conferido
lendo `server/crates/observability/src/usage_metrics.rs` (só tem contadores de
mensagens e mídia, nada de quota) e todo o caminho do
`SMARTCORE_QUOTA_ENFORCE` nos 4 binários que o leem
(`data_storage`, `data_postgres`, `data_whatsapp`, `webhook_ingress`). O que
existe de fato, por recurso:

| Recurso | Onde é lido/decidido | Sinal em modo log-only (enforce=false, hoje em todo lugar) |
|---|---|---|
| `instancias` | `data_whatsapp/src/main.rs::aplicar_quota_guard` (provisionamento de instância) | `audit_log` (Postgres), evento `quota.excedida` — **auditado incondicionalmente** (`auditar: true` hardcoded na chamada a `CheckQuota`), então sobrevive em log-only |
| `departamentos` | `data_postgres/src/main.rs` (handler de criação de departamento) | só `tracing::warn!(tenant_id=..., "quota de departamentos excedida (log-only...)")` — **não** vai para `audit_log` em log-only, pois lá `auditar` só é `true` quando `enforce` também é |
| `storage` | `data_storage/src/main.rs::aplicar_quota_guard_storage` (antes do upload ao R2) | idem: só `tracing::warn!(...)`, **sem nenhum campo estruturado** (nem `tenant_id`), pois nem a função nem o handler chamador têm `#[tracing::instrument]` — ver `03_loki_logql_storage_departamentos.md` |
| inadimplência (flag compartilhada, não é um dos 3 recursos com limite numérico) | `data_postgres` (ponto de enforcement) + `webhook_ingress` (caminho quente, sempre log-only mesmo com enforce=true) | evento `tenant.bloqueado_inadimplencia` em `audit_log`, mesmas regras de `auditar` do ponto de enforcement |

Ou seja: **não há uma fonte única e uniforme** de métricas log-only para os 3
recursos pedidos. Por isso a ferramenta principal (`01_estado_atual_quotas.sql`)
não depende de nenhum log — ela recalcula o estado *atual* de uso vs. limite
direto do banco, reaproveitando a mesma lógica de
`verificar_quota` (`server/crates/infrastructure_postgres/src/tenants/quota.rs`).
Isso funciona porque `uso_atual` de cada recurso já é um contador persistido
(`COUNT(*)` de instâncias/departamentos ativos, ou o total acumulado em
`tenants_storage_usage`), não uma taxa — o snapshot de hoje já reflete o efeito
acumulado do período observado, sem precisar reconstruir uma série temporal de
logs incompleta.

## Arquivos

- **`01_estado_atual_quotas.sql`** — fonte primária, recomendada para os 3
  recursos. Recalcula uso vs. limite por tenant/plano/recurso a partir das
  tabelas atuais (`tenants_subscription`, `tenants_plan`,
  `oraculo_app_instance`, `oraculo_departamento`, `tenants_storage_usage`).
  Dois blocos de resultado: resumo agregado por (plano, recurso) e lista
  nominal dos tenants que seriam bloqueados hoje.
- **`02_janela_log_only_audit.sql`** — consulta a trilha de auditoria
  (`audit_log`, evento `quota.excedida`/`tenant.bloqueado_inadimplencia`) numa
  janela de tempo. Só dá série histórica confiável para `instancias`, mas
  incluída para "quantas vezes isso realmente aconteceu ao longo do período"
  além do snapshot atual, e porque `instancias` é auditado incondicionalmente.
- **`03_loki_logql_storage_departamentos.md`** — queries LogQL para o Grafana
  LGTM (Loki) como confirmação de ordem de grandeza para `storage`/
  `departamentos`, já que esses dois não aparecem em `audit_log` em log-only.
  Documenta o gap de `tenant_id` ausente no log de `storage`.
- **`run_analysis.ps1`** / **`run_analysis.sh`** — wrapper fino que roda os
  dois `.sql` via `psql` e salva a saída em CSV com timestamp. Opcional — os
  `.sql` também rodam direto com `psql -f`.

## Como rodar

Precondição: acesso de rede ao Postgres de produção (via túnel SSH,
`infra/tunnel.ps1 -Env prod` / `infra/tunnel.sh prod` — ver aquele script) e a
**string de conexão do role bootstrap** (`smartcore_app`, não
`smartcore_app_rt`). Os dois scripts fazem leitura cross-tenant
(`tenants_subscription`, `tenants_storage_usage` etc. têm RLS forçado por
`app.current_tenant`), então precisam rodar como o superusuário bootstrap —
mesma exceção deliberada de tooling operacional offline que o pacote ETL de
N8.1 usa nesta mesma pasta pai, e que está documentada na regra de arquitetura
"banco só via infra/RPC" como não se aplicando a scripts de análise/migração
fora do caminho de aplicação.

```powershell
# 1. Abrir túnel (terminal separado, deixar aberto)
.\infra\tunnel.ps1 -Env prod

# 2. Rodar a análise (nova janela/terminal)
$env:DATABASE_ADMIN_URL = "postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2"
psql $env:DATABASE_ADMIN_URL -f infra\migracao-v1\analise-enforce\01_estado_atual_quotas.sql
psql $env:DATABASE_ADMIN_URL -f infra\migracao-v1\analise-enforce\02_janela_log_only_audit.sql
```

ou use o wrapper (`run_analysis.ps1`) para salvar CSV automaticamente.

## Limites e suposições assumidas (revisar)

1. **Não existe contador Prometheus `quota_excedida_total`** apesar de descrito
   no plano do N7 — confirmado lendo o código, não assumido. Se isso for
   incorreto (ex.: implementado em outro lugar que eu não encontrei), a
   abordagem baseada em SQL continua válida como fonte primária, mas vale
   reconciliar com o dashboard real.
2. **`storage` não tem `tenant_id` no log de log-only** — gap real de
   instrumentação, não limitação da consulta. Documentado em
   `03_loki_logql_storage_departamentos.md`, com sugestão (não aplicada) de
   correção de uma linha para decisão humana futura.
3. **Tenants sem `tenants_subscription`** ficam de fora do relatório de
   `01_estado_atual_quotas.sql` por construção (mesma postura do código:
   sem assinatura = sem limite aplicado = nunca "excedido"). Se a intenção for
   auditar também esses tenants (ex.: trial/legado que deveriam ter sido
   migrados para um plano), isso precisa de uma consulta à parte — não
   coberta aqui.
4. **Exatidão do parsing LogQL não verificada contra logs reais** (ambiente
   de análise não tinha acesso a produção) — tratar `03_loki_logql_...md` como
   rascunho a validar na primeira execução real, ao contrário dos `.sql`, que
   foram conferidos direto contra o schema das migrations e o código dos
   guards.
