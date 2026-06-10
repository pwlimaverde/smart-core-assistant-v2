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
- O `ia_engine` é stateless quanto a tenant: recebe `tenant_id` + credenciais já resolvidas em cada request gRPC; não acessa o banco multi-tenant. Conteúdo do cliente é input não confiável (anti prompt injection).

> Diretrizes completas de segurança: [seguranca.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/padroes_linguagens/seguranca.md).

## Risks & Open Decisions

- **RLS precisa ser testada rigorosamente** (migração mental de banco-por-tenant para banco único).
- **Auth/RBAC do Flutter**: protocolo final a definir antes do Runtime API.
- **Retenção de mídia**: política de expiração deve equilibrar custo × disponibilidade multi-operador/Web.
- **FFI dual-target**: somente lógica válida offline/cache entra no `local_engine` — nada multi-tenant sensível.

## Related Resources

- [Architecture](architecture.md)
- [Data Flow](data-flow.md)
