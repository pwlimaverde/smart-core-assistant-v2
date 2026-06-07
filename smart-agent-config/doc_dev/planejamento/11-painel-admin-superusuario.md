# 11 — Painel Gerencial do Superusuário (Admin Panel)

> **Status:** ⬜ Planejado — primeira feature de negócio pós-fundação.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Referência v1:** `old/smart-core-assistant-painel/` — Django admin como especificação
> funcional. Toda funcionalidade mapeada abaixo deriva da análise desse código.

---

## 1. Objetivo

Construir um painel web/desktop para o **superusuário** equivalente ao Django admin da
v1, porém nativo à arquitetura v2 (Rust + Flutter). O painel permite ao superusuário
gerenciar tenants, planos, assinaturas, pagamentos e configurações globais — sem precisar
de acesso direto ao banco.

**Princípio arquitetural:** o Flutter admin fala **exclusivamente com `runtime_api`** via
gRPC. O `runtime_api` valida o JWT (superusuário), e repassa ao `data_postgres` e ao
`control_plane` via RPC interno. Nenhuma tela acessa a infraestrutura diretamente.

---

## 2. Pré-requisitos (dependências de fase)

O painel exige que as seguintes peças estejam prontas antes de ser construído:

| Pré-requisito | Onde | Por quê |
|---|---|---|
| `runtime_api` com Tonic | F6.1 | gateway gRPC do painel |
| `AuthService` (Login/Refresh/Logout) | F6.1 | superusuário precisa autenticar |
| `AuthInterceptor` com role check | F6.2 | rotas admin exigem `is_superuser = true` |
| `control_plane` CRUD de tenant/plano | F2 (admin) | backend das telas de gestão |
| `data_postgres` com repos prontos | ✅ feito | persistência já existe |

**Ordem de construção:**
```
F6.1 AuthService (Login/Logout/Refresh)
  └─ F6.2 AuthInterceptor (is_superuser role guard)
      └─ F2-admin: control_plane → runtime_api endpoints de admin
          └─ Flutter admin: telas P1 → P2 → P3 → P4
```

---

## 3. Mapeamento do Django Admin v1 → Telas v2

### P1 — Gestão Core (prioridade máxima)

#### 3.1 Dashboard de Tenants

**Equivalente Django:** `TenantAdmin` com `list_display`, filtros e actions.

| Campo | Tipo | Notas |
|---|---|---|
| name | texto | nome do tenant |
| slug | texto | identificador URL |
| owner | FK → auth_user | dono do tenant |
| active | bool | toggle rápido |
| subscription_status | enum colorido | ACTIVE(verde) / PAST_DUE(laranja) / SUSPENDED(vermelho) / CANCELLED(cinza) |
| days_until_expiration | int calculado | contador regressivo; vermelho < 7, amarelo < 30 |
| created_at | data | |

**Ações em bulk:**
- Estender assinatura (30 dias / 6 meses / 12 meses)
- Ativar tenants selecionados
- Suspender tenants selecionados
- Gerar e enviar código de acesso por e-mail (código 6-char, ex.: `A3X-9Y2`)

**Filtros:** status da assinatura, data de criação, data de expiração.
**Busca:** name, slug, owner username/email.

---

#### 3.2 Detalhe do Tenant (Form completo)

Tela de criação/edição com seções colapsáveis (equivalente aos `fieldsets` Django):

**Seção: Identificação**
- name, slug (auto-gerado), owner (select de auth_user), active

**Seção: Contato**
- email, phone

**Seção: Credenciais** (somente leitura)
- id (UUID), api_key (gerada, exibida mascarada)

**Sub-recursos inline (abas ou cards expansíveis):**

| Recurso | Campos Principais |
|---|---|
| **TenantConfig** | LLM: llm_class, model, transcription_provider, vision_provider, temperatura |
| | Bot: dados_empresa (textarea), persona_bot, bot_agent_name |
| | Mensagens automáticas: msg_fallback, msg_sem_info, msg_transferencia |
| | API Keys (encriptadas): groq_api_key, openai_api_key |
| | Branding: brand_name, primary_color, secondary_color, timezone, language_code |
| **TenantEvolution** | server_url, api_key (encriptada), instance_name, connection_valid, last_check |
| **TenantDatabase** | host, port, database_name, username, password (encriptado), ssl_mode, connection_valid |
| **Subscription** | plan (select), status, current_period_start, current_period_end, payment_gateway, external_ids |
| **PaymentRecord** (lista) | lista de pagamentos com botão "Registrar Pagamento" |

---

#### 3.3 Registro de Pagamento Manual

**Equivalente Django:** `RegisterPaymentView` (form dedicado fora do admin padrão).

Formulário dedicado acessível via botão no detalhe do tenant:
- `payment_date` (DateField, padrão hoje)
- `amount` (Decimal, ≥ 0,01)
- `payment_method` (enum: PIX | TRANSFER | CASH | BOLETO | OTHER)
- `period_start` / `period_end` (DateField — período coberto pelo pagamento)
- `notes` (textarea livre)

**Efeito ao salvar:**
1. Cria `PaymentRecord` (tenant_id, amount, method, datas, notes, registrado por)
2. Atualiza `Subscription.current_period_end` via `set_manual_period(start, end)`
3. Exibe confirmação com novo status da assinatura

---

#### 3.4 Gestão de Planos Comerciais

**Equivalente Django:** `PlanAdmin`.

| Campo | Tipo |
|---|---|
| name | texto |
| description | textarea |
| price | Decimal |
| max_instances | int (-1 = ilimitado) |
| max_departments | int (-1 = ilimitado) |
| active | bool |

**Lista:** name, max_instances, max_departments, active, price.
**Ações:** criar, editar, ativar/desativar, excluir (proteção: não excluir plano com assinaturas ativas).

---

#### 3.5 Gestão de Assinaturas

**Equivalente Django:** `SubscriptionAdmin` dedicado.

Visão independente da lista de tenants para filtrar assinaturas por status, plano e
período de expiração.

| Campo | Tipo |
|---|---|
| tenant | FK |
| plan | FK |
| status | enum colorido |
| current_period_start | data |
| current_period_end | data |
| payment_gateway | texto |
| external_customer_id | texto |
| external_subscription_id | texto |

**Filtros:** status, plan, current_period_end.
**Hierarquia de data:** current_period_end.

---

#### 3.6 Histórico de Pagamentos

**Equivalente Django:** `PaymentRecordAdmin` dedicado.

Visão consolidada de todos os pagamentos registrados:

| Campo | Tipo |
|---|---|
| tenant | FK |
| payment_date | data |
| amount | Decimal |
| payment_method | enum |
| period_start → period_end | datas |
| notes | texto |
| recorded_by | FK → auth_user |

**Filtros:** payment_method, payment_date.
**Exportação CSV:** por período (todos os pagamentos do intervalo selecionado).

---

### P2 — Configuração do Tenant (prioridade alta)

#### 3.7 TenantConfig — Configurações de IA e Branding

Subtela de configuração acessível via tab no detalhe do tenant:

**LLM Settings:**
- `llm_class` (select: groq, openai, anthropic, local)
- `model` (texto — modelo específico)
- `llm_temperature` (slider 0.0–2.0)
- `transcription_provider` + `transcription_model`
- `vision_provider` + `vision_model`

**Bot Persona:**
- `dados_empresa` (textarea grande — contexto da empresa para o LLM)
- `persona_bot` (textarea — identidade/comportamento do bot)
- `bot_agent_name` (texto — nome exibido no WhatsApp)

**Mensagens Automáticas:**
- `msg_fallback` — resposta quando não há informação
- `msg_sem_info` — fora do escopo
- `msg_transferencia` — transferência para humano

**Entidades Personalizadas:**
- `entity_types` (editor JSON — tipos de entidade customizados para extração)

**API Keys (encriptadas no banco, exibição mascarada):**
- groq_api_key, openai_api_key (JSON bag)
- `ENCRYPTION_KEY` do servidor cifra antes de persistir; painel nunca recebe o valor real

**Branding:**
- `brand_name`, `primary_color` (color picker), `secondary_color`
- `timezone` (select IANA), `language_code`

---

#### 3.8 Integração Evolution (TenantEvolution)

- `server_url` (URL da instância Evolution Go)
- `api_key` (encriptado — campo sensível)
- `instance_name`
- `connection_valid` (bool, somente leitura — resultado do último teste)
- `last_check` (datetime, somente leitura)
- Botão **"Testar Conexão"** → dispara RPC `TestEvolutionConnection` → atualiza
  `connection_valid` e `last_check` em tempo real

---

#### 3.9 Banco de Dados do Tenant (TenantDatabase)

- `host`, `port` (int), `database_name`, `username`
- `password` (encriptado — campo sensível, exibição mascarada)
- `ssl_mode` (select: disable | prefer | require | verify-ca | verify-full)
- `connection_valid` (bool, somente leitura)
- `last_check` (datetime, somente leitura)
- Botão **"Testar Conexão"** → dispara RPC `TestDatabaseConnection`

---

### P3 — Gestão Operacional (prioridade média)

#### 3.10 Atendentes (Human Agents)

Lista de atendentes de todos os tenants (visão global do superusuário):

| Campo | Tipo |
|---|---|
| nome | texto |
| cargo | texto |
| departamento | FK |
| ativo | bool |
| disponivel | bool |
| max_atendimentos_simultaneos | int |
| atendimentos_ativos | int calculado |
| ultima_atividade | datetime |

**Ações bulk:** marcar como disponível / indisponível.
**Filtros:** ativo, disponivel, departamento.

---

#### 3.11 Departamentos

CRUD de departamentos por tenant:
- nome, slug, descricao, ativo
- configuracoes (editor JSON)
- FluxoAtendimento inline (lista de fluxos do departamento)

---

#### 3.12 AppInstances (Instâncias WhatsApp/Evolution)

- channel (identificador da instância Evolution)
- api_key, display_name
- departamento (FK), owner (FK)
- active, created_at
- Status de conexão em tempo real

---

### P4 — Business Intelligence e Dashboard (prioridade complementar)

#### 3.13 Dashboard Principal (tela inicial do admin)

Cards de resumo:
- Total de tenants ativos / suspensos / em atraso
- Receita mensal (soma de pagamentos do mês corrente)
- Tenants expirando nos próximos 7 dias (lista clicável)
- Total de atendimentos nas últimas 24h / 7 dias (somente leitura)

Gráficos (agregação no backend, renderização Flutter):
- Evolução de tenants ativos por mês (linha)
- Receita por mês (barras)
- Atendimentos por dia (área)

---

#### 3.14 Exportações

- **Tenants CSV:** name, slug, owner, status, plan, period_end, created_at
- **Pagamentos CSV:** tenant, date, amount, method, period, notes (por intervalo de data)
- **Clientes CSV:** por tenant — nome_fantasia, razao_social, tipo, cnpj/cpf, telefone, cidade, uf

---

## 4. Modelo de Dados — Tabelas Envolvidas

Todas as tabelas já existem nas migrations 0001–0011. O painel é **read/write sobre
tabelas já provisionadas** — nenhuma migration nova é necessária para P1–P3.

> **Atenção aos nomes reais das tabelas:** o schema preserva o prefixo de app do Django
> legado (`tenants_*`, `oraculo_*`). Use os nomes exatos abaixo nas queries.

| Tabela (nome real) | Entidade | Migration |
|---|---|---|
| `tenants_tenant` | Tenant | 0002 |
| `tenants_tenantconfig` | TenantConfig | 0002 |
| `tenants_plan` | Plan | 0003 |
| `tenants_subscription` | Subscription | 0003 |
| `tenants_paymentrecord` | PaymentRecord | 0003 |
| `tenants_tenantuser` | TenantUser | 0002 |
| `tenants_tenantinvite` | TenantInvite | 0002 |
| `oraculo_app_instance` | AppInstance | 0005 |
| `auth_user` | AuthUser | 0001 |
| `audit_log` | AuditLog | 0010 |

> **Nota:** `TenantDatabase`, `TenantEvolution`, `TenantTrello` da v1 foram
> consolidadas em `tenants_tenantconfig` e `oraculo_app_instance` na v2. Os campos de
> credencial são encriptados via `CipherManager` (AES-256-GCM) em
> `infrastructure_postgres::crypto`. As instâncias Evolution sincronizadas têm
> persistência adicional na migration 0008 (`evolution_sync`).

---

## 5. Arquitetura de Implementação

```
[Flutter Admin]
    │  gRPC (HTTP/2, metadata: Authorization: Bearer <JWT superuser>)
    ▼
[runtime_api] ← AuthInterceptor (valida JWT + is_superuser = true)
    │  RPC (UDS/TCP)           │  RPC (UDS/TCP)
    ▼                          ▼
[data_postgres]          [control_plane]
 (CRUD direto)           (lógica de negócio:
                          provisionar tenant,
                          gerar código de acesso,
                          testar conexão Evolution)
```

**Regras de roteamento no `runtime_api`:**
- Todas as rotas sob `AdminService` exigem `is_superuser = true` no interceptor.
- CRUD simples (tenants, planos, pagamentos) → `data_postgres` diretamente.
- Ações complexas (provisionar, testar conexão, enviar e-mail) → `control_plane`.

---

## 6. Contratos gRPC — `AdminService`

Novos métodos a adicionar ao `contracts/schemas/admin.proto`:

### Gestão de Tenants
```protobuf
rpc ListTenants(ListTenantsRequest) returns (ListTenantsResponse);
rpc GetTenant(GetTenantRequest) returns (TenantDetail);
rpc CreateTenant(CreateTenantRequest) returns (TenantDetail);
rpc UpdateTenant(UpdateTenantRequest) returns (TenantDetail);
rpc SetTenantActive(SetTenantActiveRequest) returns (Empty);
rpc BulkExtendSubscription(BulkExtendRequest) returns (BulkResult);
rpc BulkSetTenantActive(BulkSetActiveRequest) returns (BulkResult);
rpc GenerateAccessCode(GenerateAccessCodeRequest) returns (AccessCodeResult);
```

### Planos e Assinaturas
```protobuf
rpc ListPlans(Empty) returns (ListPlansResponse);
rpc CreatePlan(CreatePlanRequest) returns (Plan);
rpc UpdatePlan(UpdatePlanRequest) returns (Plan);
rpc SetPlanActive(SetPlanActiveRequest) returns (Empty);
rpc ListSubscriptions(ListSubscriptionsRequest) returns (ListSubscriptionsResponse);
rpc RegisterPayment(RegisterPaymentRequest) returns (PaymentRecord);
rpc ListPayments(ListPaymentsRequest) returns (ListPaymentsResponse);
```

### Configuração de Tenant
```protobuf
rpc GetTenantConfig(GetTenantRequest) returns (TenantConfig);
rpc UpdateTenantConfig(UpdateTenantConfigRequest) returns (TenantConfig);
rpc TestEvolutionConnection(TestConnectionRequest) returns (ConnectionResult);
rpc TestDatabaseConnection(TestConnectionRequest) returns (ConnectionResult);
```

### Dashboard e Exportação
```protobuf
rpc GetDashboardSummary(Empty) returns (DashboardSummary);
rpc ExportTenantsCsv(ExportRequest) returns (stream CsvChunk);
rpc ExportPaymentsCsv(ExportPaymentsRequest) returns (stream CsvChunk);
```

---

## 7. Campos Encriptados — Política de Segurança

Campos que **nunca** trafegam em claro pelo gRPC nem são exibidos literalmente na UI:

| Campo | Tabela | Tratamento |
|---|---|---|
| `password` | tenant_database | exibido mascarado `••••••••`; edição: novo valor substituído via RPC |
| `api_key` | tenant_evolution | idem |
| `api_keys` (JSON) | tenant_config | chaves exibidas mascaradas por chave (`groq_api_key: ••••`) |
| `secret_key` | tenant_trello (futuro) | idem |

**Fluxo de atualização de campo encriptado:**
1. UI envia novo valor via gRPC (TLS) → `runtime_api` → `control_plane`.
2. `control_plane` chama `CipherManager::encrypt(value)` antes de passar ao `data_postgres`.
3. `data_postgres` grava o valor cifrado + prefixo `enc:` (padrão já existente no `crypto.rs`).
4. Na leitura, `control_plane` detecta prefixo `enc:` e devolve `"••••••••"` (nunca decripta para o admin).
5. Para testar conexão, `control_plane` decripta internamente e faz o teste sem expor o valor.

---

## 8. Etapas de Implementação

### Etapa A — Backend: `control_plane` CRUD + `runtime_api` AdminService

**Branch:** `feature/admin-backend`

**A.1 — Repositórios faltantes em `infrastructure_postgres`**
- `TenantRepository::listar_todos` / `criar` / `atualizar` / `set_active`
- `PlanRepository::criar` / `atualizar` / `set_active`
- `SubscriptionRepository::atualizar_periodo` / `registrar_pagamento`
- `PaymentRecordRepository::listar_por_tenant` / `criar`
- Todas as queries devem ser registradas no cache `.sqlx` (ou runtime query com `FromRow`)

**A.2 — Handlers no `data_postgres`**
- `handler_list_tenants`, `handler_get_tenant`, `handler_create_tenant`, `handler_update_tenant`
- `handler_set_tenant_active`, `handler_list_plans`, `handler_create_plan`, `handler_update_plan`
- `handler_register_payment`, `handler_list_payments`
- Disparo de evento de auditoria em cada mutação (via `publicar_evento_seguranca`)

**A.3 — Lógica de negócio no `control_plane`**
- `handler_bulk_extend_subscription` — itera tenants, chama `data_postgres` para cada um
- `handler_generate_access_code` — gera código 6-char (`[A-Z0-9]{3}-[A-Z0-9]{3}`), salva em Redis (TTL 24h), envia e-mail via SMTP
- `handler_test_evolution_connection` — decripta api_key, faz HTTP GET no Evolution, atualiza `connection_valid`
- `handler_dashboard_summary` — agrega dados de tenants, assinaturas, pagamentos

**A.4 — Proto `admin.proto` em `contracts`**
- Definir todas as mensagens e o `AdminService` com os RPCs da seção 6
- Gerar stubs Rust (`build.rs` já configurado)

**A.5 — `AdminService` no `runtime_api`**
- Implementar cada RPC com guarda `is_superuser` no interceptor
- Rotear para `data_postgres` ou `control_plane` conforme necessidade
- Streaming gRPC para exportação CSV (`ExportTenantsCsv`, `ExportPaymentsCsv`)

**DoD A:** `grpcurl` consegue chamar todos os endpoints do `AdminService` com JWT de superusuário; chamadas sem JWT ou com JWT de usuário comum são rejeitadas com `PERMISSION_DENIED`.

---

### Etapa B — Frontend: Flutter admin

**Branch:** `feature/admin-flutter`

**B.1 — Bootstrap do `clients/flutter_windows` + packages**
(Coincide com F6.5 se ainda não feito)
- App shell com `MaterialApp` + tema dark
- Package `api_client` com factory gRPC e `DataSource: RemoteOnly`
- Package `core_ui` com componentes base (AppBar, Sidebar, DataTable, StatusBadge)
- Guarda de sessão (SecureStorage do refresh token + auto-refresh)
- `AuthGuard` + `SuperuserGuard` para rotas protegidas

**B.2 — Tela de Login (Admin)**
- Form email/password → `AuthService.Login`
- Valida se `is_superuser = true` no payload do JWT; se não for, exibe erro e encerra sessão
- Redirect para dashboard após login

**B.3 — Dashboard (P4.13)**
- Cards de resumo: tenants ativos, suspensos, expirando em 7 dias, receita mensal
- Lista "expirando logo" clicável (navega para detalhe do tenant)
- (Gráficos: podem ser adicionados depois sem bloquear o restante)

**B.4 — Lista de Tenants (P1.3.1)**
- DataTable paginada com filtros e busca
- Status badge colorido
- Checkbox para bulk actions (estender assinatura, ativar/suspender)
- Botão "Novo Tenant"

**B.5 — Detalhe do Tenant (P1.3.2)**
- Form com abas: Identificação | Assinatura | Config IA | Evolution | Pagamentos
- Aba Pagamentos: lista + botão "Registrar Pagamento" (abre dialog/sheet)
- Campos encriptados: exibição mascarada + ícone de edição que abre campo novo

**B.6 — Formulário de Pagamento (P1.3.3)**
- Dialog ou bottom sheet com os campos da seção 3.3
- Atualiza a lista de pagamentos e o status da assinatura ao salvar

**B.7 — Gestão de Planos (P1.3.4)**
- Lista + CRUD simples
- Proteção de exclusão (não deletar plano com assinaturas ativas)

**B.8 — Telas P2 (Configurações do Tenant)**
- TenantConfig: form LLM + Persona + API Keys (mascaradas) + Branding
- TenantEvolution: form + botão "Testar Conexão" com feedback em tempo real
- TenantDatabase: idem

**B.9 — Telas P3 (Operacional)**
- Lista de Atendentes (visão global)
- Lista de Departamentos
- AppInstances

**B.10 — Exportações (P4.3.14)**
- Botão exportar CSV na lista de tenants e na lista de pagamentos
- Recebe stream gRPC e salva arquivo localmente

**DoD B:** todas as telas P1 operacionais contra o `runtime_api` real; `flutter analyze` limpo; campos encriptados nunca exibem valores reais; `SuperuserGuard` bloqueia usuários comuns.

---

## 9. Critérios de Aceite Globais (DoD do Painel Admin)

- [ ] Login do superusuário via JWT; sessão renovada automaticamente (refresh)
- [ ] CRUD completo de tenants (criar, editar, ativar/suspender, ver histórico)
- [ ] CRUD de planos com proteção contra exclusão indevida
- [ ] Registro manual de pagamento atualiza `current_period_end` e status da assinatura
- [ ] Bulk actions funcionam para múltiplos tenants selecionados
- [ ] Campos encriptados (api_key, password) nunca exibem valor real; edição substitui corretamente
- [ ] `SuperuserGuard` bloqueia acesso sem JWT de superusuário (retorno gRPC `PERMISSION_DENIED`)
- [ ] Auditoria: toda mutação gera evento em `audit_log` (via `publicar_evento_seguranca`)
- [ ] `flutter analyze` limpo; `cargo clippy -- -D warnings` limpo
- [ ] Testes de integração no backend (endpoints do `AdminService` com JWT válido e inválido)

---

## 10. Checklist Transversal por PR do Painel Admin

- [ ] JWT de superusuário validado no interceptor antes de qualquer handler
- [ ] Campos encriptados: lidos via `CipherManager::encrypt/decrypt`; nunca logados
- [ ] Auditoria: mutations geram `audit_log` com `actor = superuser_id`
- [ ] `tenant_id` presente no Envelope mesmo para operações globais (usar `Uuid::nil()`)
- [ ] Paginação implementada em todas as listas (cursor-based ou offset, consistente)
- [ ] Exportações CSV escapam campos com vírgulas e aspas corretamente
- [ ] Comentários em pt-br; identificadores em inglês

---

*Documento criado em 2026-06-07. Retroalimentar conforme implementação avança.*
