# migracao-v1 — ETL de migração v1 (Django, DB-per-tenant) → v2 (Rust, single-DB + RLS)

Ferramenta de operação para o cutover da fase N8. Roda **fora** do runtime do
v2 (não é importada por nenhum crate Rust) — é um pacote Python isolado,
executado manualmente por um operador humano com acesso às credenciais reais
de produção, uma única vez (ou algumas vezes em modo `--since` durante a
janela de cutover).

**Este pacote não conecta em nenhum banco real por si só.** Ele só faz algo
quando você aponta as variáveis de ambiente (`V1_DEFAULT_DATABASE_URL`,
`V2_DATABASE_URL`, etc.) para bancos de verdade e roda o CLI. Sem isso, só os
testes unitários (lógica pura, sem I/O) rodam.

## Por que asyncpg (e não psycopg/SQLAlchemy)

- **asyncpg** é o driver Postgres async mais rápido do ecossistema Python
  (protocolo binário nativo, sem overhead de ORM), e o ETL faz muita leitura
  em lote — isso importa em tabelas grandes (`oraculo_mensagem`).
- O restante do projeto já usa `sqlx` (Rust) com Postgres puro — não há
  ORM/migrations Django para replicar aqui, então não há ganho em trazer
  SQLAlchemy só pelo query builder.
- `psycopg` (v3) também tem suporte async e seria uma alternativa razoável;
  escolhi `asyncpg` pela API mais direta para paginação por cursor/keyset
  (`fetch`/`fetchrow`/`fetchval` sem abstração extra) e por já ser a escolha
  de fato mais comum em ETLs Python-Postgres de alto volume.
- `cryptography` é usada para Fernet (compatibilidade com a v1) e AES-256-GCM
  (compatibilidade com o `CipherManager` do v2) — é dependência **só deste
  pacote**, nunca do runtime do v2.

## Estrutura

```
migracao_v1/
  cli.py                 — CLI (argparse), orquestra os steps na ordem certa
  config.py               — leitura de variáveis de ambiente (Config, S3Settings)
  secret.py                — wrapper Secret (nunca aparece em repr/log)
  crypto.py                 — Fernet (v1) decrypt + AES-256-GCM (v2) re-encrypt
  rbac.py                    — transformação module_permissions -> escopos
  delta.py                    — lógica pura do filtro --since
  id_map.py                    — mapa id_v1 -> id_v2 (persistido em JSON)
  report.py                     — relatório de conciliação + mascaramento de PII
  logging_utils.py                — log estruturado por lote (JSON, sem PII)
  db.py                             — conexões v1 default / por tenant / v2
  tables/
    spec.py            — TableSpec/ColumnSpec/FkRemap (declarativo)
    engine.py           — motor genérico: upsert idempotente + dry-run + delta
    core_specs.py         — tenants, planos, usuários, RBAC, credenciais (item 1/2/5)
    tenant_specs.py         — operacional/clientes/atendimentos/treinamento (item 3/4)
    whatsapp_specs.py         — EvolutionInstance/Contact/WhiteList (item 6)
  steps/
    orchestrator.py    — liga os TableSpecs aos steps 1-6, na ordem certa
    media.py             — step 7 (upload de mídia legada para o R2)
tests/                       — testes unitários (lógica pura, sem banco)
```

### O motor genérico (`tables/engine.py`)

Em vez de escrever a lógica de upsert/idempotência/dry-run/delta/relatório
separadamente para ~30 tabelas, existe **um único motor** (`migrate_table`)
que consome uma `TableSpec` (dados: nomes de tabela/coluna, transformações,
estratégia de id, FKs a remapear). Cada tabela é só uma declaração de dados
em `core_specs.py`/`tenant_specs.py`/`whatsapp_specs.py`. Isso significa que
o comportamento transversal (idempotência, `--dry-run`, `--since`, contagens
do relatório) é testado/corrigido **uma vez só** e vale para todas as tabelas.

Três estratégias de id (`TableSpec.id_strategy`):

- **`preserve`**: o id v1 vira o id v2 diretamente (`UPSERT ... ON CONFLICT
  (id) DO UPDATE`). Só é permitido para tabelas `scope="core"` (banco
  `default` único da v1 — sem risco de colisão entre tenants). Usado em
  `auth_user`, `tenants_tenant`, `tenants_plan`, `tenants_subscription`,
  `tenants_paymentrecord`, `tenants_tenantuser`, `tenants_tenantinvite`.
- **`natural`**: upsert por uma chave natural (`ON CONFLICT (<cols>)`), o id
  v2 é gerado pelo `SERIAL`. Usado quando o id v1 é irrelevante (ex.:
  `tenants_tenantconfig` por `tenant_id`, `settings_manager_coresettings`
  por `key`, tabelas M2M/join como `oraculo_cliente_contatos` e
  `atu_etiqueta_atendimento` por suas colunas de unicidade).
- **`map`**: gera um id v2 novo via `SERIAL` e grava a correspondência
  `id_v1 -> id_v2` no `IdMap` (ver abaixo). **Obrigatório** para toda tabela
  `scope="tenant"` (TENANT_APPS) — a v1 é DB-per-tenant, cada tenant tem sua
  própria sequência de ids começando em 1, então dois tenants podem ter um
  `Atendimento` id=42 completamente diferente. Ao consolidar num único banco
  v2, colisões são esperadas.

## O mapa de correspondência de ids (`IdMap`)

Persistido em dois lugares:

1. **Arquivo "vivo"** (`MIGRACAO_STATE_DIR/id_map.json`, default
   `./migracao_v1_state/id_map.json`) — lido no início e regravado no fim de
   cada execução real (`--dry-run` nunca grava). É o que garante idempotência
   entre execuções: rodar o CLI duas vezes reconhece os ids já migrados e faz
   `UPDATE` em vez de duplicar linhas.
2. **Snapshot versionado por execução** (`MIGRACAO_REPORTS_DIR/<run_id>/id_map.json`,
   default `./reports/<run_id>/id_map.json`) — sempre gravado, mesmo em
   `--dry-run` (nesse caso reflete o estado do mapa antes da execução, já que
   nada é escrito). Serve de auditoria histórica.

## Como rodar

### 1. Instalar

```bash
cd infra/migracao-v1
python -m venv .venv
# Windows: .venv\Scripts\activate    |    Unix: source .venv/bin/activate
pip install -e ".[dev]"          # so o essencial + testes
pip install -e ".[dev,storage]"  # inclui aioboto3, necessario so para o step "media"
```

### 2. Rodar os testes (não precisa de banco nenhum)

```bash
pytest -q
```

### 3. Configurar variáveis de ambiente (credenciais REAIS — nunca commitadas)

```bash
export V1_DEFAULT_DATABASE_URL="postgresql://user:pass@host:5432/v1_default_db"
export V1_ENCRYPTION_KEY="<chave Fernet da v1, settings.ENCRYPTION_KEY>"
export V2_DATABASE_URL="postgresql://smartcore_app:pass@host:5432/smartcore_v2"
export ENCRYPTION_KEY="<mesma ENCRYPTION_KEY que o Rust CipherManager::new_from_env le, base64 padrao de 32 bytes>"
export V1_MEDIA_ROOT="/caminho/para/media_root/da_v1"     # so p/ step "media"
export S3_ENDPOINT="https://<account>.r2.cloudflarestorage.com"
export S3_ACCESS_KEY_ID="..."
export S3_SECRET_ACCESS_KEY="..."
export S3_BUCKET="smartcore-midia"                          # so p/ step "media"
```

Em Windows/dev, se o Postgres v2 só for alcançável por túnel/TCP explícito,
lembre do padrão do projeto (`SMARTCORE_<SVC>_ENDPOINT=tcp://...`) — mas isso
é só para os serviços Rust; este ETL fala Postgres diretamente via `asyncpg`
com a DSN normal (`postgresql://...`), túnel SSH por fora se necessário (ver
`infra/tunnel.ps1`).

### 4. Dry-run (não escreve nada — só relatório)

```bash
python -m migracao_v1 --dry-run
python -m migracao_v1 --dry-run --entidade tenants.tenant
python -m migracao_v1 --dry-run --steps core,tenant_apps
```

### 5. Execução real

```bash
# Carga completa, todos os steps exceto midia (media exige --steps explicito):
python -m migracao_v1

# So um tenant (recomendado para validar antes do cutover em massa):
python -m migracao_v1 --tenant acme

# So uma entidade especifica:
python -m migracao_v1 --entidade clientes.contato --tenant acme

# Delta (janela de cutover reduzida) — so linhas mudadas desde X:
python -m migracao_v1 --since 2026-07-20T00:00:00-03:00

# Incluir o step de midia (exige V1_MEDIA_ROOT + S3_* + extra "storage"):
python -m migracao_v1 --steps core,tenant_apps,rbac,credenciais,media
```

A ordem dos steps é fixa e imposta pelo `cli.py`/`orchestrator.py`
independente da ordem passada em `--steps` (dependências de FK):

`core` → `tenant_apps` → `rbac` → `credenciais` → (`media`, por último)

### 6. Ver o relatório

Cada execução grava em `MIGRACAO_REPORTS_DIR/<run_id>/`:
- `conciliacao.json` / `conciliacao.md` — contagens v1×v2 por entidade,
  amostra de hash de linha, itens de "conciliação manual" (FK não encontrada,
  credencial Fernet que falhou ao decriptar, arquivo de mídia não encontrado
  em disco, etc.).
- `id_map.json` — snapshot do mapa de correspondência de ids daquela execução.
- `rbac_de_para.md` (só quando o step `rbac` roda) — tabela de-para com uma
  amostra de usuários mostrando `module_permissions` original (v1) × escopos
  gerados (v2), para revisão humana (plano, item 2).

## Resultado dos testes pytest (rodado localmente, sem infra)

```
72 passed in 0.5s
```

Cobertura: transformação RBAC (`test_rbac.py`), re-cifragem Fernet→AES-GCM e
formato do jsonb esperado pelo `CipherManager::decrypt_from_jsonb` do Rust
(`test_crypto.py`), lógica do filtro `--since` (`test_delta.py`), mapa de ids
(`test_id_map.py`), mascaramento de PII e hash de conciliação
(`test_report.py`), e validação/sanity-check de todas as `TableSpec`s reais
do projeto (`test_table_specs.py`).

`tables/engine.py` (o motor que fala com o Postgres via `asyncpg`) **não tem
cobertura de pytest neste round** — não há infraestrutura de banco disponível
neste ambiente de trabalho. Antes do primeiro uso real, rode `--dry-run`
contra um Postgres de teste/staging e confira o relatório de conciliação.

## Decisões tomadas sem confirmação explícita (revisar antes do cutover real)

1. **Sempre gerar id novo (`map`) para tabelas TENANT_APPS, nunca preservar
   quando "possível".** O plano permitia preservar o id original quando não
   houvesse colisão; optei por SEMPRE usar `id_map` por uniformidade e
   simplicidade de código (uma única estratégia para todas as ~20 tabelas
   TENANT_APPS), mesmo sabendo que hoje só existe um tenant ativo em
   produção (o que tornaria a preservação segura na prática, por ora).

2. **Nomes de tabela físicos da v1** foram inferidos lendo `Meta.db_table` de
   cada model Django (não tenho acesso às migrations da v1 neste ambiente).
   Onde não há `db_table` explícito (`QueryCompose`, `CoreSettings`,
   `TenantConfig`, `Plan`, `Subscription`, `PaymentRecord`, `TenantUser`,
   `TenantInvite`, `TenantDatabase`), assumi a convenção padrão do Django
   (`app_label_nomemodeloMinusculo`) e o nome do através-table M2M
   `Cliente.contatos` como `oraculo_cliente_contatos` (Django usa
   `{db_table do modelo pai}_{nome do campo}` quando o modelo pai tem
   `db_table` explícito — `Cliente.Meta.db_table = "oraculo_cliente"`).
   **Confirme esses nomes contra o banco v1 real (ou as migrations Django)
   antes de rodar em produção** — se algum nome estiver errado, o SELECT
   falha alto e claro (não silenciosamente).

3. **`TenantDatabase` não tem app_label explícito nas `CORE_APPS`** mas mora
   no app `tenants`, que está em `CORE_APPS` — assumi a tabela
   `tenants_tenantdatabase` no banco `default`.

4. **`TenantEvolution` (credencial Evolution alternativa, Fernet, no banco
   `default`, `tenants/models.py`) NÃO foi migrada.** O plano lista
   explicitamente "as três fontes" de credencial Evolution como
   `EvolutionInstance`, `Departamento.api_key` e `AppInstance.api_key` — 
   `TenantEvolution` não está nessa lista e parece um caminho
   paralelo/superado (comentário no código sugere isso). Se ainda estiver em
   uso, precisa de um step adicional — sinalizo aqui para revisão humana.

5. **`TenantTrello` (credenciais Trello) está totalmente fora de escopo** —
   não mencionado em nenhum lugar do plano. Não migrado.

6. **RESOLVIDO (2026-07-23, revisão pós-entrega):** `whatsapp_instance.api_key`
   agora é `JSONB` de verdade (migration `0023_whatsapp_instance_api_key_
   encrypted.sql`) e o adapter Rust (`infrastructure_postgres::integracoes::
   whatsapp`) foi corrigido para usar `CipherManager::encrypt_to_json`/
   `decrypt_json_entry` — mesmo formato `{"ciphertext","nonce","tag"}` de
   `tenants_tenantconfig.api_keys`. O transform em `whatsapp_specs.py` foi
   ajustado para devolver o dict diretamente (sem `json.dumps` manual); o
   codec jsonb registrado em `db.py::conectar_v2`/`conectar_v1_default`/
   `abrir_conexao_tenant` serializa automaticamente. Também corrigido: nenhuma
   conexão asyncpg tinha codec jsonb registrado — isso quebraria em runtime
   qualquer coluna jsonb tratada como dict/list Python (`module_permissions`,
   `subscribed_events`, `metadados`, etc.), não só esta.
   (Contraste: `tenants_tenantconfig.api_keys` é `JSONB` de verdade e usa
   `decrypt_from_jsonb` — esse eu confirmei lendo `tenants/config.rs`.
   `settings_manager_coresettings.value` é `TEXT` com formato
   `"ct_b64:nonce_b64:tag_b64"` — confirmado lendo
   `tenants/settings.rs::load_all_settings`, que faz `value.splitn(3, ':')`.)

7. **`Contato.foto_perfil` (avatar) NÃO foi migrado para o R2** — só
   `Mensagem.arquivo_midia` foi implementado (reusa a convenção de chave
   `media/{tenant_id}/{instance_id}/{media_type}/{hash}[.ext]` de
   `infrastructure_storage::keys::chave_midia`). Não encontrei, na leitura
   rápida do crate `infrastructure_storage`, uma convenção de chave R2 para
   avatares — só a de mídia de mensagem e a chave plana genérica
   `StorageClient::chave` (`{tenant_id}/{file_name}`, usada para outros
   uploads gerais, sem meta de tipo/instância). Migrar `foto_perfil` exigiria
   inventar uma convenção não documentada — deixei como **TODO explícito**
   em vez de inventar. A coluna `oraculo_contato.foto_perfil` fica com o path
   relativo antigo da v1 (que não resolve para nada no v2) até essa decisão
   ser tomada.

8. **`instance_id` da chave R2 de `Mensagem.arquivo_midia` é um placeholder
   (`UUID nil`)** — o modelo v1 `Mensagem` não tem FK para uma instância
   Evolution específica (a associação, quando existe, vive solta e
   inconsistente dentro do JSON `metadados`). Revisar se há uma forma
   confiável de recuperar a instância real antes do cutover, ou se o
   placeholder é aceitável (mídia migrada não seria organizada por instância
   no bucket, só por tenant — não afeta a purga por tenant, só a purga fina
   por instância, se essa granularidade for usada em algum lugar).

9. **Tabelas sem coluna de "última atualização" real** (`oraculo_atendimento`,
   `oraculo_mensagem`, `oraculo_movimento_fluxo`, `atu_etiqueta_atendimento`,
   `atu_nota`, `oraculo_departamento`, `oraculo_etapa_fluxo`,
   `oraculo_app_instance`, `atu_etiqueta`, `treinamento_query_test_feedback`,
   `oraculo_documento`, `whatsapp.whitelist`) sempre fazem carga **completa**
   em modo `--since` (comportamento seguro por padrão do motor: sem coluna de
   controle, inclui tudo — ver `delta.py`). Isso é aceitável para reduzir
   (não eliminar) a janela de cutover, mas não é um delta "de verdade" para
   essas tabelas.

10. **Marcador de senha inutilizável**: `"!migrated-from-v1"` (convenção do
    Django, hash iniciando com `!` = inválido). Confirmado seguro contra o
    verificador Argon2id do v2 lendo
    `infrastructure_postgres/src/auth/password.rs::verify_password` — um PHC
    inválido só faz `PasswordHash::new` falhar e a função devolve `false`
    (nunca panica), forçando "credenciais inválidas" → fluxo de redefinição
    de senha.

## O que este ETL explicitamente NÃO faz

- Não reembedda vetores (`oraculo_documento.embedding`,
  `treinamento_querycompose.embedding`) — copia direto (mesma dimensão 1536,
  mesma extensão pgvector nos dois lados). Reembedding via `ia_engine` é um
  passo manual separado, só necessário se o modelo de embedding divergir.
- Não decripta/gera hash de senha da v1 — força reset de senha pós-cutover
  (decisão aprovada, ver item 10 acima).
- Não tenta detectar delta "de verdade" (CDC) — é comparação simples de
  timestamp (`--since`), com fallback seguro (inclui tudo) quando a tabela
  não tem coluna de controle.
- Não escreve NENHUM plaintext de credencial em disco ou em log — a `Secret`
  (`secret.py`) e o log estruturado (`logging_utils.py`) garantem isso por
  construção (campos sensíveis nunca aparecem em `repr()`/log; só os campos
  explicitamente listados em `log_lote` chegam ao log).
