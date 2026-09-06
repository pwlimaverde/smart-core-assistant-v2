---
type: plan
name: "Cadastro retomável e pagamento resolvível pelo dono"
planSlug: cadastro-retomavel-e-pagamento
description: "Sessão que expira no meio do wizard de cadastro deixa o tenant com assinatura PENDING_PAYMENT e sem caminho de volta: ao logar, o guard olha só o passo do roteiro de configuração e manda para /configuracao/*, como se estivesse pago. A tela de pagamento é pública (/cadastro/pagamento) e depende de um signup_token que morreu com a sessão — depois do login não existe rota alguma para aplicar voucher ou quitar. O tenant entra, esbarra em 'assinatura inadimplente' a cada cadastro e não tem onde resolver."
summary: "Duas correções e uma tela: o servidor passa a contar ao cliente o estado da assinatura, o guard dá precedência ao pagamento sobre o roteiro, e o dono ganha onde resolver a pendência depois de logado. Observado em produção-dev em 2026-09-06."
status: filled
progress: 0
generated: "2026-09-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "Estado da assinatura no progresso do onboarding e RPC autenticado de quitação"
  - type: "frontend-specialist"
    role: "Precedência do pagamento no guard, tela autenticada de pagamento e aviso de pendência"
  - type: "security-auditor"
    role: "Quem pode quitar (só o dono), idempotência do resgate e auditoria do evento financeiro"
  - type: "test-writer"
    role: "Regressão do beco sem saída: sessão que expira no meio do wizard"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
    required_sensors: [rust-rapido, flutter-analise-testes]
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

# Cadastro retomável e pagamento resolvível pelo dono

> **Defeito de produto, não de infraestrutura.** Nada quebra, nada loga erro: o
> tenant simplesmente não consegue usar o que comprou, e não há tela que explique
> por quê. Reproduzido em 2026-09-06 no dev, com o tenant `Paulo Ecoprint`.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_cadastro-retomavel-e-pagamento.md](./cadastro-retomavel-e-pagamento/plano_completo_cadastro-retomavel-e-pagamento.md)

## O que aconteceu

1. No wizard de cadastro, na etapa de buscar o voucher, a **sessão expirou**
   (`AUTH_INVALID_TOKEN` repetido, 13:48–13:55).
2. O cadastro recomeçou pelo login. O tenant já existia, com
   `subscription.status = PENDING_PAYMENT` e `tenant.active = false`.
3. Ao logar, o app foi **direto para `/configuracao/*`** — o guard só consulta
   `passo`/`concluido` do roteiro, e o `onboarding_step` estava em 8.
4. Nenhum cadastro funcionou: o `data_postgres` responde
   `assinatura inadimplente` a cada operação.
5. **Não há caminho para pagar.** `/cadastro/pagamento` é rota pública do wizard
   e o `ConfirmPayment` exige `signup_token` — que morreu com a sessão.

## Causa

| # | Causa | Onde |
|---|---|---|
| 1 | O progresso do onboarding não diz nada sobre dinheiro: só `passo` e `concluido` | `GetMyOnboardingProgressResponse` (admin.proto) |
| 2 | O guard decide a rota sem olhar a assinatura | `auth_redirect.dart` / `PortaoConfiguracao` |
| 3 | Quitar exige `signup_token`, que só existe durante o wizard | `ConfirmPayment` (onboarding.proto) |

O item 3 é o que transforma um contratempo em beco sem saída: sem sessão de
cadastro, **não existe RPC que o dono logado possa chamar para pagar**.

## Entregas

| Bloco | Etapas | Entregável |
|---|---|---|
| **E1** servidor | E1 | Progresso do onboarding passa a carregar o estado da assinatura |
| **E2** servidor | E2 | RPC autenticado de quitação (voucher hoje; gateway depois), restrito ao dono |
| **E3** cliente | E3 | Guard: pagamento pendente tem precedência sobre o roteiro |
| **E4** cliente | E4 | Tela de pagamento **depois do login**, visível só para o dono |
| **E5** cliente | E5 | Aviso persistente de pendência, com o caminho para resolver |

## Riscos principais

- 🚨 **Quitação é operação financeira.** O RPC novo precisa de escopo de dono
  (`tenant:admin`), auditoria (`assinatura.quitada`) e resgate idempotente — dois
  cliques não podem consumir dois resgates do voucher.
- **Não prender quem já pagou.** O guard resolve falha de consulta para "sem
  pendência", como o `PortaoConfiguracao` já faz hoje: mandar alguém pagar de
  novo por causa de uma consulta que falhou é pior que deixar entrar.
- **Colaborador não é dono.** Um funcionário do tenant não pode ver nem cobrança
  nem voucher; para ele o aviso é "fale com o responsável".

## Definition of Done

- [ ] Sessão que expira no meio do wizard é retomável: ao logar, o dono cai na
      tela de pagamento, não em `/configuracao/pronto`.
- [ ] O dono aplica voucher **logado**, sem `signup_token`, e a assinatura ativa.
- [ ] Colaborador sem `tenant:admin` não vê a tela nem o RPC responde a ele.
- [ ] Resgate idempotente: repetir não consome dois usos do voucher.
- [ ] `assinatura.quitada` na trilha de auditoria, com autor e meio.
- [ ] Sensores `rust-rapido` e `flutter-analise-testes` verdes.
