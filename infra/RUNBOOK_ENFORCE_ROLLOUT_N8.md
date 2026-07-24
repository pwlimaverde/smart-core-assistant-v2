# Runbook — Rollout do enforce de quota (N8.3)

> Este runbook é **documentação de procedimento**. Nenhuma flag foi alterada em
> nenhum `.env`/compose real ao escrever este documento — a decisão de ligar o
> enforce depende de dados reais de produção que não estavam disponíveis no
> ambiente em que este runbook foi escrito. Ver seção "Suposições e limites" no
> fim.

## 0. Contexto — o que a flag faz hoje

`SMARTCORE_QUOTA_ENFORCE` é lida via `std::env::var` (sem cache, sem
allowlist/override por tenant) em 4 binários Rust:

| Binário | Guard | Recurso |
|---|---|---|
| `data_storage` | `aplicar_quota_guard_storage` | `storage` (bloqueia upload ao R2) |
| `data_postgres` | handler de criação de departamento | `departamentos` |
| `data_whatsapp` | `aplicar_quota_guard` | `instancias` + inadimplência (bloqueia provisionamento) |
| `webhook_ingress` | checagem de inadimplência no path de ingestão | inadimplência (retorna `402` em vez de log-only) |

**É um interruptor global, não gradual.** Não existe rollout por porcentagem,
por tenant específico ou por plano no código atual — quando a flag vira
`true`, TODOS os tenants passam a ser bloqueados quando excedem quota, no
mesmo deploy. Se isso não for aceitável, um rollout gradual exigiria mudança
de código (ex.: allowlist de tenant_ids) que está fora do escopo deste
runbook — sinalizar como decisão humana antes de prosseguir se o apetite de
risco pedir um rollout mais fino.

Em modo `false` (log-only, o padrão em todo lugar até hoje) o comportamento é
fail-open e não bloqueia nada — só loga/audita conforme o recurso (ver
`infra/migracao-v1/analise-enforce/README.md` para o detalhe de cada um).

**Rate limiting (`WEBHOOK_RATE_LIMIT_MAX/WINDOW_S`,
`RUNTIME_API_RATE_LIMIT_MAX/WINDOW_S`) já está ativo/enforçando hoje** — não é
log-only e não é controlado por `SMARTCORE_QUOTA_ENFORCE` (é uma feature
separada, da N4.4/N7). O pedido original desta tarefa junta os dois sob "ligar
enforce + rate limiting ativo"; a parte de rate limiting já está ligada em
produção por padrão (`docker/prod/.env.example`: `WEBHOOK_RATE_LIMIT_MAX=120`,
`RUNTIME_API_RATE_LIMIT_MAX=300`). O que resta fazer nesta frente, se for o
caso, é **recalibrar os limiares** com os mesmos dados de produção usados para
calibrar quota — não "ligar" algo que já está ligado. Ver seção 5.

---

## 1. Rodar a análise

Ferramental completo em `infra/migracao-v1/analise-enforce/` (ver o `README.md`
daquela pasta para o detalhe de cobertura por recurso). Resumo:

```powershell
# Terminal 1 — túnel para o Postgres de produção
.\infra\tunnel.ps1 -Env prod

# Terminal 2 — análise (role BOOTSTRAP smartcore_app, não smartcore_app_rt)
$env:DATABASE_ADMIN_URL = "postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2"
.\infra\migracao-v1\analise-enforce\run_analysis.ps1
```

Isso gera dois CSVs em `infra/migracao-v1/analise-enforce/out/`:

- `01_estado_atual_quotas-*.csv` — **fonte primária**. Bloco 1: resumo por
  (plano, recurso) com contagem de tenants excedendo e distribuição do
  excesso. Bloco 2: lista nominal dos tenants que seriam bloqueados hoje.
- `02_janela_log_only_audit-*.csv` — frequência histórica via `audit_log`
  (só confiável para `instancias`, ver README da pasta).

Para `storage`/`departamentos`, complementar (opcional, menor confiança) com
as queries LogQL de
`infra/migracao-v1/analise-enforce/03_loki_logql_storage_departamentos.md`.

## 2. Derivar limites reais por plano

1. Abra o Bloco 1 do CSV (`01_estado_atual_quotas`). Para cada `(plan_name,
   recurso)` com `tenants_excedendo > 0`:
   - Se `pct_excedendo` for alto (dezenas de %) e `excesso_medio` pequeno, o
     limite do plano provavelmente está desatualizado/subdimensionado — é
     candidato a **subir o limite no `tenants_plan`** antes de ligar o
     enforce, não a bloquear os tenants.
   - Se `pct_excedendo` for baixo (poucos tenants, valores isolados) e
     `excesso_max` alto, investigar manualmente esses tenants específicos no
     Bloco 2 (lista nominal) — pode ser abuso genuíno, conta de teste
     esquecida, ou um outlier legítimo que merece um plano customizado antes
     do enforce.
2. **Nunca ligue o enforce com um recurso ainda mostrando `tenants_excedendo >
   0` sem antes revisar cada linha do Bloco 2** — cada uma delas vira um
   tenant efetivamente bloqueado (upload rejeitado / provisionamento de
   instância rejeitado / criação de departamento rejeitada) no instante em
   que a flag virar `true`.
3. Ajustar `tenants_plan.max_instances` / `max_departments` /
   `max_storage_bytes` via `data_postgres` (RPC administrativa existente, não
   escrever direto na tabela — ver `admin.proto` / handlers de planos) para
   os planos identificados no passo 1, ANTES do passo 3 abaixo.
4. Re-rodar `01_estado_atual_quotas.sql` depois do ajuste de limites para
   confirmar que `tenants_excedendo` caiu a um nível aceitável (idealmente 0,
   ou só os outliers já triados manualmente no passo 1).

## 3. Ligar `SMARTCORE_QUOTA_ENFORCE=true` em produção

Mecanismo real de deploy hoje: **docker compose** via SSH no runner
self-hosted (não systemd — apesar de `doc_dev/planejamento/10-plano-cicd-devops.md`
descrever systemd como alvo, `docker/prod/compose.yml` +
`.github/workflows/deploy-prod.yml` são o que roda hoje). Dois arquivos de
`.env` importam:

- **`/opt/smartcore/prod/env/prod.env`** no servidor Hostinger — a fonte de
  verdade real. Todo `deploy-prod.yml` faz
  `cp /opt/smartcore/prod/env/prod.env docker/prod/.env` no início do job.
  **Editar só a cópia do workspace do runner sem editar este arquivo é
  perdido no próximo deploy/tag** — sempre edite este arquivo primeiro.
- **`docker/prod/.env`** dentro do checkout do runner self-hosted (workspace
  reutilizada entre execuções, tipicamente
  `~gh-runner/actions-runner/_work/smart-core-assistant-v2/smart-core-assistant-v2/docker/prod/.env`
  — confirme o path exato no servidor, varia com a instalação do runner) — é
  a cópia que o `docker compose` efetivamente lê. Precisa ficar em sincronia
  com o arquivo acima.

Passo a passo (SSH `hostinger-root`, ou o alias configurado — ver
`infra/tunnel.ps1`):

```bash
ssh hostinger-root

# 1. Editar a fonte de verdade
sudo -u gh-runner sed -n '/SMARTCORE_QUOTA_ENFORCE/p' /opt/smartcore/prod/env/prod.env
sudo -u gh-runner sed -i 's/^SMARTCORE_QUOTA_ENFORCE=.*/SMARTCORE_QUOTA_ENFORCE=true/' /opt/smartcore/prod/env/prod.env

# 2. Sincronizar para o workspace do runner (mesmo passo que o workflow faz)
sudo -u gh-runner cp /opt/smartcore/prod/env/prod.env \
    ~gh-runner/actions-runner/_work/smart-core-assistant-v2/smart-core-assistant-v2/docker/prod/.env

# 3. Recriar SÓ os serviços que leem a flag (menor raio de impacto — ver nota
#    abaixo sobre por que nao usar "up -d" sem lista de servicos)
cd ~gh-runner/actions-runner/_work/smart-core-assistant-v2/smart-core-assistant-v2/docker/prod
sudo -u gh-runner docker compose --env-file .env up -d \
    data_postgres data_storage data_whatsapp webhook_ingress
```

**Nota importante sobre blast radius:** todos os serviços Rust em
`docker/prod/compose.yml` usam `env_file: [.env]` apontando para o MESMO
arquivo. Rodar `docker compose --env-file .env up -d` **sem** lista de
serviços recria TODOS eles (mesmo os que não leem
`SMARTCORE_QUOTA_ENFORCE` — `data_redis`, `control_plane`, `ia_engine`,
`worker`, `runtime_api`), porque o compose detecta que o hash de config de
todos mudou junto (mesmo arquivo `.env`). Passar a lista explícita de
serviços (`data_postgres data_storage data_whatsapp webhook_ingress`) evita
reiniciar o resto da stack sem necessidade.

Depois de rodar, confirme que os 4 containers subiram saudáveis:

```bash
docker compose ps data_postgres data_storage data_whatsapp webhook_ingress
docker compose logs --since=2m data_postgres data_storage data_whatsapp webhook_ingress | grep -i quota
```

### Verificação pós-rollout

- Procurar por respostas `RATE_LIMIT`/`RateLimit` (o `AppError` usado pelos
  guards ao bloquear) nos logs/traces dos 4 serviços nos primeiros minutos —
  cada ocorrência é um bloqueio real que antes era só um `warn!`.
- Repetir `01_estado_atual_quotas.sql` — o número de bloqueios observado deve
  bater com `tenants_excedendo` calculado antes do rollout (se calibrado
  corretamente na seção 2, deve ser ~0 ou só os outliers já triados).
- Confirmar no painel/CS que nenhum tenant reportou erro inesperado de
  upload/provisionamento nas primeiras horas.

## 4. Rollback rápido

Mesmo mecanismo, invertido — rápido porque não envolve rebuild de imagem, só
recriação de container com env diferente (segundos por serviço):

```bash
ssh hostinger-root

sudo -u gh-runner sed -i 's/^SMARTCORE_QUOTA_ENFORCE=.*/SMARTCORE_QUOTA_ENFORCE=false/' \
    /opt/smartcore/prod/env/prod.env
sudo -u gh-runner cp /opt/smartcore/prod/env/prod.env \
    ~gh-runner/actions-runner/_work/smart-core-assistant-v2/smart-core-assistant-v2/docker/prod/.env

cd ~gh-runner/actions-runner/_work/smart-core-assistant-v2/smart-core-assistant-v2/docker/prod
sudo -u gh-runner docker compose --env-file .env up -d \
    data_postgres data_storage data_whatsapp webhook_ingress
```

Critério de acionamento do rollback (qualquer um destes):

- Tenant legítimo reporta bloqueio inesperado (upload rejeitado,
  provisionamento de instância recusado, criação de departamento recusada)
  cuja causa raiz é limite mal calibrado, não abuso real.
- Volume de respostas `RATE_LIMIT`/`402` nos 4 serviços muito acima do
  previsto pela análise da seção 1-2 (indica que a análise ficou
  desatualizada entre a coleta e o rollout, ou que houve pico de uso legítimo
  não capturado na janela observada).
- Qualquer suspeita de que o guard está bloqueando por erro (bug), não por
  quota real excedida — nesse caso rollback primeiro, investigar depois (o
  guard é fail-open só para falha de RPC, não para bug de lógica).

Porque é um interruptor global (seção 0), o rollback também é global — reverte
o comportamento para todos os tenants de uma vez, o que é o comportamento
desejado para um rollback de emergência.

## 5. Rate limiting — recalibração (opcional, mesma janela de dados)

Já ativo por padrão (seção 0). Se a análise da seção 1 revelar tenants
legítimos batendo no rate limit com frequência (sinal indireto: não coberto
pelos scripts desta análise, que são focados em quota — checar
`audit_log`/logs de `webhook_ingress` e `runtime_api` para eventos
`rate_limited`/`login_rate_limited` na mesma janela), ajustar
`WEBHOOK_RATE_LIMIT_MAX`/`_WINDOW_S` e `RUNTIME_API_RATE_LIMIT_MAX`/`_WINDOW_S`
nos mesmos arquivos `.env` da seção 3, mesmo procedimento de
edição+sincronização+recriação seletiva (`webhook_ingress` e `runtime_api`
respectivamente).

## Suposições e limites deste runbook

- Mecanismo de deploy assumido = docker compose via runner self-hosted
  (`docker/prod/compose.yml` + `.github/workflows/deploy-prod.yml`), **não**
  systemd — confirmado lendo esses dois arquivos, mas o plano
  `doc_dev/planejamento/10-plano-cicd-devops.md` descreve systemd como alvo
  arquitetural. Se a migração para systemd acontecer antes deste rollout,
  adaptar a seção 3/4 para `systemctl restart smartcore-prod-<serviço>`
  (mesma lógica: editar o `.env`/`EnvironmentFile` do serviço, reiniciar só
  os 4 serviços afetados).
- Caminho exato do workspace do runner self-hosted (`~gh-runner/actions-runner/_work/...`)
  inferido de `doc_dev/planejamento/10-plano-cicd-devops.md` (seção do
  registro do runner, `--work _work`) — confirmar no servidor antes de
  rodar em produção (`find ~gh-runner/actions-runner/_work -maxdepth 2`).
- Este runbook não cobre `ia_engine`, `runtime_api`, `control_plane`,
  `worker`, `data_redis` porque nenhum deles lê `SMARTCORE_QUOTA_ENFORCE`
  hoje (confirmado por busca no código) — não precisam reiniciar para este
  rollout especificamente, embora um `up -d` sem lista de serviços vá
  reiniciá-los de qualquer forma (ver nota de blast radius na seção 3).
