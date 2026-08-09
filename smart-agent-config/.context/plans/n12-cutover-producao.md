---
type: plan
name: "Fase N12 — Cutover real de produção (fim do port)"
planSlug: n12-cutover-producao
description: "Fase de OPERAÇÃO, não de construção: quase todo o código já existe desde a N8 (2026-07-23) e nunca foi executado contra produção. Executa o ETL v1→v2 (infra/migracao-v1, asyncpg, idempotente, dry-run/delta, 75 testes) contra dump real e depois contra produção; fecha as quatro validações manuais pendentes da N7.5 (rajada, dashboards com tráfego real, E2E, dedupe/dead-letter), acrescidas de mídia (N9) e roteamento por instância (N11); calibra e liga SMARTCORE_QUOTA_ENFORCE; e executa a janela de cutover — carga antecipada, freeze, delta, conciliação, virada de rota no docker/edge/Caddyfile (removendo o fallback do Django), observação assistida e desligamento do legado."
summary: "Só entra com N8.5, N9, N10 e N11 fechadas — não se desliga o legado enquanto a v2 faz menos que ele. Rollback válido apenas até o freeze. Tem decisões humanas pendentes (janela, convivência, retenção do legado, comunicação da redefinição de senha)."
status: filled
progress: 0
generated: "2026-08-09"
scaffoldVersion: "2.0.0"
agents:
  - type: "devops-specialist"
    role: "Ensaio e execução do ETL, virada de rota no Caddy, observação assistida, desligamento do legado"
  - type: "database-specialist"
    role: "Conciliação por entidade, validação de amostras, restauração de dump e backup verificado"
  - type: "security-auditor"
    role: "Revisão de que credenciais decifradas não entram em log nem no relatório de conciliação"
  - type: "test-writer"
    role: "Validações manuais da N7.5 + mídia ponta a ponta + roteamento com dois números"
  - type: "architect-specialist"
    role: "Critérios de go/no-go e decisão de rollback"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "devops-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "documentation-writer"
    status: "pending"
---

# Fase N12 — Cutover real de produção

> **Última fase do port.** Depende de **N8.5, N9, N10 e N11 fechadas**.
> **Invariante:** rollback é válido **apenas até o freeze**; depois dele, o
> caminho é corrigir para frente.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n12-cutover-producao.md](./n12-cutover-producao/plano_completo_n12-cutover-producao.md)
- **Documentação auxiliar**: [info_aux_n12-cutover-producao.md](./n12-cutover-producao/info_aux_n12-cutover-producao.md)
- Runbooks: `infra/migracao-v1/RUNBOOK_CUTOVER_N8.md`, `infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md`, `infra/PROD_ROLE_CORS_N8.md`

## Etapas

| # | Entregável |
|---|---|
| E1 | Ensaio do ETL contra dump restaurado: dry-run, execução, conciliação, amostras e **medição da duração** (dimensiona a janela) |
| E2 | Fechar as 4 validações da N7.5 + mídia ponta a ponta (N9) + roteamento com dois números (N11) |
| E3 | Rollout do enforce: calibrar limites com dados reais → piloto → global |
| E4 | Janela de cutover: carga antecipada, freeze, delta, conciliação, virada de rota, observação, desligamento do legado |
| E5 | Residuais: `/admin/dead-letter`, assinaturas expirando no dashboard, retenção de mídia e CORS validados em produção |

## Armadilhas conhecidas (já resolvidas no código — reler antes de executar)
- A v1 é **DB-per-tenant**: o ETL descobre `TenantDatabase` e conecta em cada banco.
- **Colisão de `auth_user.id=1`** deixaria o ambiente sem acesso administrativo —
  corrigido; **criar o superusuário DEPOIS do ETL**.
- Codec `jsonb` no asyncpg; credenciais Fernet → AES-256-GCM com `InvalidToken`
  isolando a credencial sem abortar o lote.
- **Mídia legada** é a única coisa que não dá para reprocessar do banco.

## Critérios de go/no-go
**Go** exige: ensaio com conciliação fechando; N8.5–N11 mergeadas e validadas;
validações da N7.5 fechadas; enforce calibrado em piloto; janela acordada com
rollback escrito; backup da v1 **restaurável** (não só existente).
**No-go** se: conciliação divergente sem explicação, alerta aberto no Grafana,
mídia falhando em produção-espelho, ou enforce bloqueando tenant legítimo.

## Decisões humanas pendentes (bloqueiam a E4)
1. Data, hora e duração aceitável da janela.
2. Estratégia de convivência com o Django durante a virada.
3. Período de retenção do legado antes da remoção.
4. Comunicação aos tenants: a senha da v1 **não** é migrada utilizável — todos
   redefinem no primeiro acesso, o que **depende do e-mail da N11.7**.

## Observabilidade & Auditoria (resumo)
Auditar: `migracao.iniciada`/`.concluida` (já implementado),
`cutover.iniciado`/`.concluido`. Verbosidade elevada **temporariamente** durante
a janela, revertida ao fim. **Revisão obrigatória:** o ETL manipula credenciais
decifradas — nada disso pode entrar em log nem no relatório de conciliação.

## Definition of Done
- [ ] Domínio de produção serve a v2 na raiz; Django desligado e fallback removido.
- [ ] Conciliação fecha por entidade, com amostras validadas à mão.
- [ ] Enforce ligado sem bloqueio indevido.
- [ ] 72 h de tráfego real sem alerta aberto.
- [ ] Runbooks atualizados com o que **de fato** aconteceu na janela.
