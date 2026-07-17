# Fase N8 — Migração de dados v1→v2 + cutover de produção (fim do port)

> **Status:** Plano de execução — criado em **2026-07-17**. Terceira e última fase
> do cronograma de **port final** (N6–N8) — ver
> [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** migrar os dados do sistema legado (Django — `old/paulo-ecoprint-server`,
> `old/smart-core-assistant-painel`) para a v2, habilitar a produção web completa
> e **desligar o legado**. É o marco que encerra o port do projeto.
> **Pré-condição dura:** N7 concluída (enforce validado em log-only, operação
> observada com tráfego real). Não se faz cutover às cegas.

---

## 0. Estado real (aterramento)

| Área | Estado | Impacto |
|---|---|---|
| Domínio de produção | ⚠️ `smartcoreassistant.com.br` ainda serve o **painel Django da v1** (reverse_proxy no Caddy) | O bloco prod de `/v2/admin` e `/v2/tenant` está **comentado** nos `.caddy` desde o deploy-admin-web |
| Apps web v2 | ✅ Admin no ar em dev (`/v2/admin`); tenant buildado + serviço compose + CI prontos (N5.3), **não roteados em prod** | N8.2 é habilitação, não construção |
| Rastreabilidade v1→v2 | ✅ Apêndice B do doc 02 mapeia cada domínio da v1 ao componente v2 | Base do escopo do ETL |
| Transformações conhecidas | ⚠️ RBAC v1 (estrutura aninhada por módulo) → escopos **planos** (formato do `derivar_escopos`, decisão da N3); credenciais Fernet (v1) → AES-256-GCM (`CipherManager`) | ETL não é cópia 1:1 — tem recodificação |
| Embeddings | ✅ pgvector 1536 nos dois lados (`Documento`/`QueryCompose` portados) | Migração direta possível, validar dimensão/modelo |
| Enforce de quotas | ⚠️ `SMARTCORE_QUOTA_ENFORCE=false` em todo lugar (log-only desde a N4) | Rollout é decisão do N8.3, com dados da janela de observação do N7 |
| Decisões humanas pendentes | ⚠️ Path definitivo (`/v2/tenant/`), portas host (8083/8084), estratégia de convivência com o Django na janela | Confirmar na fase P do ciclo |

## 1. Escopo

### Dentro do escopo
- **N8.1 ETL v1→v2** (scripts versionados em `infra/migracao-v1/`, idempotentes,
  com dry-run e relatório de conciliação por entidade):
  1. Tenants, planos, assinaturas e pagamentos.
  2. Usuários + RBAC (aninhado → escopos planos + `flow_permissions`).
  3. Contatos, atendimentos, mensagens/histórico (ids preservados ou mapa de
     correspondência persistido).
  4. Documentos de treinamento + embeddings (pgvector; revalidar
     modelo/dimensão — reembeddar se divergente).
  5. Configs de tenant + credenciais (decifra Fernet → recifra AES-256-GCM;
     nunca em claro em disco/log).
  6. Instâncias Evolution (tokens/instâncias re-registrados ou migrados).
- **N8.2 Produção web completa:** habilitar `/v2/admin` e `/v2/tenant` no domínio
  prod (blocos Caddy hoje comentados), provisionar em prod a role não-superuser
  (`infra/provision-db-role.sh`), CORS (`S3_CORS_ALLOWED_ORIGINS`) e lifecycle do
  R2 com os valores de produção.
- **N8.3 Rollout do enforce:** analisar a janela log-only (métricas de
  `quota.excedida` do N7) → definir limites reais por plano → ligar
  `SMARTCORE_QUOTA_ENFORCE=true` + rate limiting ativo em prod.
- **N8.4 Cutover:** janela de migração (freeze de escrita na v1 → ETL final
  incremental → validação de conciliação → DNS/rotas para a v2), plano de
  rollback documentado e ensaiado (voltar rotas ao Django), desligamento do
  painel legado e arquivamento de `old/`.

### Fora do escopo
- Qualquer feature nova; refactors não exigidos pela migração.

## 2. Contrato de observabilidade (DoD transversal)

- ETL emite log estruturado por lote (contagens, ids min/max, duração) — **sem
  PII em claro** (telefones mascarados, credenciais nunca logadas).
- Cada entidade migrada tem conciliação (contagem v1 × v2 + amostragem de hash).
- Cutover auditado: `migracao.iniciada`/`migracao.concluida`/`cutover.executado`
  no audit_log global (via admin_pool).

## 3. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| ETL com transformação errada de RBAC | Usuário com mais/menos permissão que na v1 | Tabela de-para revisada por humano; amostragem de contas comparada lado a lado no dry-run |
| Recifragem de credenciais falhar em silêncio | Instância Evolution quebrada pós-cutover | Verificação ativa pós-migração (health por instância via `data_whatsapp`) |
| Janela de migração longa (histórico grande) | Downtime perceptível | ETL em duas passadas: carga completa antecipada + delta incremental na janela |
| Embeddings incompatíveis (modelo diferente) | RAG degradado silenciosamente | Comparar modelo/dimensão; reembeddar via `ia_engine` se necessário (batch) |
| Rollback tardio | Dados divergentes v1×v2 | Critérios de go/no-go definidos ANTES da janela; rollback só até o ponto de freeze |

## 4. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N8** | Inventário de dados da v1 real (dump) + decisões pendentes (path/portas/janela) | Aprovar de-para de entidades + plano de janela/rollback | ETL + habilitação prod + rollout enforce | Dry-run conciliado + ensaio de rollback + smoke E2E na prod v2 | Cutover executado; legado desligado; changelog encerra o port |

**DoD da fase (e do port):** produção roda 100% na v2 (admin + tenant web no
domínio real, desktop conectando, WhatsApp fluindo), dados da v1 migrados e
conciliados, enforce ativo com limites reais, Django legado desligado com
rollback documentado — **backlog do port encerrado**.

*Plano aterrado no Apêndice B (rastreabilidade v1→v2) do doc 02, nas pendências
de N4/N5 e no estado real do Caddy/CI. Pronto para `/plan-restructuring` quando a
fase for iniciada.*
