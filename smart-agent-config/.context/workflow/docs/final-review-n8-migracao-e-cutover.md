# Final Review — n8-migracao-e-cutover
Data: 2026-07-23 · Revisor: agente principal (subagente Opus interrompido por limite mensal de API a meio da auditoria — ver "Nota metodológica")

## Rótulo: CORRIGIDO

## Nota metodológica
O gate desta fase normalmente lança um subagente Opus dedicado para a auditoria
final. Nesta execução o subagente (`a9e5a73e0035628ca`) foi interrompido pelo
limite mensal de gastos da API logo no início (7 tool calls, ~51s), antes de
produzir relatório. Em vez de tentar relançar (mesmo bloqueio esperado), o
agente principal assumiu a auditoria diretamente, com o mesmo escopo e critério
descritos no prompt que seria passado ao subagente. A auditoria abaixo cobre os
mesmos pontos, mas foi feita sem o modelo Opus dedicado — registrado para
transparência.

## Resumo das correções
- **ETL (`infra/migracao-v1/`)**: nenhuma conexão asyncpg registrava codec
  jsonb (quebraria qualquer bind de dict/list Python para coluna jsonb —
  afetava `module_permissions`, `subscribed_events`, `metadados`, e o próprio
  `api_key` do WhatsApp). Corrigido em `migracao_v1/db.py`.
- `whatsapp_specs.py`: o transform de `api_key` serializava JSON manualmente
  como string em vez de aproveitar o codec jsonb nativo (resquício de uma
  suposição desatualizada sobre o schema, já que o subagente que escreveu o
  ETL rodou num worktree defasado). Corrigido para devolver o dict Python
  diretamente.
- **Gap de observabilidade real**: o orchestrator do ETL não emitia
  `migracao.iniciada`/`migracao.concluida` no `audit_log`, exigido pelo plano
  completo (seção "Observabilidade & Auditoria" do N8.1-b). Adicionado em
  `cli.py` (`_registrar_audit_log`, best-effort, não aborta o ETL se a escrita
  de auditoria falhar; não emitido em `--dry-run`, consistente com o
  dry-run não escrever nada no v2).
- **Adapter Rust WhatsApp (fora do ETL)**: `whatsapp_instance.api_key` estava
  em texto plano apesar do comentário "encriptado em repouso" na migration
  0008 — corrigido com migration nova (0023), `CipherManager::encrypt_to_json`/
  `decrypt_json_entry`, e todos os call-sites do repositório (`criar`,
  `buscar_por_*`, `listar_ativas`, `admin_listar_todas_conectadas`) passando a
  receber `cipher: &CipherManager`. Confirmado por grep que não sobrou nenhum
  call-site gravando `api_key` como string plana.
- **N8.2**: a primeira tentativa de habilitar `/v2/admin`/`/v2/tenant` em
  produção mirou `infra/caddy/*.caddy` — arquivo legado, não é o que
  `deploy-prod.yml` de fato publica. Corrigido aplicando a mudança real em
  `docker/edge/Caddyfile` (config viva) e marcando os arquivos legados como
  obsoletos no topo.

## 1. Plano vs. Implementado

| Item do plano | Status | Observação |
|---|---|---|
| N8.1.1 Tenants/planos/assinaturas/pagamentos | ✅ | `core_specs.py` — nomes de tabela conferidos contra migrations 0002/0003 |
| N8.1.2 Usuários + RBAC (aninhado→escopos) | ✅ | `rbac.py` produz array `recurso:acao`, shape aceito por `derivar_escopos`; senha marcada não-utilizável (decisão aprovada) |
| N8.1.3 Contatos/atendimentos/mensagens (DB-per-tenant→tenant_id) | ✅ | `tenant_specs.py`, iteração via `TenantDatabase` + `id_map` |
| N8.1.4 Documentos + embeddings (pgvector 1536) | ✅ | cast `::text`/`::vector`, cópia direta sem reembedding |
| N8.1.5 Credenciais (Fernet→AES-256-GCM) | ✅ | `crypto.py::CipherManagerPy` replica `crypto.rs`; `InvalidToken` isola credencial sem abortar lote |
| N8.1.6 Instâncias Evolution | ✅ | 3 fontes de credencial preservadas sem unificar, conforme plano |
| N8.1 item 7 (mídia legada→R2) | ✅ | `steps/media.py`, dependência opcional `aioboto3` |
| N8.1 Observabilidade (b) audit_log | ⚠️→✅ | Ausente na entrega original; corrigido nesta revisão |
| N8.2 Caddy prod | ⚠️→✅ | Mirou arquivo errado na entrega original; corrigido para `docker/edge/Caddyfile` |
| N8.2 role smartcore_app_rt / CORS R2 | ✅ | Já preparado desde N4/N5.3; `.env.example` corrigido para incluir origem prod |
| N8.3 tooling enforce | ✅ | `analise-enforce/` + runbook; não liga a flag de fato (decisão correta — depende de dados reais) |
| N8.4 runbook de cutover/rollback | ✅ | `RUNBOOK_CUTOVER_N8.md` |
| Escopo "não executar contra produção real" | ✅ | Nenhuma credencial real decriptada, nenhum DNS alterado, `old/` intacto |
| ➕ Fix gap cifra `whatsapp_instance.api_key` | ➕ | Não estava no plano original; decisão registrada na fase P após achado |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---|---|---|
| `infra/migracao-v1/migracao_v1/db.py` (conectar_v1_default/conectar_v2/abrir_conexao_tenant) | Nenhum codec jsonb registrado nas conexões asyncpg — bind de dict/list Python para coluna jsonb falharia em runtime | Adicionado `_registrar_codec_jsonb` (json/jsonb via `set_type_codec`) chamado em todas as funções de conexão |
| `infra/migracao-v1/migracao_v1/tables/whatsapp_specs.py:38-49` | Transform de `api_key` fazia `json.dumps` manual (suposição de coluna VARCHAR desatualizada) | Devolve o dict diretamente; docstring atualizada refletindo o schema JSONB real (migration 0023) |
| `infra/migracao-v1/README.md` (seção 6) | Documentava a suposição do formato de `api_key` como pendência aberta | Marcado como resolvido, com referência à migration 0023 e ao fix do adapter Rust |
| `infra/migracao-v1/migracao_v1/cli.py` | Sem emissão de `migracao.iniciada`/`migracao.concluida` no audit_log (exigido pelo plano) | Adicionado `_registrar_audit_log` (best-effort) chamado no início/fim de `_run`, pulado em `--dry-run` |
| `server/crates/infrastructure_postgres/src/crypto.rs` | Só existia `decrypt_from_jsonb` (para dicionário nomeado tipo `api_keys`), sem primitiva para um único segredo isolado | Adicionados `encrypt_to_json`/`decrypt_json_entry` + 3 testes novos |
| `server/crates/infrastructure_postgres/migrations/0023_...sql` (novo) | `whatsapp_instance.api_key` era VARCHAR plano apesar do comentário "encriptado em repouso" | Migration muda para JSONB; linhas pré-existentes (sem dados reais ainda) viram `{}` |
| `server/crates/infrastructure_postgres/src/integracoes/whatsapp.rs` | Todo o repositório lia/gravava `api_key` como String plana | `WhatsappInstanceRow` (jsonb bruto) + `.decrypt(cipher)`; todos os métodos do trait passam a receber `cipher: &CipherManager` |
| `server/apps/data_postgres/src/adapters/whatsapp.rs` + `main.rs` | `PgWhatsappStore` não tinha acesso ao `CipherManager` | Campo `cipher: Arc<CipherManager>` adicionado; `main.rs` passa a instância já criada |
| `server/crates/infrastructure_postgres/tests/integracoes/mod.rs` | Testes chamavam a API antiga (sem cipher) | Atualizados + nova asserção que a coluna crua nunca contém o plaintext |
| `infra/caddy/tenant.caddy` / `admin.caddy` | Mirava arquivo que não é mais aplicado em produção (pós-migração full-docker) | Aviso de obsolescência no topo, apontando para `docker/edge/Caddyfile` |
| `docker/edge/Caddyfile` | `/v2/admin`/`/v2/tenant` não habilitados no domínio real | `handle_path` com precedência sobre o fallback Django + matcher de Content-Type para gRPC-Web |
| `.env.example` (S3_CORS_ALLOWED_ORIGINS) | Só listava a origem dev | Inclui também a origem de produção (`infra/r2-cors.json` já listava as duas) |

## 2b. Observabilidade & Auditoria

| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| ETL — todos os steps | ✅ | ✅ (corrigido) | ✅ | `log_lote` já mascarava/omitia PII; `migracao.iniciada`/`concluida` adicionados |
| ETL — falha de credencial (Fernet InvalidToken) | ✅ | N/A (vai para `conciliacao_manual` do relatório, não audit_log — por linha/id, sem valor) | ✅ | Consistente com o plano ("falha de credencial registrada por id, não o valor") |
| Fix cifra WhatsApp (Rust) | ✅ (`#[tracing::instrument(skip_all)]` já existia nos métodos) | N/A (não é uma mudança de política, é fix de bug de armazenamento) | ✅ | `CipherManager` já tem `Debug` redigido; nenhum plaintext logado |
| Caddy prod | ✅ (logs do próprio Caddy) | N/A | N/A | Conforme plano ("mudança de rota é ops, registrar no changelog") |

## 3. Decisões Autônomas (revisar depois)

- Assumi via grep/leitura manual (sem o subagente Opus dedicado) que não havia
  outros desvios além dos listados — uma segunda auditoria independente
  (rodar `/final-review` de novo quando a cota de API for renovada) é
  recomendada antes de qualquer execução real contra produção.
- `audit_log` do ETL não é emitido em `--dry-run` (decisão minha, não estava
  explícita no plano) — para manter a invariante "dry-run não escreve nada no
  v2". Se quiserem rastro de auditoria mesmo em dry-run, é uma mudança de
  1 condicional em `cli.py`.
- Não toquei em `oraculo_departamento.api_key`/`oraculo_app_instance.api_key`
  (continuam em texto plano, igual à v1) — já documentado como débito técnico
  aceito no plano original, não é escopo desta correção.

## 4. Revalidação

- pytest (ETL, 75 testes): ✅ (rodado após cada correção)
- cargo fmt --check: ✅
- cargo clippy --all-targets --all-features -D warnings: ✅
- cargo sqlx prepare --workspace --check: ✅ (sem drift)
- cargo test --workspace (via túnel, banco dev real): ✅ exceto 1 teste
  pré-existente/não relacionado (`jwt::validar_token_com_assinatura_adulterada`,
  confirmado como passando isolado — `jwt.rs` não foi tocado neste ciclo)
- testes de integração `whatsapp`/`integracoes` (4/4, contra banco real): ✅,
  incluindo asserção nova de que a coluna nunca guarda plaintext

## 5. Pendências (fora do escopo do plano, não corrigidas)

- Execução real do ETL/cutover/enforce contra produção — **esperado**, é o
  próximo passo humano com os runbooks entregues, não uma pendência do
  código.
- `oraculo_departamento.api_key`/`oraculo_app_instance.api_key` em texto
  plano — débito técnico pré-existente, aceito no plano, não corrigido aqui.
- Segunda auditoria Opus completa quando a cota de API permitir — recomendada
  antes da janela de cutover real, dado o volume de código novo (ETL Python
  inteiro, ~30 tabelas) que só teve uma passada de revisão humana/manual.
