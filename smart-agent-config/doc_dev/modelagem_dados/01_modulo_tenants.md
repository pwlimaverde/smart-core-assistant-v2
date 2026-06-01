# Módulo Tenants & Configurações Globais

Este documento detalha os modelos residentes no banco de dados **default** (Core do SaaS) responsável pelo controle de inquilinos (Tenants), configurações globais do sistema, faturamento e permissões gerais de usuários administrativos.

---

## Diagrama de Entidades (Banco Default)

```mermaid
erDiagram
    User ||--o{ Tenant : "is owner of"
    Tenant ||--|| TenantDatabase : "has database configuration"
    Tenant ||--|| TenantEvolution : "has evolution configuration"
    Tenant ||--|| TenantTrello : "has trello configuration"
    Tenant ||--|| TenantConfig : "has IA configuration"
    Plan ||--o{ Subscription : "defines limits for"
    Tenant ||--|| Subscription : "has subscription"
    Tenant ||--o{ PaymentRecord : "has payments"
    Tenant ||--o{ TenantInvite : "has invites"
    Tenant ||--o{ TenantUser : "has employees"
    User ||--o{ TenantUser : "maps to"
    User ||--o{ TenantInvite : "created by"
```

---

## 1. Módulo: `tenants`

### `Tenant`
Armazena a entidade raiz de cada cliente corporativo (inquilino) do sistema.

*   **Nome da Tabela:** `tenants_tenant`
*   **Campos:**
    *   `id` (UUID, Chave Primária): Identificador único global gerado automaticamente (`uuid.uuid4`).
    *   `name` (VARCHAR(100), Não Nulo): Nome corporativo ou fantasia do inquilino.
    *   `slug` (VARCHAR(100), Não Nulo, Único): Slug identificador para rotas web e subdomínios.
    *   `api_key` (VARCHAR(100), Não Nulo, Único): Chave de API única gerada automaticamente para comunicações externas (`uuid.uuid4().hex`).
    *   `owner_id` (INT, Chave Estrangeira, Não Nulo): Relação com o modelo `auth_user` (dono da conta). Cascade ao deletar.
    *   `email` (VARCHAR(254), Opcional/Vazio): E-mail de contato principal do tenant.
    *   `phone` (VARCHAR(20), Opcional/Vazio): Telefone de contato do tenant.
    *   `active` (BOOLEAN, Padrão: `True`): Define se o tenant está ativo no ecossistema.
    *   `setup_completed` (BOOLEAN, Padrão: `False`): Se as configurações iniciais de banco de dados e integrações foram concluídas.
    *   `onboarding_step` (INTEGER, Padrão: `1`): Indica em qual etapa do onboarding inicial o tenant se encontra.
    *   `access_code` (VARCHAR(20), Opcional/Nulo): Código de acesso temporário gerado pelo administrador do sistema.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data/hora de criação do inquilino.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Data/hora da última atualização cadastral.

---

### `TenantDatabase`
Contém as credenciais e dados de conexão do banco de dados PostgreSQL isolado do tenant.

*   **Nome da Tabela:** `tenants_tenantdatabase`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo, Único): Vínculo um para um com `Tenant`. Cascade ao deletar.
    *   `host` (VARCHAR(255), Não Nulo): Host do servidor de banco de dados.
    *   `port` (INTEGER, Padrão: `5432`): Porta de conexão do PostgreSQL.
    *   `database_name` (VARCHAR(255), Não Nulo): Nome do banco de dados específico do inquilino.
    *   `username` (VARCHAR(255), Não Nulo): Nome do usuário no PostgreSQL.
    *   `_password` (VARCHAR(500), Não Nulo, Nome no banco: `password`): Senha de conexão criptografada com chave simétrica.
    *   `ssl_mode` (VARCHAR(50), Padrão: `"disable"`): Modo SSL de conexão.
    *   `connection_valid` (BOOLEAN, Padrão: `False`): Indica se o último teste de conexão obteve sucesso.
    *   `last_check` (TIMESTAMPTZ, Opcional/Nulo): Data da última verificação de integridade da conexão.
    *   `schema_version` (VARCHAR(50), Opcional/Vazio): Versão atual das migrações do banco de dados do tenant.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Data da última alteração de credenciais.
*   **Propriedades de Código:**
    *   `password`: Getter e Setter criptográficos que decodificam/codificam a string usando a chave simétrica do servidor (`ENCRYPTION_KEY`).
    *   `get_connection_string()`: Retorna a URI no padrão `postgresql://user:pass@host:port/dbname`.

---

### `TenantEvolution`
Credenciais para conexão com a Evolution API (WhatsApp) do inquilino.

*   **Nome da Tabela:** `tenants_tenantevolution`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo, Único): Vínculo um para um com `Tenant`. Cascade ao deletar.
    *   `server_url` (VARCHAR(200), Não Nulo): URL raiz do servidor Evolution API.
    *   `_api_key` (VARCHAR(500), Não Nulo, Nome no banco: `api_key`): Token de autenticação/API Key criptografado da Evolution API.
    *   `instance_name` (VARCHAR(100), Padrão: `"atendimento"`): Nome base da instância no WhatsApp.
    *   `connection_valid` (BOOLEAN, Padrão: `False`): Status de validação do token com a API.
    *   `last_check` (TIMESTAMPTZ, Opcional/Nulo): Data da última checagem de API.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Data de atualização da configuração.
*   **Propriedades de Código:**
    *   `api_key`: Getter e Setter criptográficos para a chave.

---

### `TenantTrello`
Configurações da integração da conta do Trello do inquilino.

*   **Nome da Tabela:** `tenants_tenanttrello`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo, Único): Vínculo um para um com `Tenant`. Cascade ao deletar.
    *   `_api_key` (VARCHAR(500), Não Nulo, Nome no banco: `api_key`): API Key do Trello criptografada.
    *   `_api_secret` (VARCHAR(500), Não Nulo, Nome no banco: `api_secret`): API Secret/Token do Trello criptografado.
    *   `_token` (VARCHAR(500), Não Nulo, Nome no banco: `token`): Token de autorização de leitura/escrita do Trello criptografado.
    *   `workspace_id` (VARCHAR(100), Não Nulo): ID da área de trabalho do Trello usada para a criação automática de quadros.
    *   `webhook_id` (VARCHAR(100), Opcional/Vazio): ID do webhook geral cadastrado no Trello.
    *   `webhook_callback_url` (VARCHAR(200), Opcional/Vazio): URL de callback de recebimento de webhook.
    *   `connection_valid` (BOOLEAN, Padrão: `False`): Status de comunicação do token com a API do Trello.
    *   `last_check` (TIMESTAMPTZ, Opcional/Nulo): Data do último ping.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Última atualização do registro.
*   **Propriedades de Código:**
    *   `api_key`, `api_secret`, `token`: Getters e Setters criptográficos.

---

### `TenantConfig`
Configurações de IA, prompts e branding personalizado do Tenant. Sobrescreve as chaves globais quando preenchido.

*   **Nome da Tabela:** `tenants_tenantconfig`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo, Único): Vínculo um para um com `Tenant`. Cascade ao deletar.
    *   `dados_empresa` (TEXT, Opcional/Vazio): Informações gerais da empresa para base do RAG contextual.
    *   `persona_bot` (TEXT, Opcional/Vazio): Persona e diretrizes de comportamento da LLM.
    *   `bot_agent_name` (VARCHAR(80), Opcional/Vazio): Nome de exibição do bot nos chats (ex: `*Íris:*`).
    *   `msg_fallback` (VARCHAR(500), Padrão: `"Recebemos sua mensagem. Em breve retornaremos."`): Mensagem de erro de processamento.
    *   `msg_sem_info` (VARCHAR(500), Padrão: `"Desculpe, não encontrei informações sobre isso."`): Mensagem de ausência de informações úteis nos embeddings.
    *   `msg_transferencia` (VARCHAR(500), Padrão: `"Vou transferir seu atendimento para o setor responsável."`): Mensagem exibida antes de desativar o bot e acionar humano.
    *   `entity_types` (JSONB, Padrão: `{}`): Estrutura de metadados das entidades dinâmicas que o bot deve extrair (ex: CNPJ, CEP).
    *   `llm_class` (VARCHAR(50), Opcional/Vazio): Classe da LLM (ex: `ChatGroq`, `ChatOpenAI`, `ChatOllama`).
    *   `model` (VARCHAR(100), Opcional/Vazio): Nome do modelo da LLM (ex: `gpt-4o`, `llama-3.1-70b-versatile`).
    *   `transcription_provider` (VARCHAR(50), Opcional/Vazio): Provedor de transcrição de áudios (ex: `openai`, `groq`).
    *   `transcription_model` (VARCHAR(100), Opcional/Vazio): Modelo para transcrição (ex: `whisper-1`).
    *   `vision_provider` (VARCHAR(50), Opcional/Vazio): Provedor de visão computacional (ex: `google`, `openai`).
    *   `vision_model` (VARCHAR(100), Opcional/Vazio): Modelo para interpretar mídias visuais (ex: `gemini-2.5-flash`).
    *   `api_keys` (JSONB, Padrão: `{}`): Dicionário de chaves de API criptografadas específicas do Tenant (ex: `{"groq_api_key": "...", "openai_api_key": "..."}`).
    *   `brand_name` (VARCHAR(100), Opcional/Vazio): Nome do painel personalizado.
    *   `primary_color` (VARCHAR(7), Padrão: `"#0d6efd"`): Cor primária do painel.
    *   `secondary_color` (VARCHAR(7), Padrão: `"#6c757d"`): Cor secundária do painel.
    *   `timezone` (VARCHAR(50), Padrão: `"America/Sao_Paulo"`): Fuso horário do tenant.
    *   `language_code` (VARCHAR(10), Padrão: `"pt-br"`): Idioma padrão do painel.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Data da última atualização cadastral.
*   **Métodos de Código:**
    *   `set_api_key(service, key)`: Criptografa e adiciona chave ao dicionário.
    *   `get_api_key(service)`: Descriptografa e retorna a chave de API do serviço.

---

### `Plan`
Define os planos de assinatura do SaaS comercial e seus limites operacionais.

*   **Nome da Tabela:** `tenants_plan`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `name` (VARCHAR(100), Não Nulo): Nome do plano comercial (ex: "Premium", "Enterprise").
    *   `description` (TEXT, Opcional/Vazio): Descrição detalhada do plano.
    *   `price` (NUMERIC(10, 2), Opcional/Nulo): Preço do plano em reais.
    *   `max_instances` (INTEGER, Padrão: `1`): Limite de instâncias da Evolution API permitidas (`-1` para ilimitado).
    *   `max_departments` (INTEGER, Padrão: `1`): Limite de departamentos do Kanban (`-1` para ilimitado).
    *   `active` (BOOLEAN, Padrão: `True`): Indica se o plano comercial está disponível para novas inscrições.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data de criação do plano.

---

### `Subscription`
Assinatura de um inquilino e rastreamento do faturamento/integrações de pagamento.

*   **Nome da Tabela:** `tenants_subscription`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo, Único): Vínculo um para um com `Tenant`. Cascade ao deletar.
    *   `plan_id` (INT, Chave Estrangeira, Opcional/Nulo): Vínculo com `Plan` contratado. Protege contra deleção (`on_delete=PROTECT`).
    *   `status` (VARCHAR(20), Não Nulo, Padrão: `"ACTIVE"`): Enum status do faturamento.
        *   *Opções do Enum:* `PENDING_PAYMENT` (Aguardando Pagamento), `PAYMENT_CONFIRMED` (Pagamento Confirmado), `ACTIVE` (Ativo), `PAST_DUE` (Atrasado), `SUSPENDED` (Suspenso), `CANCELLED` (Cancelado).
    *   `current_period_start` (TIMESTAMPTZ, Opcional/Nulo): Data/hora do início da vigência do faturamento ativo.
    *   `current_period_end` (TIMESTAMPTZ, Opcional/Nulo): Data/hora de encerramento da vigência/próximo vencimento.
    *   `payment_gateway` (VARCHAR(50), Opcional/Vazio): Gateway integrado (ex: `asaas`, `stripe`).
    *   `external_customer_id` (VARCHAR(100), Opcional/Vazio): ID do cliente no Gateway.
    *   `external_subscription_id` (VARCHAR(100), Opcional/Vazio): ID do contrato recorrente no Gateway.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Última atualização do registro.
*   **Métodos de Código:**
    *   `is_active() -> bool`: Verifica se a assinatura está válida (considera expiração e status).
    *   `extend_period(months)`: Estende o término da assinatura.
    *   `set_manual_period(start, end)`: Permite forçar datas de vencimento via administrativo.

---

### `PaymentRecord`
Registro histórico de lançamentos de pagamentos manuais ou reconciliados dos Tenants.

*   **Nome da Tabela:** `tenants_paymentrecord`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo): Relação com `Tenant`. Cascade ao deletar.
    *   `amount` (NUMERIC(10, 2), Não Nulo): Valor financeiro do pagamento.
    *   `payment_date` (DATE, Não Nulo): Data em que o pagamento foi realizado.
    *   `payment_method` (VARCHAR(20), Não Nulo): Forma de pagamento utilizada.
        *   *Opções do Enum:* `PIX`, `TRANSFER` (Transferência), `CASH` (Dinheiro), `BOLETO`, `OTHER` (Outro).
    *   `period_start` (DATE, Não Nulo): Início do período contratual coberto pelo pagamento.
    *   `period_end` (DATE, Não Nulo): Final do período contratual coberto pelo pagamento.
    *   `notes` (TEXT, Opcional/Vazio): Observações manuais sobre o pagamento.
    *   `recorded_by_id` (INT, Chave Estrangeira, Opcional/Nulo): ID do usuário (`auth_user`) que lançou o pagamento. Seta nulo em deleção.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data/hora do lançamento.

---

### `TenantInvite`
Estrutura para envio de convites de novos funcionários pelo painel administrativo para ingresso no espaço de trabalho do inquilino.

*   **Nome da Tabela:** `tenants_tenantinvite`
*   **Campos:**
    *   `id` (UUID, Chave Primária): UUID aleatório de convite.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo): Vínculo com `Tenant`. Cascade ao deletar.
    *   `email` (VARCHAR(254), Não Nulo): E-mail do funcionário convidado.
    *   `name` (VARCHAR(100), Não Nulo): Nome do funcionário convidado.
    *   `role` (VARCHAR(20), Padrão: `"staff"`): Cargo/Nível de permissões atribuído.
        *   *Opções do Enum:* `admin` (Administrador), `manager` (Gerente), `staff` (Funcionário), `viewer` (Visualizador).
    *   `module_permissions` (JSONB, Padrão: `{}`): Dicionário de permissões de módulos.
    *   `flow_permissions` (JSONB, Padrão: `[]`): Lista de IDs de `FluxoAtendimento` do banco do tenant liberados para o usuário (vínculo lógico, pois fluxos residem em base isolada).
    *   `token` (VARCHAR(64), Não Nulo, Único): Token gerado automaticamente via URL-safe.
    *   `expires_at` (TIMESTAMPTZ, Não Nulo): Data limite de expiração do token (padrão: 7 dias da criação).
    *   `used` (BOOLEAN, Padrão: `False`): Se o convite já foi aceito.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data de geração.
    *   `created_by_id` (INT, Chave Estrangeira, Opcional/Nulo): Usuário (`auth_user`) que gerou o convite.
*   **Métodos de Código:**
    *   `is_valid() -> bool`: Verifica se o token não expirou e não foi utilizado.

---

### `TenantUser`
Perfil de usuário/funcionário vinculado a um Tenant. Mapeia a relação entre o usuário global e o banco de dados do inquilino.

*   **Nome da Tabela:** `tenants_tenantuser`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `user_id` (INT, Chave Estrangeira, Não Nulo, Único): Um para um com `auth_user`. Cascade ao deletar.
    *   `tenant_id` (UUID, Chave Estrangeira, Não Nulo): Muitos para um com `Tenant`. Cascade ao deletar.
    *   `role` (VARCHAR(20), Padrão: `"staff"`): Nível de permissão administrativa.
        *   *Opções do Enum:* `admin` (Administrador), `manager` (Gerente), `staff` (Funcionário), `viewer` (Visualizador).
    *   `module_permissions` (JSONB, Padrão: `{}`): Permissões por módulos (ex: `{"modulo_comercial": {"view": true, "edit": false}}`).
    *   `flow_permissions` (JSONB, Padrão: `[]`): Lista lógica de IDs de fluxos de atendimento (`FluxoAtendimento`) liberados ao atendente no Kanban.
    *   `is_active` (BOOLEAN, Padrão: `True`): Indica se o funcionário está ativo no tenant.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data de contratação/ingresso.
    *   `created_by_id` (INT, Chave Estrangeira, Opcional/Nulo): Usuário administrativo que criou o vínculo.
*   **Métodos de Código:**
    *   `has_module_permission(module, action) -> bool`: Valida se o usuário pode ver, criar ou editar dados de um app específico.
    *   `has_flow_permission(flow_id) -> bool`: Valida acesso à coluna/quadro do Kanban.
    *   `allowed_flow_ids() -> list[int]`: Retorna a lista de IDs inteiros permitidos.

---

## 2. Módulo: `settings_manager`

### `CoreSettings`
Substitui as configurações globais remotas (antigo Firebase Remote Config). Define flags globais de funcionamento do ecossistema.

*   **Nome da Tabela:** `settings_manager_coresettings`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `key` (VARCHAR(255), Não Nulo, Único): Chave identificadora (ex: `OPENAI_API_KEY`).
    *   `value` (TEXT, Não Nulo): Valor da configuração associado à chave.
    *   `encrypted` (BOOLEAN, Padrão: `False`): Se ativado, descriptografa o conteúdo ao chamar `get_value()`.
    *   `description` (TEXT, Opcional/Vazio): Descrição detalhada da configuração para documentação em painel.
    *   `created_at` (TIMESTAMPTZ, Não Nulo): Data de criação.
    *   `updated_at` (TIMESTAMPTZ, Não Nulo): Data da última atualização da chave.
*   **Métodos de Código:**
    *   `get_value() -> str`: Descriptografa `value` usando a chave simétrica do servidor se `encrypted` for verdadeiro.
*   **Configurações de Ordenação:** Ordenado por `key` alfabeticamente.
