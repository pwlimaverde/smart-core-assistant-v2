# Runbook — publicação da v2 em produção (cutover v1 → v2)

> **Nada aqui foi executado.** Este documento é procedimento; cada passo é uma
> decisão sua. Os pontos que exigem valor real (segredos) estão marcados como
> `__PREENCHER__` e não podem ser inferidos do repositório.

## 0. Estado real do servidor (verificado em 2026-07-28)

| | |
|---|---|
| Painel v1 (produção de verdade) | **no ar** — `smartcoreassistant_app` + celery + Postgres, ~7 semanas de uptime |
| Stack v2 de produção | **não existe** — só `smart-core-v2-dev-*` |
| `/opt/smartcore/prod/env/prod.env` | **não existe** (o deploy falha no primeiro passo) |
| `/opt/smartcore/prod/.env` | existe, de 16/jun, **faltam 24 variáveis** |
| Banco v1 | `smartcoreassistant_postgres` → base `smart_core_db`, 30 CoreSettings, 1 tenant ativo (`paulo-ecoprint`) |

O v1 **continua servindo** durante todo o cutover: a borda (`docker/edge`) roteia
`/v2/admin/*` e `/v2/tenant/*` para a v2 e **tudo o mais para o Django**. Subir a
v2 não derruba o v1.

---

## 1. Montar o `prod.env` (bloqueador nº 1)

O deploy executa `cp /opt/smartcore/prod/env/prod.env docker/prod/.env`. O
caminho com a subpasta `env/` é o canônico (igual ao dev); o `.env` solto na
pasta acima é resquício do padrão antigo.

```bash
ssh hostinger-root
mkdir -p /opt/smartcore/prod/env
cp /opt/smartcore/prod/.env /opt/smartcore/prod/env/prod.env   # ponto de partida
chmod 600 /opt/smartcore/prod/env/prod.env
```

Depois **acrescente as 24 variáveis ausentes**. Use
`docker/prod/.env.example` do repositório como referência — ele está completo e
comentado. As que exigem decisão sua:

| Variável | Observação |
|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | credenciais do container Postgres da v2. `POSTGRES_USER=smartcore_app` é o bootstrap (SUPERUSER) |
| `APP_RT_PASSWORD` | senha da role de runtime `smartcore_app_rt` (NOBYPASSRLS) |
| `REDIS_PASSWORD` | **obrigatória**: o Redis agora guarda as chaves de LLM decifradas (ver §5) |
| `EVOLUTION_API_URL` / `EVOLUTION_GLOBAL_API_KEY` | aponte para a stack `docker/evolution` já existente |
| `SMARTCORE_ENV=prod` | sem ela, os traces de produção saem marcados como `dev` |
| `TRANSCRIPTION_ENABLED` | kill-switch global; ver §5 |
| `SMARTCORE_IA_ENGINE_ENDPOINT=http://ia_engine:50060` | **sem ela o worker aponta para si mesmo** e nenhuma chamada de IA chega ao motor |
| `SMARTCORE_DATA_WHATSAPP_ENDPOINT` | `tcp://data_whatsapp:9107` |
| `WEBHOOK_INGRESS_PORT`, `RUNTIME_API_GRPC_WEB_ADDR`, `WEB_*_PORT`, `*_IMAGE` | valores do `.env.example` servem |
| `S3_*` | R2 de **produção** — bucket distinto do de dev |
| `SMARTCORE_QUOTA_ENFORCE`, `*_RATE_LIMIT_*` | comece em log-only; ver `RUNBOOK_ENFORCE_ROLLOUT_N8.md` |

Reaproveite do `.env` antigo: `DATABASE_URL`, `DATABASE_ADMIN_URL`,
`ENCRYPTION_KEY`, `JWT_SECRET`, `SMTP_*`, `OTEL_*`, endpoints `SMARTCORE_*`.

> **`ENCRYPTION_KEY` é crítica no cutover.** É com ela que o ETL re-cifra as
> chaves de API vindas da v1 e é com ela que o `data_postgres` as decifra. Se a
> chave usada no ETL diferir da do `.env` de produção, as chaves migram e
> **nenhuma decifra** — o sintoma é bot sem credencial, não erro de migração.

**Verificação do passo:**
```bash
# nenhuma linha deve sair
diff <(grep -oE '^[A-Z_]+=' docker/prod/.env.example | tr -d '=' | sort) \
     <(grep -oE '^[A-Z_]+=' /opt/smartcore/prod/env/prod.env | tr -d '=' | sort) \
  | grep '^<'
```

---

## 2. Subir a stack de produção

```bash
cd docker/prod
docker compose --env-file .env pull
docker compose --env-file .env up -d
```

O `data_postgres` roda as migrations no boot (inclusive a `0026_tenant_prompts`)
e, logo depois, o **pre-warm** publica a config de cada tenant ativo no Redis.

**Verificação:**
```bash
docker logs smart-core-v2-prod-data_postgres-1 | grep -i "pre-warm"
# esperado: "Pre-warm de config publicou N tenant(s) no Redis" com N > 0
```

Se `N = 0` com tenants já migrados, `DATABASE_ADMIN_URL` está ausente — a
listagem de tenants é cross-tenant e o pool de runtime não a enxerga (RLS).

---

## 3. Migrar os dados da v1 (ETL)

Ferramenta: `infra/migracao-v1` (ver o README de lá para o detalhe de cada step).

```bash
cd infra/migracao-v1
pip install -e ".[dev,storage]"

# O banco v1 e' o container `smartcoreassistant_postgres`, base `smart_core_db`.
# Ele nao publica porta no host: descubra o IP na rede do compose e abra o
# tunel, como o infra/tunnel.ps1 faz para a v2.
#   ssh hostinger-root "docker inspect -f \
#     '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' smartcoreassistant_postgres"
export V1_DEFAULT_DATABASE_URL="postgresql://postgres:__PREENCHER__@localhost:__PORTA_TUNEL_V1__/smart_core_db"
export V1_ENCRYPTION_KEY="<Fernet da v1: settings.ENCRYPTION_KEY>"
export V2_DATABASE_URL="postgresql://smartcore_app:...@localhost:5434/smartcore_v2"
export ENCRYPTION_KEY="<a MESMA do prod.env — ver aviso do §1>"

python -m migracao_v1 --dry-run          # não escreve nada
python -m migracao_v1                    # execução real
```

**O que a config traz da v1** (confirmado no banco de produção):

| | v1 (real) | default semeado na v2 |
|---|---|---|
| LLM | `ChatGoogleGenerativeAI` / `gemini-2.5-flash-lite` | `ChatOpenAI` / `gpt-4o-mini` |
| Visão | `google` / `gemini-2.5-flash-lite` | `openai` / `gpt-4o` |
| Transcrição | `groq` / `whisper-large-v3-turbo` | `openai` / `whisper-1` |
| Distância vetorial | `0.5` | `0.25` |

Sem o ETL, a v2 sobe apontando para **OpenAI com chave vazia**. As chaves da v1
estão cifradas em Fernet no banco e o ETL as re-cifra para AES-GCM; nenhum
tenant tem chave própria, então são 5 chaves globais.

> **Ordem importa: crie o superusuário DEPOIS do ETL.** A v1 tem `auth_user`
> id=1 e o primeiro superusuário criado no v2 também recebe id=1 — o upsert por
> id colidiria. O ETL hoje **preserva** senha válida já existente no destino
> (ver `preservar_destino_quando` em `core_specs.py`), mas os demais campos do
> usuário (username, email, flags) passam a refletir a v1. Criar depois evita
> a surpresa por completo.

**Verificação:**
```sql
-- as keys precisam estar em MAIÚSCULO (é como o Rust as lê)
SELECT key, encrypted FROM settings_manager_coresettings WHERE key LIKE '%API_KEY%';
```
```bash
# e a config resolvida precisa aparecer no Redis
docker exec smart-core-v2-prod-redis-1 redis-cli -a "$REDIS_PASSWORD" \
  --scan --pattern 'tenant:config:*'
```

---

## 4. Prompts do sistema

Os 30 CoreSettings da v1 incluem 11 prompts. Deles:

- **7 têm consumidor na v2** e passam a valer pela cascata
  (`PROMPT_REGRAS_RESPOSTA`, `PROMPT_INTENT_SYSTEM`, …). O texto do código é o
  default; o valor migrado da v1 o sobrescreve.
- **4 não têm** (`PROMPT_*_ANALISE_CONTEUDO`, `PROMPT_*_MELHORIA_CONTEUDO`):
  pertencem às features de curadoria de conteúdo de treinamento da v1, que a v2
  não implementou. Migram e ficam inertes até que existam.

Para ajustar um prompt sem release: edite a chave `PROMPT_*` no painel
(global) ou `tenants_tenantconfig.prompts` (por tenant). O `data_postgres`
republica no Redis e o `ia_engine` recarrega em milissegundos, sem restart.

---

## 5. Decisões conscientes antes de abrir ao público

**O Redis passa a guardar as chaves de LLM decifradas.** É o desenho do
`gerenciamento_configuracoes_ia.md` (§4.4) — antes elas só existiam em trânsito.
Exige `REDIS_PASSWORD` definida e Redis sem porta publicada no host (o compose
de prod já não publica). Um dump de RDB passa a ser material de credencial.
Registrado em `.context/docs/security.md`.

**`TRANSCRIPTION_ENABLED` é kill-switch global**, independente da cascata por
tenant. Com ele `false`, um tenant que ligue transcrição no painel recebe
resposta vazia **sem erro**. Ligue nos dois lugares ou em nenhum.

**Quota e rate limiting**: comece em log-only. Ver
`infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md`.

---

## 6. Smoke test

O deploy já executa dois automaticamente e **falha o pipeline** se algum reprovar:

- **serviços** (9 containers): estado + reinícios, e o veredito do healthcheck
  para quem o declara (hoje só o `ia_engine`, via `grpc.health.v1`);
- **borda**: `curl` no domínio público — estar `running` não prova que o Caddy
  aceitou a config e abriu a porta.

Manual, ponta a ponta: envie uma mensagem pelo WhatsApp de um tenant migrado e
confirme que a resposta reflete a **persona configurada** (é o caminho que passa
por Redis → `ia_engine` → prompt).

---

## 7. Rollback

O v1 nunca é desligado por este procedimento, então o rollback é parar a v2:

```bash
cd docker/prod && docker compose --env-file .env down
```

A borda volta a mandar tudo para o Django (as rotas `/v2/*` passam a dar 502; o
restante do site segue normal). O deploy também guarda backup do banco em
`/opt/smartcore/prod/backups/` e mantém as 5 últimas releases no GHCR — para
voltar uma versão, reimplante a tag anterior.
