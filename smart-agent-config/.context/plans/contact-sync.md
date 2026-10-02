---
type: plan
name: "Sincronização de Contatos WhatsApp"
planSlug: contact-sync
description: "Sincronizar contatos do WhatsApp com o cadastro: contatos pessoais acompanham o WhatsApp automaticamente; contatos de clientes seguem o sistema (sistema ganha) e a diferença vira divergência para um humano resolver. Webhook como caminho normal, polling como reconciliação. Estende oraculo_contato, o consumidor whatsapp.contact.updated (P8), o scheduler do worker, o AdminService gRPC-Web, o mcp_server e a ContatosPage — não cria subsistema paralelo."
summary: "F0 confirma o contrato real da evolution-go (Swagger e eventos); F1 migration 0051 (origem do nome, divergências, idempotência, opt-in por conexão); F2 backend Rust (canonical_event, consumidor em lote, regra pessoal × cliente, listagem no provedor, polling, RPCs e auditoria); F3 admin.proto + gRPC-Web + tools MCP; F4 abas Pessoais/Clientes/Divergências no Flutter; F5 métricas, alertas e painel Grafana. Gate de decisões D1–D3 antes da F2. Nenhum teste roda na máquina local: CI e VPS."
status: filled
progress: 0
generated: "2026-10-02"
scaffoldVersion: "2.0.0"
agents:
  - type: "architect-specialist"
    role: "F0: confirmar contrato da evolution-go no Swagger, capturar eventos reais e fixtures; conduzir as decisões D1–D3"
  - type: "database-specialist"
    role: "F1: migration 0051, RLS das tabelas novas, regra pura decidir_sincronizacao, sqlx prepare"
  - type: "backend-specialist"
    role: "F2: webhook_ingress, worker, data_postgres, data_whatsapp, infrastructure_evolution, scheduler; F3.1: admin.proto e grpc_web.rs"
  - type: "ai-specialist"
    role: "F3.2: tools MCP no mcp_server (Python, grpc.aio)"
  - type: "frontend-specialist"
    role: "F4: abas e divergências na ContatosPage, opt-in na tela de conexões"
  - type: "security-auditor"
    role: "PII (telefone/JID/nome) fora de log, span, métrica e audit_log; SecretString do token; LGPD da importação da agenda"
  - type: "devops-specialist"
    role: "F5: métricas OTel, alertas e painel Grafana; deploy da migration só via imagem"
  - type: "test-writer"
    role: "Fixtures da F0, tabela-verdade da regra, integração RLS, testes de widget e das tools"
docs:
  - "architecture.md"
  - "data-flow.md"
  - "security.md"
  - "testing-strategy.md"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
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
lastUpdated: "2026-10-02T00:00:00.000Z"
---

# Sincronização de Contatos WhatsApp

> **Branch:** `feature/contact-sync` (a partir da `dev`, gitflow).
> **Restrição:** nenhum teste na máquina local; testes na CI, verificação no VPS de dev.
> **Estado:** planejamento concluído; revisão (R) aguarda as decisões D1–D3.

## Artefatos detalhados
- **Plano completo** (fonte da verdade técnica): [plano_completo_contact-sync.md](./contact-sync/plano_completo_contact-sync.md)
- **Documentação auxiliar**: [info_aux_contact-sync.md](./contact-sync/info_aux_contact-sync.md) — tem trechos desatualizados; ver "Correções aplicadas" no plano completo
- **Guia de execução**: [contact-sync.md](../workflow/guides/contact-sync.md)
- **Referência da evolution-go** (N9): [ref_evolution_go.md](./n9-conversa-completa/ref_evolution_go.md) — mistura contrato da Evolution v2 (Node); o Swagger da instância é quem manda

## Regra de negócio
- **Contato de cliente** (vínculo em `oraculo_cliente_contatos` ou nome digitado por humano): o sistema ganha. O WhatsApp nunca sobrescreve `nome_contato`; a diferença vira divergência pendente.
- **Contato pessoal**: `nome_contato` acompanha o WhatsApp enquanto a origem do nome for `whatsapp`.
- Campos do provedor (`nome_perfil_whatsapp`, `nome_agenda_whatsapp`, foto) sempre atualizam e nunca geram divergência.
- Criar contato a partir da agenda do aparelho: só com opt-in por conexão (D1). Sem escrita de volta no celular.

## Gate de decisões (antes da F2)

| # | Decisão | Proposta do plano | Alternativa |
|---|---|---|---|
| **D1** | Importar a agenda do aparelho? | Opt-in por conexão (`whatsapp_instance.sincronizar_agenda`, default `false`) | Nunca criar contato a partir da agenda (P8 à risca) |
| **D2** | `ip_address` no `audit_log` | `NULL` + `user_agent` preenchido; propagar IP no `Envelope` é item próprio | Incluir a propagação de IP neste plano |
| **D3** | Sobreposição com N11/E6 | Este plano fica com o **nome**; foto continua no E6 | Absorver a foto também |

A F0 e a F1 podem andar antes do gate: a F1 é aditiva e não depende da resposta de D1 (o opt-in nasce desligado).

## Fases de execução (dentro de E)

| Fase | Entrega | Duração | Depende de | Aceite |
|---|---|---|---|---|
| **F0** | Contrato real da evolution-go: rota de listagem, nomes de evento (`Contact`/`PushName`?), fixtures anonimizadas | 1 d | — | `info_aux` reescrito na seção Evolution; fixtures commitadas |
| **F1** | Migration `0051_sincronizacao_de_contatos.sql`; `decidir_sincronizacao` pura; repositórios | 2–3 d | F0 | RLS das tabelas novas provado na CI; `sqlx prepare --check` verde |
| **F2** | `canonical_event` corrigido, consumidor tipado em lote, `SincronizarContatosDoWhatsapp`, divergências, `listar_contatos` no provedor, polling no scheduler, auditoria `contato.*` | 7–9 d | F1 + gate D1–D3 | CI verde; reentrega idempotente; cliente nunca sobrescrito |
| **F3** | `admin.proto` + métodos em `grpc_web.rs` + stubs Dart/Python; tools MCP de divergência e opt-in | 3–4 d | F2 | todo RPC novo com método tonic concreto; `pytest`/`ruff`/`mypy` verdes |
| **F4** | Abas Pessoais/Clientes/Divergências; opt-in com aviso LGPD; "Sincronizar agora" | 6–7 d | F3.1 | widget tests e `flutter analyze` verdes na CI |
| **F5** | Métricas `smartcore_contato_sync_*`, alertas, painel `contatos_sync.json` | 3–4 d | F2 | painel no Grafana de dev; alertas carregados |

Ordem: F0 → F1 → F2 → F3.1 → (F4 ∥ F3.2 ∥ F5). Total ~22–27 d em série, ~17–20 d com paralelismo.

## Observabilidade e auditoria (resumo — detalhe por fase no plano completo)
- **Spans:** `contact.sync.webhook`, `contact.sync.consumir`, `contact.sync.aplicar`, `contact.sync.listar_provedor` (único com `err`: só infra), `contact.sync.polling`, `contact.divergencia.resolver`. Repositórios via `run_in_tenant_transaction` + `#[instrument(skip_all)]`.
- **audit_log:** `contato.sincronizacao_aplicada` (por lote), `contato.divergencia_detectada`, `contato.criado_da_agenda`, `contato.divergencia_resolvida`, `whatsapp_instance.sincronizacao_agenda_alterada`, `contato.sincronizacao_solicitada` — publicados pelo `data_postgres` via `AuditPort` → stream de segurança.
- **Sanitização:** token da instância em `SecretString`; telefone/JID só com 4 dígitos finais; nome de contato nunca em log/métrica/auditoria; corpo de erro do provedor truncado.

## Riscos principais
| Risco | Mitigação |
|---|---|
| Contrato da evolution-go diferente do suposto | F0 é gate de tudo |
| Tempestade de eventos na 1ª sincronia | Lote de 200, idempotência por hash, auditoria por lote |
| Migration aplicada fora do deploy (crash loop de 09/2026) | Aplicar só pela imagem; `0051` imutável depois de aplicada |
| RPC novo ausente no gRPC-Web | Teste que confere `.proto` × `impl AdminService` |
| Importação da agenda sem base legal | Opt-in desligado por padrão + aviso na tela (D1) |
