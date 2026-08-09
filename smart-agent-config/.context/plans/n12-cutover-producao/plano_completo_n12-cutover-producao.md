# N12 — Cutover real de produção (fim do port)

> **Origem:** pendências da N8 (código pronto, execução não feita), N7.5
> (validações manuais) e N4 (enforce).
> **Natureza:** esta fase é **operação**, não construção. Quase todo o código já
> existe; o que falta é executá-lo contra produção, com janela, critérios de
> go/no-go e rollback.
> **Escala:** MEDIUM · **Depende de:** N8.5, N9, N10 e N11 **fechadas** — não se
> desliga o legado enquanto a v2 faz menos que ele.
> **Runbooks existentes:** `infra/migracao-v1/RUNBOOK_CUTOVER_N8.md`,
> `infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md`, `infra/PROD_ROLE_CORS_N8.md`.

---

## Onde estamos

Entregue na N8 (2026-07-23) e **nunca executado contra produção**:

- ETL `infra/migracao-v1/`: asyncpg, idempotente, `--dry-run`/`--since`,
  conciliação por entidade, **75 testes** de lógica pura. Cobre tenants, planos,
  assinaturas, pagamentos, usuários+RBAC (aninhado → escopos planos),
  contatos/atendimentos/mensagens (a v1 é **DB-per-tenant**: o ETL descobre
  `TenantDatabase` e conecta em cada banco físico), documentos+embeddings
  (pgvector 1536 nativo dos dois lados), credenciais (Fernet → AES-256-GCM) e
  instâncias Evolution. Etapa 7: mídia legada → R2.
- Caddy de produção com `/v2/admin` e `/v2/tenant` (`docker/edge/Caddyfile`),
  com o **Django ainda no `handle` de fallback** da raiz.
- Tooling de derivação de limites (`infra/migracao-v1/analise-enforce/`).

Correções pós-entrega já aplicadas: codec `jsonb` no asyncpg, `api_key` como
jsonb cifrado, auditoria `migracao.iniciada`/`.concluida`, e o fix de **não
sobrescrever senha válida** no `auth_user` (colisão de `id=1` entre o superusuário
da v1 e o da v2 — aconteceu em dev, deixaria produção sem acesso administrativo).

---

## E1 — Ensaio do ETL contra dump de produção

**Antes de qualquer coisa em produção**, rodar contra uma **cópia restaurada**:

1. Restaurar dump da v1 num ambiente isolado (o `infra/restore-postgres.sh`
   existe).
2. `--dry-run` completo → relatório de conciliação por entidade.
3. Rodar de verdade contra a base de teste → conciliar contagens
   (tenants, usuários, contatos, atendimentos, mensagens, documentos).
4. **Validar amostras manualmente**: uma conversa completa, um documento com
   embedding (dimensão 1536 preservada), uma credencial decifrada, um usuário com
   RBAC aninhado convertido em escopos.
5. Medir **duração** — é o que dimensiona a janela de indisponibilidade.

**Ordem obrigatória** (do runbook): criar o superusuário **depois** do ETL.

### Observabilidade & Auditoria

- **Logs:** o ETL já emite relatório por entidade; acrescentar duração por etapa
  para dimensionar a janela.
- **Auditoria:** `migracao.iniciada`/`migracao.concluida` no `audit_log` global
  (já implementado, pulado em `--dry-run`).
- **Sanitização:** o ETL manipula **credenciais decifradas** — confirmar que
  nenhuma entra em log nem no relatório de conciliação. Ponto de revisão
  obrigatório antes da execução real.

---

## E2 — Fechar as validações manuais da N7.5

Pendentes desde 2026-07-23 e **pré-condição dura** do cutover:

1. **Rajada/carga** no webhook e no bus (via túnel/`test_support`), medindo
   backlog do outbox e latência do worker.
2. **Dashboards e alertas do Grafana com tráfego real** — a stack LGTM está no
   ar e nunca foi validada com volume.
3. **E2E manual das UIs do tenant** (agora muito maior: as telas de N9–N11).
4. **Dedupe e dead-letter** observados com tráfego real.

Acrescentar, por causa das fases novas: **teste de mídia ponta a ponta**
(enviar/receber áudio, imagem e documento em produção-espelho) e **teste de
roteamento por instância** com dois números reais.

---

## E3 — Rollout do enforce de quotas

`SMARTCORE_QUOTA_ENFORCE` continua `false`. Sequência:

1. Janela log-only observada (já roda) → extrair limites reais por plano com o
   tooling de `analise-enforce/`.
2. Ajustar os limites dos planos com base no uso real (não no chute inicial).
3. Ligar o enforce **em um tenant piloto** primeiro.
4. Ligar globalmente, com alerta para `quota.excedida`.

**Atenção nova:** a N9a faz a quota de **storage** passar a morder de verdade
(antes ninguém enviava mídia). Observar essa quota especificamente antes de
ligar o enforce global.

### Observabilidade & Auditoria

- `quota.excedida` já é auditado **apenas quando o enforce bloqueia de verdade**
  (correção da N7). Manter.
- Alerta no Grafana para taxa de bloqueio por tenant — bloqueio em massa é sinal
  de limite mal calibrado, não de abuso.

---

## E4 — Janela de cutover

Do runbook, com os critérios de go/no-go:

1. **Carga antecipada** (bulk) com o sistema v1 ainda no ar.
2. **Freeze** da v1 (janela combinada com o dono do produto).
3. **Delta** (`--since`) para pegar o que mudou durante a carga.
4. **Conciliação** e checagem de amostras.
5. **Virada de rota**: remover o `handle` de fallback do Django no
   `docker/edge/Caddyfile`; a v2 passa a servir a raiz do domínio.
6. **Observação assistida** — janela de acompanhamento com o dono do produto.
7. **Rollback**: válido **só até o freeze**. Depois dele, o caminho é corrigir
   para frente (a v1 estaria desatualizada).
8. **Desligamento do legado**: parar os containers do Django, manter o dump e o
   código em `old/` por um período de retenção acordado antes de remover.

### Observabilidade & Auditoria

- **Auditoria:** `cutover.iniciado` e `cutover.concluido` no `audit_log` global.
- **Logs:** aumentar temporariamente a verbosidade do `webhook_ingress` e do
  `worker` durante a janela, e voltar ao normal depois.
- **Sanitização:** durante o cutover a tentação de logar payload inteiro para
  depurar é grande — **não fazer**. Usar `trace_id` e a auditoria.

---

## E5 — Residuais de produção

- `/admin/dead-letter` (se não tiver saído na N11.9).
- Assinaturas expirando no `GetDashboardSummary` (a v1 mostra "próximos 7 dias"
  no backoffice).
- Retenção de mídia validada em produção (lifecycle do R2 por prefixo).
- CORS de produção conferido com o domínio real (item que só se prova em prod).

---

## Critérios de go/no-go

**Go** exige todos:

- [ ] Ensaio do ETL contra dump real, com conciliação fechando por entidade.
- [ ] N8.5, N9, N10 e N11 mergeadas em `dev` e validadas.
- [ ] As quatro validações da N7.5 fechadas, mais mídia e roteamento.
- [ ] Enforce calibrado e ligado em piloto sem bloqueio indevido.
- [ ] Janela acordada, com plano de rollback escrito e testado até o freeze.
- [ ] Backup do banco da v1 verificado (restaurável, não só existente).

**No-go** se qualquer um: conciliação divergente sem explicação; alerta aberto no
Grafana; mídia falhando em produção-espelho; ou enforce bloqueando tenant
legítimo.

## Riscos

| Risco | Mitigação |
|---|---|
| ETL demorar mais que a janela | medir no ensaio (E1); carga antecipada + delta reduz a janela ao delta |
| Colisão de `id` em `auth_user` | já corrigido (`preservar_destino_quando`); criar superusuário **após** o ETL |
| Credencial não decifrar (Fernet legado) | `InvalidToken` isola a credencial sem abortar o lote; relatório lista as que falharam para refazer à mão |
| Rollback impossível após o freeze | deixar explícito no runbook; decisão de freeze é do dono do produto |
| Enforce bloquear tenant bom no dia do cutover | ligar o enforce **antes** do cutover, em janela separada — nunca no mesmo dia |
| Mídia legada não migrar (etapa 7 do ETL) | conciliar contagem de objetos no R2; mídia é a única coisa que não dá para reprocessar do banco |

## Definition of Done

- [ ] Domínio de produção serve a v2 na raiz.
- [ ] Painel Django desligado e fallback removido do Caddy.
- [ ] Conciliação do ETL fecha por entidade, com amostras validadas à mão.
- [ ] Enforce ligado sem bloqueio indevido.
- [ ] 72 h de tráfego real sem alerta aberto.
- [ ] Runbooks atualizados com o que **de fato** aconteceu na janela (não com o
      que estava planejado).
