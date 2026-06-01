# Modelagem de Dados - Smart Core Assistant v2

Este diretório contém a especificação detalhada do modelo de dados do **Smart Core Assistant v2**, mapeado a partir do sistema legado. O objetivo desta documentação é servir como referência técnica para a implementação do esquema de banco de dados no novo sistema, detalhando tabelas, tipos de dados, restrições, índices e relações.

---

## 1. Arquitetura Multitenant (Cross-Database)

O sistema utiliza uma arquitetura **SaaS Multitenant com Bancos de Dados Separados** para garantir o isolamento e a segurança dos dados de cada cliente (Tenant). O banco de dados é dividido em duas camadas lógicas:

### Camada Core (Banco de Dados `default`)
Armazena dados globais do SaaS, informações administrativas e controle de acessos globais. Esta camada reside em um único banco de dados centralizado.
*   **Modelos contidos:** [Tenant](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#tenant), [TenantDatabase](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#tenantdatabase), [TenantEvolution](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#tenantevolution), [TenantTrello](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#tenanttrello), [TenantConfig](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#tenantconfig), [Plan](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#plan), [Subscription](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#subscription), [PaymentRecord](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#paymentrecord), [TenantInvite](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#tenantinvite), [TenantUser](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#tenantuser), [CoreSettings](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md#coresettings) e o modelo nativo de usuários do Django (`auth_user`).

### Camada Tenant (Banco de Dados Específico)
Cada inquilino ativo possui seu próprio banco de dados PostgreSQL. Toda a lógica de negócio, contatos, atendimentos, integrações e dados processados para IA rodam exclusivamente nessa base isolada.
*   **Modelos contidos:** Todos os demais modelos dos apps `clientes`, `operacional`, `atendimentos`, `treinamento`, `trello_sync` e `evolution_sync`.

```mermaid
graph TD
    subgraph Banco Central [Banco Central / Core - default]
        User[django.contrib.auth.models.User]
        Tenant[Tenant]
        DBConfig[TenantDatabase]
        EvoConfig[TenantEvolution]
        TrlConfig[TenantTrello]
        Config[TenantConfig]
        Plan[Plan]
        Sub[Subscription]
        Pay[PaymentRecord]
        Invite[TenantInvite]
        TUser[TenantUser]
        CoreSettings[CoreSettings]
    end

    subgraph Banco Tenant A [Banco do Tenant A - Isolado]
        ContatoA[Contato]
        ClienteA[Cliente]
        AtendimentoA[Atendimento]
        MensagemA[Mensagem]
        DeptA[Departamento]
        AgentA[Atendente]
        TrainA[Treinamento]
    end

    subgraph Banco Tenant B [Banco do Tenant B - Isolado]
        ContatoB[Contato]
        ClienteB[Cliente]
        AtendimentoB[Atendimento]
        MensagemB[Mensagem]
        DeptB[Departamento]
        AgentB[Atendente]
        TrainB[Treinamento]
    end

    Tenant -->|Conexão DB| DBConfig
    DBConfig -->|Acessa| Banco Tenant A
    DBConfig -->|Acessa| Banco Tenant B
```

---

## 2. Restrições e Chaves Estrangeiras Lógicas (Cross-Database)

Para manter a integridade referencial sem criar dependências físicas impossíveis no nível do banco de dados (já que as tabelas estão em bancos diferentes), o sistema adota duas abordagens:

1.  **Chaves Estrangeiras Lógicas (Sem Constraints Físicas):**
    Campos armazenados como inteiros normais (`BigIntegerField` ou `UUIDField`) que guardam o ID de uma tabela em outro banco de dados ou app isolado. A validação destas referências ocorre na camada de aplicação (no ORM ou nas regras de negócio).
    *   *Exemplo 1:* O `Atendente` (no banco do tenant) possui um campo `usuario_id` apontando para `auth_user` (no banco default). No ORM Django, é usado `db_constraint=False`.
    *   *Exemplo 2:* `EvolutionInstance` possui um campo `tenant_id` (UUID) para referenciar o Tenant proprietário que está na base default.
2.  **Consolidação de Tabelas de Domínio Coeso:**
    Toda a modelagem de informação de atendimento que antes se dividia entre `atendimento_unificado` e `atendimentos` foi consolidada no app central `atendimentos` para evitar acoplamento desnecessário e facilitar queries.

---

## 3. Estrutura da Documentação

A documentação detalhada da modelagem foi dividida por módulos funcionais:

1.  **[Módulo Tenants & Configurações Globais](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/01_modulo_tenants.md)**
    *   Gerenciamento de Tenants, infraestrutura de conexão de bancos, planos, assinaturas, controle de acesso e configurações de IA globais.
2.  **[Módulo Clientes & Contatos](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/02_modulo_clientes.md)**
    *   Cadastro de contatos vindos do WhatsApp (com validações de telefone) e de clientes corporativos com dados fiscais (CNPJ, CPF, CEP).
3.  **[Módulo Operacional (Estrutura de Trabalho)](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/03_modulo_operacional.md)**
    *   Departamentos, atendentes humanos, capacidade de atendimento simultâneo, fluxos de trabalho e etapas do Kanban.
4.  **[Módulo Atendimentos & Mensageria](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/04_modulo_atendimentos.md)**
    *   Atendimentos ativos, mensagens inbound/outbound, suporte a mídias, histórico de status, campos personalizados dinâmicos, tags e notas internas.
5.  **[Módulo Treinamento & IA (RAG)](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/05_modulo_treinamento.md)**
    *   Modelos de chunks de conhecimento vetorizados com `pgvector` (1536 dimensões), feedbacks de testes e controle semântico de intenções (Query Compose).
6.  **[Módulo Sincronizadores & Integrações (Trello/WhatsApp)](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_dados/06_modulo_integracoes.md)**
    *   Sincronização bidirecional com quadros do Trello e rastreamento de instâncias e eventos da Evolution API.

---

## 4. Convenções de Banco de Dados

*   **Banco de Dados Recomendado:** PostgreSQL 16+.
*   **Módulo Vetorial:** Extensão `pgvector` habilitada na base do tenant para busca semântica em embeddings de 1536 dimensões (OpenAI/text-embedding-3-small ou similar).
*   **Criptografia de Credenciais:** Informações sensíveis (senhas de banco, chaves de API do Trello e Evolution) são criptografadas antes de serem salvas no banco com chave simétrica definida em variáveis de ambiente (`ENCRYPTION_KEY`).
