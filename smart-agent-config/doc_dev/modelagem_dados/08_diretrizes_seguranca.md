# 08. Diretrizes de Segurança para Armazenamento de Dados Sensíveis

Este documento estabelece as diretrizes obrigatórias de segurança da informação aplicadas à camada de persistência de dados e tratamento de informações sensíveis no ecossistema **Smart Core Assistant v2**. O sistema gerencia dados confidenciais de inquilinos (Tenants) — como chaves de API de provedores de IA (Groq, OpenAI) e tokens de integração — e dados pessoais identificáveis (PII) de clientes finais (contatos, históricos de chats, mensagens e transcrições de áudio).

---

## 1. Isolamento Multi-Tenant via Row-Level Security (RLS)

O sistema utiliza uma arquitetura de banco de dados unificado (single database) com isolamento lógico imposto no nível do PostgreSQL por meio de políticas de Row-Level Security (RLS).

### 1.1 Dupla Barreira de Isolamento (Defesa em Profundidade)
Para garantir que falhas de lógica em consultas SQL complexas não causem vazamento de dados entre tenants, o isolamento baseia-se em dois mecanismos redundantes:
1. **Filtro Nativo de RLS (PostgreSQL):** Toda tabela de dados de negócio do inquilino possui RLS ativo associado à variável de contexto local `app.current_tenant` (ex: `SET LOCAL app.current_tenant = 'tenant-uuid'`).
2. **Filtro Explícito no Código (Rust/SQLx):** Toda query Rust no SQLx deve incluir explicitamente a cláusula `WHERE tenant_id = $1` ou associar o `tenant_id` às inserções/atualizações.
   * *Justificativa:* Além de atuar como barreira dupla contra erros de programação, a declaração explícita de `tenant_id` permite que o planejador de consultas do PostgreSQL utilize índices compostos (ex: `(tenant_id, telefone)`), evitando varreduras completas (*seq scans*) e mantendo a alta performance.

### 1.2 Regra de Menor Privilégio na Conexão do Banco
* **Restrição de Superusuário:** O pool global de conexões (`PgPool`) do backend Rust **nunca** deve se conectar ao PostgreSQL utilizando a role de `superuser` (como `postgres`) ou a role dona das tabelas (*table owner*). No PostgreSQL, roles superusuárias e donas de tabelas contornam o RLS por padrão (`BYPASSRLS`).
* **Role da Aplicação:** Deve ser criada uma role específica de privilégios mínimos (ex: `app_runtime`) que tenha permissão para realizar operações de DML (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) nas tabelas necessárias, mas seja estritamente submetida às políticas de RLS (`NOBYPASSRLS`).

**Estado real (N4.1, implementado):** `smartcore_app` é o *bootstrap user* do
container Postgres — o próprio PostgreSQL exige que ele permaneça `SUPERUSER`
("the bootstrap user must have the SUPERUSER attribute"), então ele **não pode**
ser rebaixado; continua sendo a role administrativa (`DATABASE_ADMIN_URL`, dona
das tabelas, usada só para migrations/DDL e os poucos lookups cross-tenant
legítimos). A role de runtime é uma role **nova e aditiva**, `smartcore_app_rt`
(`DATABASE_URL` — NOSUPERUSER NOBYPASSRLS) — é ela quem passa de verdade pelas
policies de RLS. A criação é aplicada uma vez por ambiente via
`infra/provision-db-role.sh` (idempotente); os grants de DML da role de runtime
são mantidos em sincronia a cada migration por
`server/crates/infrastructure_postgres/migrations/0018_app_rt_role_grants.sql`
(condicional/idempotente; `0016_app_runtime_role.sql` cobre a role administrativa).
Fronteira `pool` × `admin_pool` documentada em
`infrastructure_postgres::connection::criar_admin_pool`.

### 1.3 Exemplo de SQL para Ativação e Política de RLS
Abaixo está o padrão para a criação e ativação das políticas nas tabelas de inquilino:

```sql
-- Cria a role da aplicação com privilégios mínimos
CREATE ROLE app_runtime WITH LOGIN PASSWORD '...' NOBYPASSRLS;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_runtime;

-- Habilita o RLS na tabela
ALTER TABLE oraculo_contato ENABLE ROW LEVEL SECURITY;

-- Força a aplicação das políticas mesmo para o dono da tabela
ALTER TABLE oraculo_contato FORCE ROW LEVEL SECURITY;

-- Cria a política de isolamento com base na variável de sessão
CREATE POLICY contato_tenant_isolation ON oraculo_contato
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
```

---

## 2. Criptografia em Nível de Aplicação (Application-Level Encryption)

Credenciais de terceiros, tokens de API de provedores (ex: chaves do OpenAI, Groq, Evolution API) armazenadas na tabela `tenants_tenantconfig` (no campo JSONB `api_keys`) devem ser criptografadas em nível de aplicação antes do envio ao banco. Isso garante a proteção mesmo em cenários de comprometimento do banco de dados ou dumps expostos.

### 2.1 Algoritmo e Criptografia Simétrica
* **Algoritmo:** Utilizar criptografia simétrica autenticada **AES-256-GCM** (Advanced Encryption Standard no modo Galois/Counter Mode) via crate Rust `aes-gcm`.
* **Segurança de Criptografia Autenticada (AEAD):** O modo GCM fornece tanto confidencialidade quanto integridade dos dados, garantindo que qualquer tentativa de alteração dos dados cifrados seja detectada durante a descriptografia.

### 2.2 Gerenciamento da Chave Mestra (Master Key)
* **Zero Hardcoding:** A chave mestra de criptografia de 256 bits (32 bytes) **nunca** deve residir em arquivos de código ou tabelas de banco de dados.
* **Variável de Ambiente:** A chave deve ser injetada em produção via variável de ambiente **`ENCRYPTION_KEY`**, codificada em hexadecimal ou Base64. Em ambiente de desenvolvimento local, declarada em `.env` (nunca versionado) e documentada com valor falso em `.env.example`.
* **Nonce Único (Número de Uso Único):** Para cada operação de encriptação, um nonce aleatório de 96 bits (12 bytes) deve ser gerado usando **`OsRng`** (CSPRNG do sistema operacional). **Nunca reutilize um nonce** com a mesma chave mestra.

### 2.3 Estrutura de Armazenamento do Dado Criptografado
A informação criptografada é armazenada no dicionário JSONB `api_keys` sob a seguinte estrutura:

```json
{
  "groq_api_key": {
    "ciphertext": "base64_encoded_encrypted_data",
    "nonce": "base64_encoded_12_byte_nonce",
    "tag": "base64_encoded_16_byte_auth_tag"
  }
}
```

### 2.4 Fluxo de Execução Conceitual em Rust
Implementação do comportamento de criptografia na crate `infrastructure_postgres`:

```rust
// Exemplo conceitual para referência de implementação
use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm,
};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};

pub struct CipherManager {
    key: [u8; 32],
}

impl CipherManager {
    pub fn new_from_env() -> Result<Self, &'static str> {
        let key_str = std::env::var("ENCRYPTION_KEY")
            .map_err(|_| "ENCRYPTION_KEY não configurada")?;

        let key_bytes = BASE64.decode(key_str.trim())
            .map_err(|_| "Chave inválida (deve ser Base64)")?;

        if key_bytes.len() != 32 {
            return Err("A chave mestra precisa ter exatamente 32 bytes (256 bits)");
        }

        let mut key = [0u8; 32];
        key.copy_from_slice(&key_bytes);
        Ok(Self { key })
    }

    pub fn encrypt(&self, plaintext: &[u8]) -> Result<(String, String, String), &'static str> {
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| "Falha ao inicializar cifra AES-GCM")?;

        // OsRng usa entropia do SO — mais seguro que thread_rng para material criptográfico
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);

        // O resultado já contém ciphertext + tag de autenticação concatenados
        let ciphertext_with_tag = cipher.encrypt(&nonce, plaintext)
            .map_err(|_| "Falha na encriptação")?;

        let (ciphertext, tag) = ciphertext_with_tag.split_at(ciphertext_with_tag.len() - 16);

        Ok((
            BASE64.encode(ciphertext),
            BASE64.encode(nonce),
            BASE64.encode(tag),
        ))
    }

    pub fn decrypt(&self, ciphertext_b64: &str, nonce_b64: &str, tag_b64: &str) -> Result<Vec<u8>, &'static str> {
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| "Falha ao inicializar cifra AES-GCM")?;

        let ciphertext = BASE64.decode(ciphertext_b64).map_err(|_| "Ciphertext inválido")?;
        let nonce_bytes = BASE64.decode(nonce_b64).map_err(|_| "Nonce inválido")?;
        let tag = BASE64.decode(tag_b64).map_err(|_| "Tag inválida")?;

        let nonce = aes_gcm::Nonce::from_slice(&nonce_bytes);

        let mut ciphertext_with_tag = ciphertext;
        ciphertext_with_tag.extend_from_slice(&tag);

        let plaintext = cipher.decrypt(nonce, ciphertext_with_tag.as_slice())
            .map_err(|_| "Falha na descriptografia (integridade violada ou chave inválida)")?;

        Ok(plaintext)
    }
}
```

---

## 3. Tratamento de Dados de Contatos e Clientes (PII e LGPD)

Dados Pessoais Identificáveis (PII) inseridos nas conversas de chat, transcrições de áudio de WhatsApp e cadastros de contatos requerem políticas estritas para assegurar os direitos dos titulares segundo a LGPD (Lei Geral de Proteção de Dados).

### 3.1 Direito ao Esquecimento (Expurgo Definitivo)
* **Exclusão Física (Hard Delete):** Ao deletar registros de contatos, mensagens ou mídias cadastrados sob solicitação do tenant ou cliente final, o sistema deve executar a remoção física dos dados (`DELETE` direto na tabela unificada) em vez de simples exclusão lógica (`Soft Delete` via flag `deleted_at`).
* **Expurgo em Cascata:** A remoção de um `Contato` deve desencadear a deleção em cascata de todas as suas `Mensagens`, `Atendimentos` e dados vetoriais (embeddings) gerados na base RAG do tenant.
* **Conflito com Auditoria:** O Hard Delete de dados pessoais pode colidir com a obrigação de manter logs de auditoria por prazo legal. A solução é anonimizar (não deletar) os registros de auditoria — substituindo PII por valores nulos ou genéricos — em vez de apagá-los por completo.

### 3.2 Armazenamento de Arquivos e Mídias de WhatsApp
* **Tempo de Vida Limite (TTL):** Arquivos de áudio de mensagens de voz e imagens recebidas das instâncias do WhatsApp devem ser salvos em buckets de Object Storage privados (Cloudflare R2, S3-compatible, em desenvolvimento e produção) com políticas de expiração automática (TTL máximo recomendado de 30 dias para mensagens normais).
* **Links Temporários:** O acesso a mídias no Object Storage no painel do atendente deve ser realizado por meio de URLs pré-assinadas (*Presigned URLs*) com validade curta (máximo de 15 minutos), evitando links diretos ou públicos expostos.

---

## 4. Prevenção de Vazamento de Informações via Logs e Tracing

Mensagens de log geradas pela aplicação (usando a crate `tracing`) não podem ser fontes de vazamento de dados sensíveis ou informações de identificação de usuários.

### 4.1 Sanitização e Mascaramento de Informações Confidenciais
* **Campos Proibidos:** É expressamente proibido escrever logs contendo chaves de API, senhas do banco de dados, segredos JWT, tokens de convite, ou payloads sensíveis brutos enviados por integradores HTTP.
* **Dados Pessoais:** Evitar escrever o número completo do telefone (`telefone`) e dados cadastrais no nível de log `INFO` ou `WARN`. Caso seja indispensável para depuração técnica em produção, os números devem ser mascarados (ex: `+55 11 9****-1234`).
* **Proteção de Structs Sensíveis em Rust:** Structs que carregam chaves de API ou credenciais devem usar a crate **`secrecy`** (padrão idiomático Rust), que fornece `SecretString` e `SecretVec<u8>` — tipos que implementam `Debug` como `[REDACTED]` e zeram o conteúdo na memória ao fazer `Drop`. Evitar implementar `Debug` manualmente ou depender da crate `derivative` para esse fim:
  ```rust
  use secrecy::SecretString;

  pub struct RuntimeConfig {
      pub tenant_id: Uuid,
      pub openai_api_key: SecretString,  // nunca vaza em logs ou panic messages
      pub groq_api_key: SecretString,
      // ...
  }
  ```

### 4.2 Trilhas de Auditoria (Audit Logs)
Mudanças de estado críticas não devem expor os valores sensíveis alterados, mas devem registrar a ação e o autor em uma tabela de logs de auditoria estruturada.

> **Nota de Modelagem:** A tabela de auditoria (`audit_log`) deve ser adicionada ao módulo de configurações ou tenants em uma migração futura dedicada. Campos mínimos: `id`, `tenant_id`, `user_id`, `event_type` (ex: `api_key.update`), `description`, `ip_address`, `user_agent`, `created_at`.

* **Eventos Críticos Auditados:**
  - Alterações cadastrais de `Tenant` e troca de dono (`owner_id`).
  - Criação, uso e expiração de convites (`TenantInvite`).
  - Mudança de cargo ou nível de permissões de colaborador (`TenantUser`).
  - Atualização do plano (`Subscription`) ou inserção manual de lançamentos financeiros (`PaymentRecord`).
  - Mudança de chaves de API configuradas no `TenantConfig`.
* **Metadados Obrigatórios do Registro de Auditoria:**
  - Timestamp (UTC) preciso da operação.
  - ID do usuário responsável (`user_id` / `RequestContext`).
  - IP de origem da requisição e User-Agent.
  - Tipo de evento (ex: `api_key.update`, `tenant_user.role_change`).
  - Descrição da alteração sem conter os segredos em si (ex: *"Chave de API do Groq atualizada"*).

---

## 5. Segurança de Acesso, Convites e Autorização Granular

### 5.1 Tokens de Convite Seguros (`TenantInvite`)
* **Entropia e Geração:** O campo `token` de um `TenantInvite` deve ser gerado utilizando `OsRng` com tamanho mínimo de 64 caracteres Hexadecimal ou Base64 URL-safe.
* **Ciclo de Vida Curto:** O convite deve ter validade limitada a 7 dias, rastreada por `expires_at`.
* **Uso Único:** O sistema deve impor a transação em que, imediatamente ao aceitar o convite, o campo `used` é atualizado para `True` e o vínculo `TenantUser` é criado. Qualquer tentativa subsequente de acessar o mesmo token deve ser rejeitada com código HTTP `410 Gone`.

### 5.2 Controle de Acesso Baseado em Escopos (RBAC)
* **Consumo de `RequestContext`:** Todo handler de rota Axum que invoca funções do repositório deve recuperar o `RequestContext` autenticado pelo middleware do token JWT.
* **Validação de Escopo:** O repositório deve validar explicitamente os escopos necessários na execução das operações de persistência:
  ```rust
  if !ctx.has_permission("clientes:write") {
      return Err(DbError::PermissionDenied);
  }
  ```
* **Filtro Kanban por Fluxo:** A listagem de colunas do Kanban deve filtrar pelos IDs de fluxo permitidos ao atendente. Em Rust, o `RequestContext` deve incluir o campo `flow_permissions: Vec<i32>` (carregado do campo `flow_permissions` do `TenantUser` no middleware de autenticação), evitando uma query extra por request:
  ```rust
  pub struct RequestContext {
      pub tenant_id: Uuid,
      pub user_id: i32,
      pub user_scopes: Vec<String>,
      pub flow_permissions: Vec<i32>,  // lista de IDs de FluxoAtendimento permitidos
  }
  ```

---

## 6. Segurança do Cache Redis

O Redis (`server/crates/infrastructure_redis/`) passou a armazenar `RuntimeConfig` com chaves de API **já descriptografadas** pelo Rust. Isso requer proteção equivalente à do banco de dados:

* **Acesso Restrito:** O Redis deve ser acessível apenas pela rede interna do servidor (bind em `127.0.0.1` ou rede Docker privada). **Nunca expor a porta Redis para a internet.**
* **Autenticação Obrigatória:** Configurar `requirepass` no Redis com senha forte injetada via variável de ambiente (`REDIS_PASSWORD`). Proibido Redis sem autenticação em qualquer ambiente além do desenvolvimento local isolado.
* **TTL das Configs:** A chave `tenant:config:{tenant_id}` no Redis deve ter TTL de no máximo 24 horas, renovado a cada leitura do `ia_engine`. Isso limita o tempo de exposição de credenciais em caso de comprometimento da instância Redis.
* **TLS em Produção:** Em produção (Hostinger KVM2), configurar `tls-port` no Redis e certificados TLS para a comunicação entre os serviços Rust e Python, mesmo que na mesma máquina.
* **Sem Logs de Comandos:** Desativar o comando `MONITOR` e o log de comandos `loglevel debug` no Redis em produção, pois estes expõem os valores das chaves nos logs do Redis.

### 6.1 PII transitória no Redis de cache (N8.5/E2)

O buffer de agregação de rajada (`worker/src/buffer_mensagens.rs`) **grava conteúdo
de mensagem do contato** na chave `tenant:{id}:buf:{sender}` durante a janela de
agregação. É a primeira vez que o Redis de cache carrega PII de conversa, e não
apenas configuração — o registro aqui existe para que ninguém trate esse Redis
como armazenamento inócuo em auditoria futura.

Mitigações aplicadas no código (todas verificáveis no módulo):

* **TTL curto e obrigatório:** janela × 10, com teto de 300 s e piso de 1 s. Não
  existe caminho que crie a chave sem `EXPIRE` — buffer órfão de worker que morreu
  no meio da janela não pode virar PII imortal.
* **Namespace por tenant:** a chave carrega o `tenant_id`, e o telefone do
  remetente entra no nome da chave (não no valor) — o mesmo dado que o Redis já
  via nas chaves de idempotência e rate limit.
* **Conteúdo nunca sai em log:** o drain registra apenas a **contagem** de
  mensagens agregadas. Nem o texto compilado nem o individual entram em span,
  evento de log ou métrica.
* **Nada de auditoria:** agregar não muda estado sensível; o que muda
  (`mensagem.persistida`, `bot.respondeu`) já é auditado nos pontos existentes.

Consequência operacional: **o Redis de cache passa a estar no escopo do direito ao
esquecimento** (§3.1) na janela de até 5 minutos. Como o TTL é sempre menor que
isso, o expurgo do banco não precisa de passo extra no Redis — mas um pedido de
exclusão durante a janela deve ser considerado atendido só após o TTL vencer.

---

## 7. Check-list para o Ciclo de Desenvolvimento (Code Review Gate)

Durante a fase de Code Review do GitFlow (para branches `feature/` e `bugfix/`), a equipe deve validar a conformidade com as diretrizes deste documento:

- [ ] A tabela de dados contém o campo `tenant_id` e a política de RLS foi declarada no script de migration correspondente?
- [ ] As queries em Rust utilizam a transação encapsulada em `run_in_tenant_transaction`?
- [ ] Há redundância explícita da cláusula `WHERE tenant_id = $1` nas novas consultas do SQLx?
- [ ] Armazenamento de chaves ou segredos de terceiros está sendo encriptado com AES-256-GCM antes de ir ao banco?
- [ ] A chave mestra de criptografia (`ENCRYPTION_KEY`) é recuperada exclusivamente via variável de ambiente no runtime?
- [ ] A geração de nonces e tokens de convite usa `OsRng` (CSPRNG do SO), não `thread_rng`?
- [ ] Structs que carregam credenciais usam `SecretString`/`SecretVec` da crate `secrecy`?
- [ ] Existem structs imprimindo dados confidenciais brutos em mensagens de log (`tracing`) ou no dump de erros?
- [ ] As rotas de criação de convites geram tokens criptograficamente seguros e aplicam validação de data limite?
- [ ] O Redis está configurado com autenticação e TTL nas chaves de configuração de tenant?
- [ ] O `RequestContext` inclui `flow_permissions` carregados do `TenantUser` no middleware de JWT?
