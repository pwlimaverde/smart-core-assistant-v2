# Modelagem de Dados - Smart Core Assistant v2

Este diretório contém a especificação detalhada do modelo de dados do **Smart Core Assistant v2**, mapeado a partir do sistema legado. O objetivo desta documentação é servir como referência técnica para a implementação do esquema de banco de dados no novo sistema, detalhando tabelas, tipos de dados, restrições, índices e relações.

---

## 1. Arquitetura de Banco de Dados Único (Logical Multitenancy)

O sistema adota uma arquitetura **SaaS Multitenant com Base de Dados Única** compartilhada. O isolamento lógico de dados de cada cliente (Tenant) é garantido por duas barreiras robustas:

1. **Filtro obrigatório por `tenant_id`:** Todas as tabelas de negócio do inquilino possuem uma chave estrangeira física (`tenant_id`) apontando para a tabela central de inquilinos.
2. **Row-Level Security (RLS) no PostgreSQL:** A nível de banco de dados, políticas de RLS barram acessos cruzados. Em cada transação, a aplicação configura o contexto local (`SET LOCAL app.current_tenant = tenant_id`), forçando o PostgreSQL a filtrar todas as operações DML de forma nativa e automática.

```mermaid
graph TD
    subgraph Banco de Dados Unificado (Single DB)
        subgraph Camada Core (SaaS global)
            User[django.contrib.auth.models.User]
            Tenant[Tenant]
            Config[TenantConfig]
            Plan[Plan]
            Sub[Subscription]
            Pay[PaymentRecord]
            Invite[TenantInvite]
            TUser[TenantUser]
            CoreSettings[CoreSettings]
        end

        subgraph Camada Tenant (Dados isolados logicamente por tenant_id e RLS)
            Contato[Contato]
            Cliente[Cliente]
            Atendimento[Atendimento]
            Mensagem[Mensagem]
            Dept[Departamento]
            Agent[Atendente]
            Train[Treinamento]
            Doc[Documento]
            EvoInst[EvolutionInstance]
        end
    end

    Tenant ||--|| Config : "has configuration"
    Tenant ||--o{ Contato : "owns (logical isolation)"
    Tenant ||--o{ Atendimento : "owns (logical isolation)"
    Tenant ||--o{ EvoInst : "owns (logical isolation)"
```

---

## 2. Restrições e Chaves Estrangeiras Físicas (Integridade Garantida)

Como todas as tabelas residem na **mesma base de dados física**, a integridade referencial é mantida e imposta pelo próprio motor do PostgreSQL:

1. **Constraints Físicas (`FOREIGN KEY`):**
   Relacionamentos entre tabelas de negócio do tenant (ex: `Mensagem` para `Atendimento`, `EtapaFluxo` para `FluxoAtendimento`) utilizam chaves estrangeiras físicas com comportamento `ON DELETE CASCADE` ou `ON DELETE PROTECT` ativas, garantindo consistência referencial absoluta.
2. **Relacionamento com Usuários (auth_user):**
   A tabela `operacional_atendente` e `tenants_tenantuser` possuem relacionamentos de chaves estrangeiras físicas com a tabela padrão de usuários do Django (`auth_user`), garantindo que não haja registros órfãos de colaboradores.

---

## 3. Estrutura da Documentação

A documentação detalhada da modelagem foi dividida por módulos funcionais:

1. **[Módulo Tenants & Assinaturas](./01_modulo_tenants.md)**
   * Gerenciamento de Tenants, planos, assinaturas, convites, controle de acessos de funcionários e tabelas de configuração local do Tenant (`TenantConfig`).
2. **[Módulo Clientes & Contatos](./02_modulo_clientes.md)**
   * Cadastro de contatos do WhatsApp (com normalização de telefone) e de clientes corporativos com dados fiscais (CNPJ, CPF, CEP) sob isolamento lógico.
3. **[Módulo Operacional (Estrutura de Trabalho)](./03_modulo_operacional.md)**
   * Departamentos, atendentes humanos, filas e canais Kanban locais de cada inquilino.
4. **[Módulo Atendimentos & Mensageria](./04_modulo_atendimentos.md)**
   * Atendimentos ativos, mensagens inbound/outbound, suporte a mídias, histórico de transições do Kanban e campos personalizados.
5. **[Módulo Treinamento & IA (RAG)](./05_modulo_treinamento.md)**
   * Chunks de texto vetorizados com `pgvector` (1536 dimensões), logs de feedbacks e mapeador semântico de intenções (`QueryCompose`) com filtro de tenant.
6. **[Módulo Sincronizadores & Integrações (WhatsApp)](./06_modulo_integracoes.md)**
   * Rastreamento de instâncias e contatos conectados ao único servidor Evolution API central.
7. **[Módulo Configurações Globais](./07_modulo_configuracoes.md)**
   * Definições de chaves de API globais, flags operacionais mestres do sistema e parametrizações comuns do CoreSettings.
8. **[Design de Gerenciamento de Configurações e IA](./gerenciamento_configuracoes_ia.md)**
   * Avaliação do gerenciamento legado de configurações e LLM (`ServiceHub`), e detalhamento da arquitetura em Rust com cache coordenado Redis + DashMap e ponte para o `ia_engine` Python via gRPC.
9. **[Arquitetura de Persistência (Repository Pattern)](./arquitetura_persistencia.md)**
   * Padrão Repository com crate `infrastructure_postgres`, isolamento via RLS e transações SQLx.
10. **[Módulo Central de Banco (`infrastructure_postgres`)](./modulo_central_banco.md)**
    * Organização interna da crate de persistência no workspace Rust, migrações, segurança e consumo pelos binários.
11. **[Estratégia de Implementação Rust](./estrategia_implementacao_rust.md)**
    * Stack de crates, padrão de transação RLS, cache `TenantConfigCache` com DashMap + Redis e busca vetorial pgvector.
12. **[Diretrizes de Segurança para Armazenamento de Dados Sensíveis](./08_diretrizes_seguranca.md)**
    * Isolamento RLS, criptografia AES-256-GCM com `OsRng`, proteção de PII (LGPD), segurança do Redis e checklist de code review.
13. **[Diretrizes de Controle de Acesso e Permissões (RBAC)](./09_diretrizes_permissoes_acesso.md)**
    * Catálogo canônico de escopos, `RequestContext` com `flow_permissions`, middleware JWT (HS256 explícito, `flow_permissions` via Redis), mitigações OWASP e checklist.
14. **[Módulo Auth — Autenticação e Gestão de Usuários](./10_modulo_auth_usuarios.md)**
    * Schema completo de `auth_user`, hierarquia superuser/owner/funcionário, argon2id, JWT Claims, fluxos de login/registro/convite e distinção entre lookups normais (RLS) e pré-auth (admin_pool).



---

## 4. Convenções de Banco de Dados

* **Banco de Dados Recomendado:** PostgreSQL 16+.
* **Módulo Vetorial:** Extensão `pgvector` habilitada na base de dados para busca semântica em embeddings de 1536 dimensões.
* **Criptografia de Credenciais:** Informações sensíveis (como tokens de instâncias da Evolution API e chaves de API locais em JSONB) são criptografadas antes de serem salvas no banco com chave simétrica definida em variáveis de ambiente (`ENCRYPTION_KEY`).
* **Crate de Persistência:** `server/crates/infrastructure_postgres/` — centraliza todas as queries SQLx, migrações, políticas RLS e o `TenantConfigCache` (DashMap concorrente). Nenhum outro crate conecta diretamente ao PostgreSQL.
* **Cache de Configurações:** Redis (`server/crates/infrastructure_redis/`) atua como ponte entre o backend Rust e o `ia_engine` Python. O Rust resolve os fallbacks (Tenant > CoreSettings), grava o resultado consolidado no Redis, e o Python consome sem acesso direto ao PostgreSQL.
