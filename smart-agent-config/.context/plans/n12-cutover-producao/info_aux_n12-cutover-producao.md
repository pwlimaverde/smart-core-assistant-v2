# Documentação Auxiliar — N12 Cutover de Produção

> Gerado em: 2026-08-09
> Plano canônico: `.context/plans/n12-cutover-producao.md`
> Plano completo: `.context/plans/n12-cutover-producao/plano_completo_n12-cutover-producao.md`

---

## Escopo de dependências

Fase de **operação**, não de construção. Nenhuma lib nova, nenhuma API externa
nova. Todo o código já existe e foi testado; o que falta é executá-lo contra
produção.

| Componente | Onde | Estado |
|---|---|---|
| ETL v1→v2 | `infra/migracao-v1/` (Python + asyncpg) | pronto, 75 testes, **nunca rodado em produção** |
| Runbook de cutover | `infra/migracao-v1/RUNBOOK_CUTOVER_N8.md` | pronto |
| Runbook do enforce | `infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md` | pronto |
| Role e CORS de produção | `infra/PROD_ROLE_CORS_N8.md` | pronto |
| Tooling de limites | `infra/migracao-v1/analise-enforce/` | pronto |
| Caddy de produção | `docker/edge/Caddyfile` | `/v2/admin` e `/v2/tenant` no ar; **Django ainda no fallback da raiz** |
| Restauração de dump | `infra/restore-postgres.sh` | existe |

---

## Particularidades do ETL (conhecidas, já resolvidas)

Registradas no changelog da N8 e nas correções de 28/07 — releia antes de rodar:

1. **A v1 é DB-per-tenant.** O ETL descobre `TenantDatabase`, conecta no banco
   físico de cada tenant e injeta `tenant_id`. Achado arquitetural que não estava
   no plano original.
2. **Colisão de `auth_user.id=1`.** A v1 tem superusuário com id 1; o primeiro
   superusuário criado na v2 também. O upsert sobrescrevia a senha válida com o
   marcador `!migrated-from-v1` e **deixava o ambiente sem acesso
   administrativo** — aconteceu em dev. Corrigido com
   `ColumnSpec.preservar_destino_quando`. **Regra operacional: criar o
   superusuário DEPOIS do ETL.**
3. **Codec `jsonb` no asyncpg** — sem ele, qualquer bind de dict/list para coluna
   jsonb quebra em runtime (`module_permissions`, `subscribed_events`,
   `metadados`, `api_key`). Corrigido em `migracao_v1/db.py`.
4. **Credenciais**: `CipherManagerPy` replica byte a byte o `CipherManager` Rust
   (Fernet da v1 → AES-256-GCM). `InvalidToken` isola a credencial sem abortar o
   lote — as que falharem saem no relatório para refazer à mão.
5. **`whatsapp_instance.api_key`** virou JSONB cifrado (migration 0023).
6. **Embeddings**: pgvector 1536 nativo dos dois lados, cópia direta via
   `::vector` — sem reprocessar.
7. **Mídia legada** (etapa 7 do ETL): é a única coisa que **não** dá para
   reprocessar a partir do banco. Conciliar contagem de objetos no R2.

---

## Pendências herdadas que esta fase fecha

| Pendência | Origem | Item |
|---|---|---|
| 4 validações manuais (rajada, dashboards, E2E, dedupe/dead-letter) | N7.5 (2026-07-23) | E2 |
| `SMARTCORE_QUOTA_ENFORCE` ainda `false` | N4 | E3 |
| ETL não executado | N8.1 | E1 + E4 |
| Django no fallback do Caddy | N8.2 | E4 |
| `ReprocessarDeadLetter` sem chamador | N7 | E5 (ou N11.9) |
| Assinaturas expirando no dashboard | paridade v1 (`backoffice/dashboard.html`) | E5 |

**Acrescentado pelas fases novas:** teste de mídia ponta a ponta (N9) e teste de
roteamento por instância com dois números (N11.2) entram nas validações da E2. A
quota de **storage** passa a morder de verdade depois da N9a — observar antes do
enforce global.

---

## Grupo C — Observabilidade e Auditoria

| Etapa | Log | `audit_log` | Sanitização |
|---|---|---|---|
| E1 ensaio do ETL | relatório por entidade + **duração por etapa** (dimensiona a janela) | `migracao.iniciada`/`.concluida` (já implementado; pulado em `--dry-run`) | **o ETL manipula credenciais decifradas** — revisão obrigatória de que nada disso entra em log ou no relatório de conciliação |
| E2 validações | métricas do Grafana com tráfego real | — | nenhum payload de mensagem em log durante os testes de carga |
| E3 enforce | alerta de taxa de bloqueio por tenant | `quota.excedida` só quando bloqueia de verdade (correção da N7) | — |
| E4 cutover | verbosidade elevada **temporariamente** no `webhook_ingress` e no `worker`, revertida ao fim | **`cutover.iniciado`, `cutover.concluido`** | a tentação de logar payload inteiro para depurar é grande — **não fazer**; usar `trace_id` |
| E5 residuais | conforme item | — | — |

---

## Decisões humanas pendentes (bloqueiam a E4)

Não são técnicas — precisam do dono do produto:

1. **Janela de migração**: data, hora e duração aceitável de indisponibilidade
   (dimensionada pelo ensaio da E1).
2. **Estratégia de convivência** com o Django durante a virada.
3. **Período de retenção** do legado (`old/` + dump) antes da remoção definitiva.
4. **Comunicação aos tenants**: a senha da v1 **não** é migrada utilizável — todo
   usuário migrado precisa redefinir a senha no primeiro acesso (decisão já
   aprovada na N8.1). Isso exige aviso prévio e depende do e-mail transacional da
   **N11.7** estar funcionando.
