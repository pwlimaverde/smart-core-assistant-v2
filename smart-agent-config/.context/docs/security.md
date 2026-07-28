---
type: doc
name: security
description: Security policies, authentication, secrets management, and compliance requirements
category: security
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Security Model

O isolamento multi-tenant é a preocupação central. Dois mecanismos em profundidade:

1. **Filtro obrigatório por `tenant_id`** em toda consulta na aplicação (primeira barreira).
2. **Row-Level Security (RLS) do PostgreSQL** — banco recusa leitura/escrita sem `tenant_id` no contexto da sessão.

## Multi-Tenant Isolation

- `tenant_id UUID NOT NULL` em **todas** as tabelas de domínio.
- Ao abrir uma conexão: `SET app.current_tenant = '<uuid>'` antes de qualquer query.
- Policies RLS por tabela rejeitam rows sem `tenant_id` correspondente.
- Redis: namespace por tenant (`tenant:<id>:*`) em cache e presença.
- Event bus: envelope Redis Streams sempre carrega `tenant_id`; consumers validam antes de processar.
- Storage de mídia: prefixo/bucket segregado por tenant.

## Webhook Security

- `messaging_gateway` valida assinatura/origem do Evolution Go antes de processar qualquer payload.
- Payload bruto persistido antes de qualquer processamento de domínio (auditoria).
- Nunca executa regra pesada no caminho do webhook.

## Credential Handling

- Tokens, chaves de API e credenciais: **somente em variáveis de ambiente** (`.env` git-ignored).
- `.env.example` documenta variáveis necessárias sem valores reais.
- Arquivos sensíveis no `.gitignore`: `.env*`, `*.pem`, `*.key`, `credentials.json`.
- Tokens de LLM isolados no `ia_engine` via variáveis de ambiente; override por tenant via `tenant_config.api_keys` (cifradas em repouso).
- O `ia_engine` é stateless quanto a tenant e **não acessa o banco multi-tenant**. Conteúdo do cliente é input não confiável (anti prompt injection).
- **Config de tenant (incluindo chaves de LLM) trafega pelo Redis, decifrada.** O Rust resolve a cascata `TenantConfig > CoreSettings`, decifra as chaves com a `ENCRYPTION_KEY` e publica o `RuntimeConfig` em `tenant:config:<uuid>` (TTL 24h); o `ia_engine` lê de lá e mantém cópia em RAM (ver [gerenciamento_configuracoes_ia.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md), seção 4.4).
  - **Consequência aceita conscientemente**: o Redis passa a ser um armazenamento de segredos em claro, não só um cache. Antes as chaves só existiam em trânsito (payload gRPC por request).
  - **Controles que sustentam a decisão**: `REDIS_PASSWORD` obrigatório, Redis sem porta publicada no host (rede interna do compose), TTL curto e nenhum log do payload — as mensagens de erro dos dois lados citam só o tipo da exceção, nunca o conteúdo.
  - **Ao expor o Redis** (réplica gerenciada, monitoramento externo, dump de RDB para backup), tratar o dump como material de credencial: rotacionar as chaves de LLM se vazar.

> Diretrizes completas de segurança: [seguranca.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/padroes_linguagens/seguranca.md).

## Risks & Open Decisions

- **RLS já coberta por testes de integração reais** (cross-tenant negado, fail-closed); manter cobertura a cada nova tabela/policy.
- **Auth**: fundação pronta (Argon2, refresh com rotação/reuse-detection + blocklist); falta o módulo `user-auth-module` (JWT no `runtime_api`) e o RBAC do Flutter.
- **Retenção de mídia**: política de expiração deve equilibrar custo × disponibilidade multi-operador/Web.
- **FFI dual-target**: somente lógica válida offline/cache entra no `local_engine` — nada multi-tenant sensível.

## Related Resources

- [Architecture](architecture.md)
- [Data Flow](data-flow.md)
