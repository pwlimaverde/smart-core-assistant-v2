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

1. **[Módulo Tenants & Assinaturas](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md)**
   * Gerenciamento de Tenants, planos, assinaturas, convites, controle de acessos de funcionários e tabelas de configuração local do Tenant (`TenantConfig`).
2. **[Módulo Clientes & Contatos](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/02_modulo_clientes.md)**
   * Cadastro de contatos do WhatsApp (com normalização de telefone) e de clientes corporativos com dados fiscais (CNPJ, CPF, CEP) sob isolamento lógico.
3. **[Módulo Operacional (Estrutura de Trabalho)](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/03_modulo_operacional.md)**
   * Departamentos, atendentes humanos, filas e canais Kanban locais de cada inquilino.
4. **[Módulo Atendimentos & Mensageria](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/04_modulo_atendimentos.md)**
   * Atendimentos ativos, mensagens inbound/outbound, suporte a mídias, histórico de transições do Kanban e campos personalizados.
5. **[Módulo Treinamento & IA (RAG)](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/05_modulo_treinamento.md)**
   * Chunks de texto vetorizados com `pgvector` (1536 dimensões), logs de feedbacks e mapeador semântico de intenções (`QueryCompose`) com filtro de tenant.
6. **[Módulo Sincronizadores & Integrações (WhatsApp)](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/06_modulo_integracoes.md)**
   * Rastreamento de instâncias e contatos conectados ao único servidor Evolution API central.
7. **[Módulo Configurações Globais](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/07_modulo_configuracoes.md)**
   * Definições de chaves de API globais, flags operacionais mestres do sistema e parametrizações comuns do CoreSettings.
8. **[Design de Gerenciamento de Configurações e IA](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md)**
   * Avaliação do gerenciamento legado de configurações e LLM (`ServiceHub`), e detalhamento da arquitetura em Rust com cache concorrente (`DashMap`) e polimorfismo tipado (`LlmProvider`).



## 4. Convenções de Banco de Dados

* **Banco de Dados Recomendado:** PostgreSQL 16+.
* **Módulo Vetorial:** Extensão `pgvector` habilitada na base de dados para busca semântica em embeddings de 1536 dimensões.
* **Criptografia de Credenciais:** Informações sensíveis (como tokens de instâncias da Evolution API e chaves de API locais em JSONB) são criptografadas antes de serem salvas no banco com chave simétrica definida em variáveis de ambiente (`ENCRYPTION_KEY`).
