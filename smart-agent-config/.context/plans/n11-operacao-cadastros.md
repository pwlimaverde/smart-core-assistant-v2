---
type: plan
name: "Fase N11 — Operação da conexão, roteamento e cadastros"
planSlug: n11-operacao-cadastros
description: "Dar ao tenant autonomia sobre o que hoje exige acesso ao banco ou ao painel legado. Cinco frentes: (1) sonda periódica de estado das conexões — a v1 tinha keepalive de 60s e a v2 não tem nada, mas a premissa foi corrigida: whatsmeow tem keep-alive nativo, o que falta é sondar, não forçar reconexão; (2) roteamento por conexão→departamento via AppInstance — hoje resolver_atendimento_para_contato usa buscar_primeiro_ativo e um tenant com duas conexões manda tudo para o mesmo fluxo; (3) tela de detalhe da conexão (QR fora do onboarding, ligar/desligar bot, renomear, webhook, logout); (4) whitelist gerenciável (repo existe, só leitura no webhook_ingress); (5) e-mail transacional como porta plugável — não há cliente SMTP no server/, o que bloqueia convite entregue, ativação e recuperação de senha. Mais contatos editáveis, cliente PJ (repo completo sem consumidor) e residuais de operação."
summary: "Paralelizável com N10. A alteração de maior risco de regressão de todo o backlog é o roteamento por instância (E2) — entra atrás de feature flag. O item de maior lead time é o DNS do e-mail (DKIM leva 24-48h): iniciar no dia 1."
status: filled
progress: 0
generated: "2026-08-09"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "Sonda de estado, roteamento por AppInstance, RPCs de conexão/whitelist/contatos/clientes, porta de e-mail"
  - type: "frontend-specialist"
    role: "Detalhe da conexão, whitelist, ficha do contato, clientes PJ, telas públicas de recuperação de senha"
  - type: "devops-specialist"
    role: "DNS de entregabilidade (SPF/DKIM/DMARC) e provisionamento do provedor de e-mail"
  - type: "security-auditor"
    role: "Recuperação de senha sem enumeração de e-mails, token nunca em log, QR como credencial"
  - type: "architect-specialist"
    role: "Aprovar a porta EmailSender e a estratégia de rollout do roteamento por instância"
  - type: "test-writer"
    role: "E2E de roteamento com duas instâncias e regressão do fallback"
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
    agent: "backend-specialist"
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

# Fase N11 — Operação da conexão, roteamento e cadastros

> **Depende de N8.5** (consumo do evento `CONNECTION`, que faz par com a sonda).
> **Paralelizável com N10.** ⚠️ Mesma ressalva da N9 sobre o **contrato da
> evolution-go**: a fonte da verdade é `infrastructure_evolution/src/provider.rs`,
> não a documentação da Evolution API v2.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n11-operacao-cadastros.md](./n11-operacao-cadastros/plano_completo_n11-operacao-cadastros.md)
- **Documentação auxiliar**: [info_aux_n11-operacao-cadastros.md](./n11-operacao-cadastros/info_aux_n11-operacao-cadastros.md)
- Referências brutas: [ref_evolution_go.md](./n11-operacao-cadastros/ref_evolution_go.md) · [ref_email_transacional.md](./n11-operacao-cadastros/ref_email_transacional.md)

## Origem
- [26-levantamento-paridade-v1-v2.md](../../doc_dev/planejamento/26-levantamento-paridade-v1-v2.md) §3.4 e §3.7
- [27-mapa-telas-rotas-v2.md](../../doc_dev/planejamento/27-mapa-telas-rotas-v2.md) §D.2–D.4 e §D.10

## Etapas

| # | Entregável | Risco |
|---|---|---|
| E1 | Sonda periódica de estado das conexões (30 s, com histerese antes de reconectar) | baixo |
| E2 | **Roteamento por conexão → departamento** (`AppInstance`), atrás de feature flag | **alto** |
| E3 | Tela de detalhe da conexão: QR, bot, departamento, renomear, webhook, logout | médio |
| E4 | Whitelist gerenciável (5 operações) | baixo |
| E5 | Contatos editáveis + histórico + **cliente PJ** com vínculo N:N | médio |
| E6 | Perfil do contato (nome e foto) sob demanda | baixo |
| E7 | **E-mail transacional** — porta `EmailSender` (Brevo default, SMTP alternativo) | médio |
| E8 | Recuperação de senha e reenvio de convite | médio |
| E9 | Residuais: dead-letter na borda, DI do offline, expiração de assinatura, tipos de mensagem, export/import de CoreSettings | baixo |

**Ordem:** iniciar o **DNS do e-mail no dia 1** (lead time), depois
E1 → E3 → E2 → E4 → E7 → E8 → E5 → E6 → E9.

## Decisão registrada — provedor de e-mail
Porta plugável no padrão do pagamento. **Default: Brevo** (HTTP via `reqwest`;
300/dia grátis permanente, primeiro plano pago barato, webhooks de entrega).
**Alternativa: SMTP** via `lettre` 0.11.22 (doc criada em `doc_dev/libs/rust/lettre.md`).
**SPF + DKIM são obrigatórios** desde 2026 — DKIM propaga em 24–48 h.

## Observabilidade & Auditoria (resumo)
Auditar: `whatsapp_instance.state_updated` (com `origem`), `.reconectada`,
`.departamento_vinculado`, `.bot_alterado`, `.renomeada`, `.webhook_alterado`,
`.logout`; `whitelist.adicionada`/`.alterada`/`.removida` (telefone **mascarado**);
`contato.alterado`, `cliente.*` (campo, não valor); `email.enviado`/`.falhou`
(destino mascarado); `auth.redefinicao_solicitada`, `auth.senha_redefinida`,
`convite.reenviado` (com `ip`/`user_agent`).
**Nunca em log:** QR (credencial de pareamento), token de recuperação,
`api_key` de instância, chave do provedor de e-mail, CPF/CNPJ/endereço.

## Definition of Done
- [ ] Tenant com duas conexões roteia cada uma para o seu departamento.
- [ ] Conexão caída aparece no painel sem ninguém abrir a tela.
- [ ] QR, bot, webhook, renomear e logout operáveis pela tela.
- [ ] Whitelist gerenciável e auditada.
- [ ] Convite chega por e-mail com URL absoluta; senha se recupera sozinha.
- [ ] Cliente PJ cadastrável e vinculável a contatos.
- [ ] Suítes verdes pelos scripts canônicos.
