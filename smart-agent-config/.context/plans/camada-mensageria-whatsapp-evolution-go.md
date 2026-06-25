---
type: plan
name: Módulo Rust de Mensageria WhatsApp (Evolution Go)
description: Realinhar a camada Rust de mensageria (infrastructure_evolution, data_whatsapp, webhook_ingress) do contrato Evolution API v2 para o Evolution Go (whatsmeow) que está rodando, e ampliar para a superfície completa (presença, reações, markread, download de mídia, advanced-settings, reconnect, foto de perfil). DB e ports/adapters já prontos; sem mudança de schema.
planSlug: camada-mensageria-whatsapp-evolution-go
summary: "Realinhamento da camada Rust de mensageria WhatsApp do contrato Evolution v2 (Baileys) para o Evolution Go (whatsmeow), com ampliação para a superfície completa do Go. Sem criação de crate/app e sem mudança de schema."
artifacts:
  plano_completo: ".context/plans/camada-mensageria-whatsapp-evolution-go/plano_completo_camada-mensageria-whatsapp-evolution-go.md"
  info_aux: ".context/plans/camada-mensageria-whatsapp-evolution-go/info_aux_camada-mensageria-whatsapp-evolution-go.md"
  origem_doc_dev: "doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md"
docs:
  - "architecture.md"
  - "data-flow.md"
  - "security.md"
  - "testing-strategy.md"
phases:
  - id: "phase-p"
    name: "Planning — escopo e contratos"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — arquitetura e segurança"
    prevc: "R"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-e"
    name: "Execution — realinhar + ampliar 4 componentes"
    prevc: "E"
    agent: "backend-specialist"
    required_sensors: [tests]
    required_artifacts: [handoff-summary]
    status: "pending"
  - id: "phase-v"
    name: "Validation — testes e integração real"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation — final-review e arquivamento"
    prevc: "C"
    agent: "code-reviewer"
    status: "pending"
generated: 2026-06-25
status: ready
scaffoldVersion: "2.0.0"
---

# Módulo Rust de Mensageria WhatsApp (Evolution Go)

> Realinhar a camada Rust de mensageria do contrato **Evolution API v2 (Baileys)** — escrito no
> código atual — para o **Evolution Go (whatsmeow)**, que é o servidor que está rodando, e
> ampliar para a **superfície completa** (presença, reações, recibo de leitura, download de
> mídia, advanced-settings, reconnect, foto de perfil). **Estruturado para conformidade SOLID**:
> contrato segregado em traits de capacidade (ISP), `ProviderRegistry` resolvendo `dyn` por
> instância (DIP) e registry de normalizadores no ingress (OCP) — **plugar/desplugar provedor
> sem tocar consumidores**. **Não é greenfield**: crates, apps, migração e ports/adapters já
> existem. **Sem criação de crate/app e sem mudança de schema.**

## Artefatos (fonte da verdade técnica)

- **Plano completo (detalhamento técnico + código):**
  [plano_completo](./camada-mensageria-whatsapp-evolution-go/plano_completo_camada-mensageria-whatsapp-evolution-go.md)
- **Documentação auxiliar (libs locais + contrato Evolution Go):**
  [info_aux](./camada-mensageria-whatsapp-evolution-go/info_aux_camada-mensageria-whatsapp-evolution-go.md)
- **Origem (doc_dev):** `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`
  (documento único consolidado; substituiu os dois planos-base v2 que existiam antes).
- **Plano arquivado relacionado:** `.context/plans/archive/camada-abstracao-mensageria/` (versão v2).

## Fonte da verdade do contrato Go

`old/smart-core-assistant-painel/.../evolution_sync/services/evolution_go_adapter.py`,
`.../domain/schemas.py` (canonização de eventos) e `.../services/webhook.py` — battle-tested
contra o mesmo servidor. Onde a coleta web conflitar com o adapter, **o adapter prevalece**.

## Escopo por componente (resumo — detalhes no plano completo)

| Componente | Estado hoje | Trabalho |
| --- | --- | --- |
| `infrastructure_messaging` | trait **único** de 12 métodos (v2) | **E1**: segregar em traits de capacidade (ISP) + fachada com descoberta `Option<&dyn>` + `ProviderRegistry`; ampliar p/ Go |
| `infrastructure_evolution` | fala endpoints v2 | **E2**: realinhar ao contrato Go implementando os traits segregados |
| `data_whatsapp` | `AppState` com `EvolutionProvider` **concreto** | **E3**: trocar por `ProviderRegistry` (DIP), resolve `dyn` pelo `provider` da instância; novos RPCs |
| `webhook_ingress` | `match provider` + eventos v2 lowercase | **E4**: `WebhookNormalizer` registry (OCP) + canonização de eventos Go |
| DB + ports/adapters | prontos e genéricos | **E5**: só validar (sem mudança) |
| `control_plane` | endpoint admin | **E6**: sem regressão |

> **Conformidade SOLID** (núcleo do design): ISP (traits de capacidade), DIP (`ProviderRegistry`
> resolve `dyn MessagingProvider` por instância), OCP (`WebhookNormalizer` registry), LSP
> (capacidade ausente → `Unsupported`, sem no-op). Plugar provedor = nova crate + 1 linha no
> registry + 1 normalizer; zero alteração nos consumidores.

## Fases PREVC

1. **P — Planning** (concluída): reconciliação v2→Go contra o repo real e o `evolution_go_adapter.py`;
   superfície completa do trait e eventos normalizados definidos. Saídas: info_aux + plano completo.
2. **R — Review**: R1 versões (axum 0.7.5 vs 0.8 local; reqwest 0.12); R2 segurança (SecretString,
   RLS, body truncado); R3 contrato de barramento (TenantEnvelope + transport::bus). Gate R.
3. **E — Execution**: E1 **segregar** o contrato de `infrastructure_messaging` em traits de
   capacidade (ISP) + fachada com acessores `Option<&dyn>` + `ProviderRegistry` + `Unsupported`;
   E2 `EvolutionProvider` implementa os traits contra o Go (helper `send_request`, endpoints Go,
   `map_state` ampliado, webhook embutido no `connect`); E3 `data_whatsapp` troca `AppState`
   concreto por `ProviderRegistry` (DIP), resolve `dyn` por instância, CreateWhatsappInstance via
   `connect_instance(&WebhookConfig)`, novos RPCs markread/react/presence/avatar/download/reconnect;
   E4 `webhook_ingress` `WebhookNormalizer` registry (OCP) + `canonical_event`; E5 validar DB (sem
   mudança); E6 `control_plane` sem regressão.
4. **V — Validation**: build dos 4 crates/apps; testes via `.\infra\test-local.ps1` (mocks wiremock
   atualizados v2→Go); integração manual contra o Evolution Go real (confirmar campo `base64` do
   downloadmedia); checagem de observabilidade/auditoria sem vazamento.
5. **C — Confirmation**: gate `prevc-final-review`; grep limpo de endpoints v2; commits gitflow sem
   auto-referência; arquivar planos-base v2 e este plano.

## Observabilidade & Auditoria (inviolável)

Logs/trace com `SecretString` em `skip(...)` e campos de correlação (`service`, `env`,
`tenant_id`, `trace_id`, `error_code`); auditoria `whatsapp.instance.create/delete` e
`whatsapp.admin.bulk_disconnect` via `security:stream` → `audit_log` (context sem token);
sanitização: body de erro truncado a 200 chars, body de webhook nunca logado. Detalhamento por
fase no plano completo.
