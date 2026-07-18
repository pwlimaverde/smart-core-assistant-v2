# Documentação Auxiliar — Fase N8: Migração v1→v2 + cutover de produção

> Gerado em: 2026-07-18
> Plano canônico: `.context/plans/n8-migracao-e-cutover.md`
> Plano completo: `.context/plans/n8-migracao-e-cutover/plano_completo_n8-migracao-e-cutover.md`
> Origem: `doc_dev/planejamento/23-fase-N8-migracao-e-cutover.md` (histórico).

Fase final do port: migrar os dados do legado Django (`old/paulo-ecoprint-server`,
`old/smart-core-assistant-painel`) para a v2, habilitar a produção web completa e
**desligar o legado**. É majoritariamente **ops + ETL**, com pouca lib nova — a
única dependência externa nova é a leitura das credenciais Fernet da v1.

---

## Achados no código (aterramento — destinos da migração)

### Criptografia — destino da recodificação (N8.1 item 5)
`server/crates/infrastructure_postgres/src/crypto.rs`: `CipherManager` (AES-256-GCM)
carrega a chave mestra de `ENCRYPTION_KEY` (base64, **32 bytes**), e
`encrypt(plaintext: &[u8]) -> (ciphertext_b64, nonce_b64, tag_b64)`. As chaves de
API do tenant são guardadas num **jsonb** `api_keys` no formato
`{ "<nome>": { "ciphertext", "nonce", "tag" } }` (ver `decrypt_from_jsonb`). Debug
do `CipherManager` é `[REDACTED]` (chave nunca vaza em log).

> **Fluxo do ETL:** Fernet(v1).decrypt(token) → bytes em claro (memória) →
> `CipherManager::encrypt` → grava `{ciphertext,nonce,tag}` no jsonb da v2. O
> plaintext nunca toca disco/log. Ver `doc_dev/libs/python/cryptography.md`.

### RBAC — destino dos escopos planos (N8.1 item 2)
A N3 decidiu escopos **planos** (formato do `derivar_escopos`), enquanto a v1 tem
RBAC **aninhado por módulo**. O ETL de usuários/permissões precisa aplicar a mesma
transformação `aninhado → escopos planos + flow_permissions`. `derivar_escopos`
aparece em `application/src/auth/login.rs`/`refresh.rs` — é a fonte da verdade do
shape de escopo que o ETL deve produzir.

### Produção web — habilitação, não construção (N8.2)
`infra/caddy/tenant.caddy`: o bloco **DEV** está ativo (`dev.smartcoreassistant.com.br`,
`/v2/tenant/*` estático + gRPC-Web em `localhost:50051`); o bloco **PROD** está
**comentado** (linhas 51-71). Hoje `smartcoreassistant.com.br` serve o **painel
Django legado** (reverse_proxy para `172.18.0.5:8000`). Habilitar o tenant em prod
exige inserir um `handle /v2/tenant/*` **ANTES** do reverse_proxy do Django naquele
site block — alteração de config de sistema em produção (fazer com cuidado). O
`admin.caddy` segue o mesmo padrão. CORS do R2 (`S3_CORS_ALLOWED_ORIGINS` /
`infra/r2-cors.json`, N5.3) precisa dos valores **de produção**.

### Enforce de quotas — rollout é decisão do N8.3
`SMARTCORE_QUOTA_ENFORCE=false` em todo lugar (log-only desde a N4, mesma flag que
o N7.1 estende para storage/departamentos). Ligar para `true` (+ rate limiting
ativo) é decisão do N8.3, **com os dados da janela de observação do N7**.

### Embeddings — pgvector 1536 dos dois lados
`Documento`/`QueryCompose` portados usam pgvector 1536 (`doc_dev/libs/{rust,python}/pgvector.md`).
Migração direta é possível; **revalidar modelo/dimensão** — se o modelo de embedding
da v1 divergir, reembeddar via `ia_engine` (batch).

---

## Rastreabilidade v1→v2 (base do escopo do ETL)

O **Apêndice B** de `doc_dev/planejamento/02-fases-desenvolvimento.md` mapeia cada
domínio da v1 ao componente v2 (linha de ETL v1→v2 adicionada na atualização de
2026-07-17). É a lista canônica de entidades a migrar:

1. **Tenants, planos, assinaturas, pagamentos** — schema de planos já existe
   (`0003_plans_subscriptions.sql`); N7.1 adiciona `max_storage_bytes`.
2. **Usuários + RBAC** — aninhado (v1) → escopos planos + `flow_permissions` (v2).
3. **Contatos, atendimentos, mensagens/histórico** — ids preservados **ou** mapa de
   correspondência persistido (para não quebrar referências).
4. **Documentos de treinamento + embeddings** — pgvector; revalidar modelo/dimensão.
5. **Configs de tenant + credenciais** — Fernet (v1) → AES-256-GCM (`CipherManager`).
6. **Instâncias Evolution** — tokens/instâncias re-registrados ou migrados (validar
   health por instância pós-migração via `data_whatsapp`).

---

## Libs / serviços (Grupo A + B)

### Python — `cryptography` / Fernet (novo → doc central criado)
Doc central: `doc_dev/libs/python/cryptography.md` (criado 2026-07-18, via Context7).
- `Fernet(key).decrypt(token) -> bytes`; `MultiFernet([...])` se a v1 rotacionou
  chaves; `InvalidToken` tratada **por credencial** (isola falha, alimenta a
  conciliação), sem abortar o lote.
- **Não** entra no runtime do `ia_engine` — dependência exclusiva do script de ETL
  em `infra/migracao-v1/`.
- Regras: plaintext só em memória, o mínimo de tempo; logs só com ids/contagens.

### Libs USAR LOCAL (reaproveitadas da central)
| Lib | Doc central | Uso no N8 |
|-----|-------------|-----------|
| `aes_gcm` | `doc_dev/libs/rust/aes_gcm.md` | destino da recifragem (via `CipherManager`) |
| `secrecy` | `doc_dev/libs/rust/secrecy.md` | credenciais em `SecretString` no fluxo |
| `pgvector` (rust+py) | `doc_dev/libs/{rust,python}/pgvector.md` | migração/validação de embeddings 1536 |
| `aws_sdk_s3` | `doc_dev/libs/rust/aws_sdk_s3.md` | R2 prod (CORS/lifecycle) via `data_storage` |
| `langchain` / `langchain_google_genai` | `doc_dev/libs/python/*` | reembeddar se modelo divergir |

### Serviços externos (Grupo B)
- **Caddy** (reverse proxy prod) — habilitar blocos `/v2/admin` e `/v2/tenant`;
  `caddy validate` + `systemctl reload` (config em `infra/caddy/*.caddy`).
- **Cloudflare R2** — CORS/lifecycle com valores de prod (já dominado em N4/N5;
  `S3_CORS_ALLOWED_ORIGINS`, `infra/r2-cors.json`).
- **Evolution GO (WhatsApp)** — re-registro/validação de instâncias (health por
  instância). Já documentado nas fases anteriores.
- **DNS/rotas** — apontar produção para a v2 na janela de cutover (com rollback).
- **Postgres prod** — provisionar a role não-superuser `smartcore_app_rt`
  (`infra/provision-db-role.sh`, entregue na N4) no banco de produção.

---

## Grupo C — Observabilidade e Auditoria (transversal)

| Etapa | Log/Trace | audit_log | Sanitização |
|-------|-----------|-----------|-------------|
| N8.1 ETL (por lote) | log estruturado por entidade/lote: contagens, ids min/max, duração | `migracao.iniciada`/`migracao.concluida` no audit_log global (via `admin_pool`) | **sem PII em claro** — telefones mascarados; credenciais/tokens nunca logados |
| N8.1 credenciais | só id da credencial + ok/falha | falha de `InvalidToken` registrada por id | plaintext nunca em disco/log; Fernet key via secret |
| N8.2 prod web | logs do Caddy/data_storage já existentes | mudança de rota é ops (registrar no changelog/runbook) | N/A |
| N8.3 rollout enforce | contador `quota.excedida` (do N7) vira base da decisão | ativação de enforce registrada (mudança de política) | só limites/ids |
| N8.4 cutover | log da janela (freeze/delta/validação) | `cutover.executado` no audit_log global | conciliação por hash amostrado, sem dump de PII |

---

## Notas gerais / gotchas
- **ETL idempotente + dry-run:** scripts versionados em `infra/migracao-v1/`, com
  relatório de conciliação por entidade (contagem v1 × v2 + amostragem de hash).
- **Duas passadas:** carga completa antecipada + **delta incremental** na janela
  (reduz downtime para históricos grandes).
- **RBAC revisado por humano:** tabela de-para conferida lado a lado no dry-run
  (risco de usuário com mais/menos permissão que na v1).
- **Rollback ensaiado ANTES da janela:** critérios go/no-go definidos previamente;
  rollback só até o ponto de freeze (voltar rotas ao Django).
- **Recifragem verificada ativamente:** health por instância Evolution pós-migração
  (recifrar em silêncio e quebrar a instância é o pior caso).
- **Não fazer cutover às cegas:** N7 concluída (enforce validado log-only, operação
  observada) é pré-condição dura.
