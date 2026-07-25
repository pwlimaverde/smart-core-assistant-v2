# N8.4 — Runbook de cutover + rollback (fim do port)

> Vira a produção 100% para a v2 e desliga o legado Django. **Pré-condição
> dura:** N7 concluída (enforce validado log-only, operação observada com
> tráfego real) — não se faz cutover às cegas. Este documento é o roteiro de
> execução; ele **não foi executado** nesta rodada (escopo desta fase do N8 é
> só construir código/config — ver decisão registrada no plano).

## 0. Pré-requisitos (confirmar ANTES de agendar a janela)

- [ ] N8.1 (ETL) rodou em **carga completa antecipada** (fora da janela, ver
      seção 1) com dry-run conciliado (contagens v1×v2 batem, amostras de
      hash conferem, `conciliacao_manual` do relatório revisada e resolvida).
- [ ] N8.2 aplicado: `/v2/admin` e `/v2/tenant` respondendo no domínio real
      (`docker/edge/Caddyfile`), role `smartcore_app_rt` provisionada em
      produção (`infra/provision-db-role.sh`), CORS do R2 com a origem de
      produção (`infra/PROD_ROLE_CORS_N8.md`).
- [ ] N8.3 decidido: limites reais por plano definidos a partir da janela do
      N7 (`infra/migracao-v1/analise-enforce/`), critério de ativação do
      enforce registrado (`infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md`).
- [ ] **Rollback ensaiado com sucesso** (seção 4) em ambiente não-produtivo,
      ANTES de agendar a janela real — se o ensaio falhar, não agende.
- [ ] Critérios go/no-go abaixo aprovados pelo architect-specialist (decisão
      registrada no workflow N8, fase R).
- [ ] Janela de manutenção comunicada (duração estimada: proporcional ao
      volume do delta incremental, não da carga completa — a carga grande já
      rodou antes).

## 1. Carga antecipada (fora da janela, dias antes)

Roda a carga completa do ETL contra produção, **sem downtime** (v1 continua
servindo tráfego normalmente durante esta etapa):

```bash
# Variáveis (preencher com credenciais reais de produção — nunca commitar):
export V1_DEFAULT_DATABASE_URL="postgresql://..."   # banco `default` da v1 (Django)
export V2_DATABASE_URL="postgresql://smartcore_app:...@host:5432/smartcore_v2"  # admin (DDL/upsert), não a role _rt
export V1_ENCRYPTION_KEY="<chave Fernet da v1>"
export ENCRYPTION_KEY="<chave mestra AES-256-GCM da v2>"

cd infra/migracao-v1
pip install -e ".[dev]"

# 1. Dry-run primeiro — SEMPRE. Revisar o relatório antes de continuar.
python -m migracao_v1 --dry-run 2>&1 | tee reports/dry-run-carga-completa.log

# 2. Carga real (todos os steps exceto midia, que pode rodar em paralelo/depois)
python -m migracao_v1 2>&1 | tee reports/carga-completa.log

# 3. Mídia legada (etapa 7, opcional/separada — exige S3_* + V1_MEDIA_ROOT)
export V1_MEDIA_ROOT="/caminho/para/media/legado"
export S3_ENDPOINT="..." S3_ACCESS_KEY_ID="..." S3_SECRET_ACCESS_KEY="..." S3_BUCKET="..."
pip install -e ".[storage]"
python -m migracao_v1 --steps media 2>&1 | tee reports/media.log
```

Revisar `reports/*.json` (contagens v1×v2 por entidade, amostras de hash,
`conciliacao_manual`) antes de prosseguir. Qualquer item em
`conciliacao_manual` (credencial `InvalidToken`, FK não encontrada) precisa
de decisão humana antes do freeze — não ignorar silenciosamente.

## 2. Janela de cutover

1. **Freeze de escrita na v1**: colocar o painel Django em modo
   manutenção/somente-leitura (ou desligar os workers que escrevem, mantendo
   o Postgres up para o delta). Registrar o timestamp exato do freeze —
   **é o ponto de não-retorno do rollback** (seção 4).
2. **ETL delta** — só o que mudou desde a carga antecipada:
   ```bash
   python -m migracao_v1 --since "<timestamp-da-carga-antecipada>" 2>&1 | tee reports/delta-cutover.log
   ```
3. **Validação de conciliação** do delta (mesmo critério da seção 1) — se
   houver `conciliacao_manual` bloqueante, **abortar e rollback** (seção 4).
4. **DNS/rotas para a v2**: remover o `handle { reverse_proxy
   smartcoreassistant_app:8000 }` (fallback Django) do caminho principal em
   `docker/edge/Caddyfile`, OU simplesmente confirmar que o tráfego real já
   está sendo atendido pelos `handle_path /v2/admin/*`/`/v2/tenant/*`
   (que já têm precedência desde o N8.2) e decidir se o Django fica só como
   fallback de rotas não migradas ou é desligado de vez (próximo passo).
5. **Smoke E2E na prod v2**: admin web (`https://smartcoreassistant.com.br/v2/admin/`),
   tenant web (`.../v2/tenant/`), desktop conectando no `runtime_api` de
   produção, uma mensagem de WhatsApp de ponta a ponta (Evolution → webhook →
   worker → resposta).
6. **Ligar o enforce** (se ainda não ligado, seguindo
   `infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md`).

## 3. Critérios go/no-go (aprovados na fase R do workflow N8)

**GO** somente se TODOS:
- Dry-run/delta conciliados por entidade (contagens batem, hashes conferem,
  sem `conciliacao_manual` bloqueante).
- Rollback ensaiado com sucesso ANTES da janela real.
- Smoke E2E passa (seção 2.5).
- `.\infra\test-local.ps1` e `.\infra\test-flutter.ps1` verdes no estado
  final do código implantado.

**NO-GO** se qualquer um falhar — reverter (seção 4) e reagendar.

## 4. Rollback

**Válido SOMENTE até o ponto de freeze** registrado no passo 2.1 — depois
disso os dados da v1 e v2 divergem (a v1 não recebeu as escritas que a v2
recebeu) e "rollback" vira reconciliação manual, não uma reversão simples.

Procedimento (antes do freeze, ou se o freeze acabou de acontecer e nada
ainda mudou na v2 de forma irreversível):
1. Reverter `docker/edge/Caddyfile` para o estado anterior (Django como
   único destino, sem os `handle_path /v2/*` com precedência) — ou,  se os
   blocos `/v2/*` já estavam ativos desde o N8.2 (coexistência), não é
   necessário reverter Caddy: só tirar o Django do modo manutenção.
2. Tirar o painel Django do modo manutenção/somente-leitura.
3. **Não** desfazer os dados já escritos na v2 pelo ETL — o ETL é idempotente
   (upsert), então rodá-lo de novo mais tarde não duplica nada; os dados
   ficam lá, só não são a fonte de verdade até o próximo cutover.
4. Registrar o motivo do rollback e o timestamp no changelog/audit_log
   (`cutover.executado` com resultado `rollback`).

## 5. Desligar o legado (só após GO confirmado e smoke E2E estável por um
   período de observação — não no mesmo instante do cutover)

1. Confirmar que não há mais tráfego real no painel Django (logs de acesso
   zerados por um período razoável).
2. Desligar os containers/processos do Django (`old/paulo-ecoprint-server`
   compose) e do `smart-core-assistant-painel`.
3. Arquivar `old/` (mover para um repositório/branch de arquivo, não apagar
   direto — preserva histórico caso seja preciso consultar dados/lógica
   legados depois).
4. Registrar `cutover.executado` no audit_log global (via `admin_pool`) com
   `resultado=sucesso`, duração de cada etapa (freeze/delta/validação/virada).
5. Changelog do repositório: **encerra o backlog do port N1–N8**.

## Observabilidade & auditoria (transversal, ver plano completo)

- Log da janela: freeze, delta, validação, virada de rota — com durações.
- `cutover.executado` no audit_log global; go/no-go registrado.
- Conciliação por hash amostrado no relatório — sem dump de PII.
