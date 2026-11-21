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

## Segredos dos ambientes e governança de deploy

- **Fonte dos segredos**: secret `ENV_FILE_B64` (o `.env` inteiro, base64) do GitHub
  Environment `dev` e do `prod` — **secret de ambiente**, não de repositório: só chega ao
  job que declarou o environment e passou pelas regras dele. Cópia do `prod.env` no cofre do
  dono (sem a `ENCRYPTION_KEY` os dados cifrados se perdem).
- **Materialização** (`infra/deploy/deploy.sh`): `umask 077`, escrita atômica em
  `/opt/smartcore/<env>/env/<env>.env` (600, `gh-runner`), conteúdo decodificado nunca vai ao
  log, sem `set -x`; validação de chaves obrigatórias (`required-keys.<env>`) e proibidas
  (`COMPOSE_PROJECT_NAME`; `MINIO_*` na prod).
- **Environment `prod`**: revisor obrigatório (o dono) e implantação só a partir de tags
  `v*` e da `main`. Vale para release, rollback e infra compartilhada.
- **Rulesets**: `main` só por PR (merge commit), sem force-push/exclusão — o único bypass é a
  deploy key do runner (`/home/gh-runner/.ssh/smartcore_main_ff`), usada para o fast-forward
  pós-release; `dev` sem force-push/exclusão; tags `vX.Y.Z` só o dono cria, nenhuma tag `v*`
  é movida ou apagada.
- **Versionamento**: imagens sempre com tag exata (`X.Y.Z` / `X.Y.Z-beta.N`), nunca `latest`
  em ambiente (a CI reprova tag móvel em `docker/stack/`). O `gate-origem` do `deploy-prod`
  só aceita tag em commit com beta testada na dev ou já na `main` (hotfix).
- **Sem ambiente local**: Postgres e Redis da dev não publicam porta no host; o túnel SSH foi
  removido (uma rota de acesso direto ao banco a menos).
- **Ponto aberto**: o runner self-hosted (`gh-runner`, grupo `docker` = root efetivo) atende
  dev e prod; a contenção é o revisor do environment `prod`. Runner separado para prod é a
  decisão D3 do go-live.

> Diretrizes completas de segurança: [seguranca.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/padroes_linguagens/seguranca.md).

## Risks & Open Decisions

- **RLS já coberta por testes de integração reais** (cross-tenant negado, fail-closed); manter cobertura a cada nova tabela/policy.
- **Auth**: fundação pronta (Argon2, refresh com rotação/reuse-detection + blocklist); falta o módulo `user-auth-module` (JWT no `runtime_api`) e o RBAC do Flutter.
- **Retenção de mídia**: política de expiração deve equilibrar custo × disponibilidade multi-operador/Web.
- **FFI dual-target**: somente lógica válida offline/cache entra no `local_engine` — nada multi-tenant sensível.

## Related Resources

- [Architecture](architecture.md)
- [Data Flow](data-flow.md)
