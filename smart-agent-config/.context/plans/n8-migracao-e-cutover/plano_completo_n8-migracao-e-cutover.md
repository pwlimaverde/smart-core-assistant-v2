# Plano Completo — Fase N8: Migração v1→v2 + cutover de produção (fim do port)

> Gerado em: 2026-07-18 · Reestruturado contra o código real e docs atuais (ver
> [info_aux_n8-migracao-e-cutover.md](./info_aux_n8-migracao-e-cutover.md)).
> Origem: `doc_dev/planejamento/23-fase-N8-migracao-e-cutover.md` (histórico).
> **Idioma:** Português (comunicação/documentação); código e identificadores em inglês.
> **Objetivo:** migrar os dados do legado Django para a v2, habilitar a produção web
> completa e **desligar o legado** — marco que encerra o port do projeto.
> **Pré-condição dura:** N7 concluída (enforce validado log-only, operação observada
> com tráfego real). Não se faz cutover às cegas.

## Correções aplicadas (vs. plano base)

| # | Correção | Motivo / Fonte |
|---|---|---|
| 1 | **Recodificação de credenciais concretizada:** Fernet(v1).decrypt → `CipherManager::encrypt` (AES-256-GCM), gravando o jsonb `{ciphertext,nonce,tag}` por chave; chave mestra v2 vem de `ENCRYPTION_KEY` (base64, 32 bytes). | `infrastructure_postgres/src/crypto.rs:23-109` |
| 2 | **`cryptography`/Fernet é dependência só do ETL** (`infra/migracao-v1/`), fora do runtime; `InvalidToken` tratada por credencial (não aborta o lote). | `doc_dev/libs/python/cryptography.md` |
| 3 | **N8.2 é habilitação, não construção:** blocos prod do Caddy estão **comentados** (`tenant.caddy:51-71`); o domínio prod serve o Django legado (`172.18.0.5:8000`). Inserir `handle /v2/tenant/*` **antes** do reverse_proxy do Django. | `infra/caddy/tenant.caddy` |
| 4 | **RBAC v1 aninhado → escopos planos** deve produzir exatamente o shape de `derivar_escopos` (decisão da N3), não um formato novo. | `application/src/auth/login.rs` |
| 5 | **Enforce (N8.3) usa os dados do N7:** a flag `SMARTCORE_QUOTA_ENFORCE` já existe (log-only desde a N4); ligar é decisão informada pela janela de observação do N7, não um passo cego. | `data_storage/src/main.rs`; N7.1 |
| 6 | **Embeddings:** revalidar modelo/dimensão antes de migrar direto — reembeddar via `ia_engine` só se divergente (pgvector 1536 já dos dois lados). | `doc_dev/libs/*/pgvector.md` |

---

## N8.1 — ETL v1→v2 (scripts idempotentes, dry-run, conciliação)

**Objetivo:** transferir os dados do Django legado para a v2 com fidelidade
verificável, sem cópia 1:1 onde há recodificação (RBAC, credenciais).

**Local:** `infra/migracao-v1/` — scripts versionados, **idempotentes**, com
`--dry-run` e relatório de conciliação **por entidade** (contagem v1 × v2 +
amostragem de hash).

**Ordem (respeita dependências referenciais):**
1. **Tenants, planos, assinaturas, pagamentos** — base de tudo (FKs). Mapear planos
   da v1 aos da v2 (schema `0003_plans_subscriptions.sql`; `max_storage_bytes` do N7).
2. **Usuários + RBAC** — transformar RBAC **aninhado por módulo** (v1) em **escopos
   planos + `flow_permissions`** (shape de `derivar_escopos`). Tabela de-para
   revisada por humano; amostragem de contas comparada lado a lado no dry-run.
3. **Contatos, atendimentos, mensagens/histórico** — preservar ids **ou** persistir
   mapa de correspondência (não quebrar referências cruzadas).
4. **Documentos de treinamento + embeddings** — migrar pgvector; **revalidar
   modelo/dimensão**; reembeddar via `ia_engine` (batch) só se divergente.
5. **Configs de tenant + credenciais** — para cada chave de API: `Fernet.decrypt`
   (Python, chave v1 por secret) → `CipherManager.encrypt` (AES-256-GCM) → jsonb
   `{ciphertext,nonce,tag}`. Plaintext só em memória; `InvalidToken` isola a
   credencial e vai para conciliação manual.
6. **Instâncias Evolution** — re-registrar/migrar tokens e instâncias; verificação
   ativa de health por instância pós-migração (via `data_whatsapp`).

**Estratégia de execução:** **duas passadas** — carga completa antecipada (fora da
janela) + **delta incremental** na janela de cutover (reduz downtime de históricos
grandes). Cada rerun é idempotente (upsert por id/chave natural).

**DoD:** dry-run conciliado por entidade (contagens batem, amostras de hash
conferem); credenciais recifradas e verificadas (instâncias respondem); relatório
de conciliação arquivado.

**Observabilidade & Auditoria:**
- (a) Log estruturado por lote/entidade: contagens, ids min/max, duração,
  `error_code`. **Sem PII em claro** (telefones mascarados).
- (b) `migracao.iniciada`/`migracao.concluida` no audit_log global (via `admin_pool`);
  falha de credencial registrada por id (não o valor).
- (c) Fernet key, tokens e plaintexts **nunca** logados nem escritos em disco; chaves
  em `SecretString`; o plaintext vive o mínimo entre decrypt e re-encrypt.

---

## N8.2 — Produção web completa

**Objetivo:** habilitar `/v2/admin` e `/v2/tenant` no domínio de produção, hoje
comentados, sem derrubar o painel Django enquanto ele coexiste.

**Áreas:** `infra/caddy/*.caddy`, `data_storage` (CORS/lifecycle prod),
`infra/provision-db-role.sh`, compose de prod.

**Passos:**
1. **Caddy prod:** inserir `handle_path /v2/admin/*` e `/v2/tenant/*` (estáticos)
   **antes** do `reverse_proxy` do Django (`172.18.0.5:8000`) no site block de
   `smartcoreassistant.com.br`; encaminhar gRPC-Web ao endpoint prod da `runtime_api`.
   `caddy validate --config /etc/caddy/Caddyfile` → `systemctl reload caddy`.
   Confirmar decisões pendentes na fase P: path definitivo (`/v2/tenant/`), portas
   host (8083/8084), endpoint gRPC-Web prod.
2. **Role não-superuser em prod:** rodar `infra/provision-db-role.sh` (entregue na
   N4) no Postgres de produção; apontar os apps para `smartcore_app_rt`.
3. **R2 prod:** `S3_CORS_ALLOWED_ORIGINS` com o domínio real + `infra/r2-cors.json`
   aplicado por `data_storage` (expondo `Content-Range`/`Accept-Ranges` para seek de
   mídia); lifecycle do R2 com valores de produção.

**DoD:** `/v2/admin` e `/v2/tenant` respondem no domínio real (coexistindo com o
Django), mídia carrega com CORS/range, apps prod rodam sob a role restrita.

**Observabilidade & Auditoria:**
- (a) Logs do Caddy/`data_storage` já existentes cobrem o roteamento.
- (b) Mudança de rota/role é ops — registrar no changelog e no runbook de cutover.
- (c) N/A (sem manipulação de segredo nova além das já protegidas).

---

## N8.3 — Rollout do enforce (com dados da janela do N7)

**Objetivo:** transformar as métricas log-only em limites reais e ligar o enforce.

**Passos:**
1. Analisar a janela log-only: métricas `quota.excedida`/`quota_excedida_total`
   (do N7.1) por plano/recurso — ver quem estouraria e em quanto.
2. Definir limites reais por plano (`max_instancias`, `max_departamentos`,
   `max_storage_bytes`) com base nos dados observados.
3. Ligar `SMARTCORE_QUOTA_ENFORCE=true` + rate limiting ativo em prod (mesma flag
   já cabeada em N4/N7 — vira enforce em vez de log).

**DoD:** enforce ativo em prod com limites informados por dados reais; nenhum tenant
legítimo bloqueado por limite mal calibrado (validado contra a janela).

**Observabilidade & Auditoria:**
- (a) Contadores de quota/rate-limit continuam; agora com bloqueios reais visíveis.
- (b) Ativação do enforce (mudança de política) registrada no audit_log; bloqueios
  reais auditados no ponto de enforce (padrão N4/N7).
- (c) Só limites/ids — sem PII.

---

## N8.4 — Cutover + desligamento do legado

**Objetivo:** virar a produção 100% para a v2 e desligar o Django, com rollback
ensaiado.

**Passos:**
1. **Freeze de escrita na v1** (janela combinada) → **ETL final incremental** (delta
   sobre a carga antecipada do N8.1) → **validação de conciliação** (contagens +
   amostras).
2. **DNS/rotas para a v2** (remover o `reverse_proxy` do Django do caminho principal).
3. **Rollback documentado e ensaiado ANTES da janela:** critérios go/no-go
   definidos previamente; rollback = voltar rotas ao Django, válido só até o ponto
   de freeze (depois disso os dados divergem).
4. **Smoke E2E na prod v2:** admin + tenant web no domínio real, desktop conectando,
   WhatsApp fluindo.
5. **Desligar o painel legado** e **arquivar `old/`** (`paulo-ecoprint-server`,
   `smart-core-assistant-painel`).

**DoD (e DoD do port):** produção roda 100% na v2 (admin + tenant web no domínio
real, desktop conectando, WhatsApp fluindo), dados da v1 migrados e conciliados,
enforce ativo com limites reais, Django legado desligado com rollback documentado —
**backlog do port encerrado**.

**Observabilidade & Auditoria:**
- (a) Log da janela: freeze, delta, validação, virada de rota (com durações).
- (b) `cutover.executado` no audit_log global (via `admin_pool`); go/no-go registrado.
- (c) Conciliação por hash **amostrado** — sem dump de PII no relatório.

---

## Sequenciamento

**N8.1 (carga antecipada) → N8.2 → N8.3 → N8.4 (delta + virada).** O ETL de carga
completa (N8.1) roda fora da janela; a produção web (N8.2) e o rollout do enforce
(N8.3) preparam o terreno; o cutover (N8.4) faz o delta incremental e a virada de
rota na janela combinada, com o legado desligado ao final.

## Validação (fase V)
- **Dry-run conciliado** do ETL (contagens v1×v2 + amostras de hash) por entidade.
- **Ensaio de rollback** completo (voltar rotas ao Django) antes da janela real.
- **Smoke E2E** na prod v2 (admin/tenant web + desktop + WhatsApp).
- `.\infra\test-local.ps1` + `.\infra\test-flutter.ps1` verdes no estado final.

## DoD da fase (encerra o port)
Produção 100% v2, dados migrados/conciliados, enforce ativo com limites reais,
Django desligado com rollback documentado. **Fim do backlog do port N1–N8.**
