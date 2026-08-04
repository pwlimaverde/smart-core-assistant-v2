//! Port (abstração) do domínio Operacional do data_postgres: configurações globais
//! (core settings), configuração por tenant (com cifragem), feature flags, consulta
//! de auditoria, health e dashboard. O handler depende SOMENTE desta trait; SQL,
//! cifragem (CipherManager), invalidação de cache e PING de Redis vivem no adapter.

use async_trait::async_trait;
use infrastructure_postgres::{DbError, RequestContext};
use uuid::Uuid;

/// Configuração global do sistema; `value` já vem MASCARADO quando `encrypted`.
#[derive(Debug, Clone)]
pub struct CoreSetting {
    pub key: String,
    pub value: String,
    pub encrypted: bool,
    pub description: String,
}

/// Configuração de IA do tenant resolvida para o `worker` montar `LlmProviderConfig`
/// ao chamar o `ia_engine` (fase N2). Ao contrário de `obter_tenant_config` (painel
/// admin, chaves MASCARADAS), aqui a `api_key` vem DESCRIPTOGRAFADA de verdade — este
/// RPC é interno (worker→data_postgres), nunca exposto ao painel/browser.
#[derive(Clone, Default)]
pub struct ConfigIa {
    pub dados_empresa: String,
    pub persona_bot: String,
    pub llm_provider: String,
    pub llm_model: String,
    pub llm_temperature: f64,
    pub embeddings_provider: String,
    pub embeddings_model: String,
    pub similarity_threshold: f64,
    pub vector_distance_threshold: f64,
    /// Kill-switch de transcrição de áudio deste tenant (N6.4), resolvido pela
    /// cascata `tenants_tenantconfig` > CoreSetting `TRANSCRIPTION_ENABLED`. O
    /// worker respeita antes de pedir transcrição à IA.
    pub transcription_enabled: bool,
    /// api_key do provedor do LLM (família resolvida de `llm_class`).
    pub api_key: String,
    /// api_key do provedor de embeddings (família resolvida de `embeddings_class`).
    /// Pode diferir de `api_key` quando LLM e embeddings usam provedores distintos.
    pub embeddings_api_key: String,
}

// `Debug` redigido: as api_keys resolvidas (em claro) nunca podem aparecer num
// `{:?}` acidental (log/trace). Só os campos não-sensíveis são impressos.
impl std::fmt::Debug for ConfigIa {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConfigIa")
            .field("dados_empresa", &self.dados_empresa)
            .field("persona_bot", &self.persona_bot)
            .field("llm_provider", &self.llm_provider)
            .field("llm_model", &self.llm_model)
            .field("llm_temperature", &self.llm_temperature)
            .field("embeddings_provider", &self.embeddings_provider)
            .field("embeddings_model", &self.embeddings_model)
            .field("similarity_threshold", &self.similarity_threshold)
            .field("vector_distance_threshold", &self.vector_distance_threshold)
            .field("api_key", &"[REDACTED]")
            .field("embeddings_api_key", &"[REDACTED]")
            .finish()
    }
}

/// Operações do domínio Operacional expostas aos handlers RPC.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait OperacionalStore: Send + Sync {
    /// Lista as configurações globais (valores cifrados já mascarados).
    async fn listar_core_settings(&self) -> Result<Vec<CoreSetting>, DbError>;

    /// Cria/atualiza uma configuração global; cifra o valor quando `encrypted`.
    async fn upsert_core_setting(
        &self,
        key: &str,
        raw_value: &str,
        encrypted: bool,
        description: &str,
    ) -> Result<(), DbError>;

    /// Remove uma configuração global; `true` se algum registro foi afetado.
    async fn deletar_core_setting(&self, key: &str) -> Result<bool, DbError>;

    /// Obtém a configuração do tenant (chaves de API decifradas e mascaradas).
    /// `None` quando não há configuração para o tenant.
    async fn obter_tenant_config(
        &self,
        tenant_id: Uuid,
    ) -> Result<Option<serde_json::Value>, DbError>;

    /// Atualiza a configuração do tenant a partir do payload (cifra chaves novas,
    /// preserva mascaradas, invalida o cache). Retorna os NOMES das chaves de API
    /// alteradas (nunca os valores) para auditoria dedicada.
    async fn atualizar_tenant_config(
        &self,
        tenant_id: Uuid,
        payload: serde_json::Value,
    ) -> Result<Vec<String>, DbError>;

    /// Obtém a instância Evolution (WhatsApp) ativa do tenant: `(name, api_key)`.
    async fn obter_evolution_instance(
        &self,
        tenant_id: Uuid,
    ) -> Result<Option<(String, String)>, DbError>;

    /// Lista as feature flags com seus overrides por tenant (JSON pronto).
    async fn listar_feature_flags(&self) -> Result<Vec<serde_json::Value>, DbError>;

    /// Define o valor global de uma feature flag e publica a invalidação no Redis.
    async fn set_feature_flag(&self, key: &str, enabled_globally: bool) -> Result<(), DbError>;

    /// Define/remove o override de feature flag para um tenant e publica a invalidação.
    async fn set_feature_flag_override(
        &self,
        key: &str,
        tenant_id: Uuid,
        enabled: bool,
        remove: bool,
    ) -> Result<(), DbError>;

    /// Consulta paginada do audit_log; retorna `(entradas_json, total)`.
    async fn query_audit_log(
        &self,
        tenant_id: Option<Uuid>,
        event_type: Option<String>,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<serde_json::Value>, i64), DbError>;

    /// Health dos serviços de infraestrutura (Postgres + Redis), com latências.
    async fn service_health(&self) -> Vec<serde_json::Value>;

    /// Resumo do dashboard administrativo (contagens + MRR + health).
    async fn dashboard_summary(&self) -> Result<serde_json::Value, DbError>;

    /// Resolve a config de IA do tenant (fase N2) via `TenantConfigCache` — mesma
    /// cascata Tenant > CoreSettings já usada pelo painel admin, mas com a api_key
    /// descriptografada de verdade (uso interno do worker, nunca do painel).
    async fn resolver_config_ia(&self, tenant_id: Uuid) -> Result<ConfigIa, DbError>;

    /// Cria um departamento do tenant (N7.1). Exige escopo `operacional:admin` ou
    /// `tenant:admin` (checado pelo repositório via `RequestContext::exigir_qualquer`).
    /// A checagem de quota do recurso `"departamentos"` é responsabilidade do
    /// chamador (handler), executada ANTES desta chamada. `nome`/`descricao` são
    /// owned para satisfazer o `automock` (lifetime aninhado em `Option<&str>`).
    async fn criar_departamento(
        &self,
        ctx: &RequestContext,
        nome: String,
        descricao: Option<String>,
    ) -> Result<serde_json::Value, DbError>;

    /// Lista os departamentos do tenant.
    async fn listar_departamentos(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<serde_json::Value>, DbError>;

    async fn atualizar_departamento(
        &self,
        ctx: &RequestContext,
        id: i32,
        nome: String,
        descricao: Option<String>,
        ativo: bool,
    ) -> Result<bool, DbError>;

    /// Desativa — não apaga. Atendimentos e atendentes apontam para o
    /// departamento, e remover a linha levaria histórico junto.
    async fn desativar_departamento(&self, ctx: &RequestContext, id: i32) -> Result<bool, DbError>;

    /// Lista os fluxos do tenant (ativos e inativos), com departamento e
    /// contagens de etapas e de atendimentos abertos.
    async fn listar_fluxos(&self, ctx: &RequestContext) -> Result<Vec<serde_json::Value>, DbError>;

    /// Cria um fluxo **já com as quatro etapas padrão** (fila, trabalho, espera,
    /// finalização).
    ///
    /// Um fluxo sem etapas não recebe atendimento nenhum — a etapa de entrada é
    /// o que o roteamento procura. Entregar o esqueleto pronto evita que o
    /// tenant crie um fluxo que parece existir e não funciona.
    ///
    /// A quota do recurso `"fluxos"` é responsabilidade do handler, ANTES desta
    /// chamada. `nome`/`descricao` são owned por causa do `automock`.
    async fn criar_fluxo(
        &self,
        ctx: &RequestContext,
        departamento_id: i32,
        nome: String,
        descricao: Option<String>,
    ) -> Result<serde_json::Value, DbError>;

    /// Atualiza o fluxo. Devolve `{sucesso, motivo}`: desativar um fluxo com
    /// atendimento aberto é recusado, e o motivo precisa chegar à tela.
    async fn atualizar_fluxo(
        &self,
        ctx: &RequestContext,
        id: i32,
        nome: String,
        descricao: Option<String>,
        ativo: bool,
    ) -> Result<serde_json::Value, DbError>;

    /// Desativa o fluxo. Mesmo contrato `{sucesso, motivo}` de `atualizar_fluxo`.
    async fn desativar_fluxo(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<serde_json::Value, DbError>;

    /// Etapas ativas de um fluxo, na ordem em que aparecem no quadro.
    async fn listar_etapas(
        &self,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Vec<serde_json::Value>, DbError>;

    /// Acrescenta uma etapa no fim do fluxo.
    async fn criar_etapa(
        &self,
        ctx: &RequestContext,
        fluxo_id: i32,
        nome: String,
        tipo_etapa: String,
        cor: String,
    ) -> Result<serde_json::Value, DbError>;

    async fn atualizar_etapa(
        &self,
        ctx: &RequestContext,
        id: i32,
        nome: String,
        descricao: Option<String>,
        cor: String,
        tipo_etapa: String,
    ) -> Result<bool, DbError>;

    /// Desativa a etapa. Devolve `{sucesso, motivo}`: uma etapa com atendimento
    /// parado nela, ou a última porta de entrada do fluxo, não pode sair.
    async fn desativar_etapa(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<serde_json::Value, DbError>;

    /// Troca a etapa de lugar com a vizinha. `false` quando já está na ponta.
    async fn mover_etapa(
        &self,
        ctx: &RequestContext,
        id: i32,
        para_cima: bool,
    ) -> Result<bool, DbError>;

    /// Lista os atendentes do tenant, ativos primeiro.
    async fn listar_atendentes(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<serde_json::Value>, DbError>;

    /// Cria um atendente. `fluxo_id` é obrigatório no banco — é o quadro em que
    /// ele trabalha, e sem fluxo criado não há atendente a criar.
    async fn criar_atendente(
        &self,
        ctx: &RequestContext,
        nome: String,
        email: String,
        cargo: String,
        fluxo_id: i32,
        departamento_id: Option<i32>,
    ) -> Result<serde_json::Value, DbError>;

    /// Atualiza o atendente. Devolve `{sucesso, motivo}`: desativar alguém com
    /// conversa em andamento é recusado, e o motivo precisa chegar à tela.
    #[allow(clippy::too_many_arguments)]
    async fn atualizar_atendente(
        &self,
        ctx: &RequestContext,
        id: i32,
        nome: String,
        cargo: String,
        departamento_id: Option<i32>,
        fluxo_id: i32,
        ativo: bool,
        disponivel: bool,
        max_simultaneos: i32,
    ) -> Result<serde_json::Value, DbError>;

    /// Desativa o atendente. Mesmo contrato `{sucesso, motivo}`.
    async fn desativar_atendente(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<serde_json::Value, DbError>;

    /// Números do painel do tenant.
    ///
    /// Uma consulta só, e não uma por número: são cinco contagens pequenas
    /// sobre o mesmo tenant, e cinco idas ao banco para montar uma tela seria
    /// desperdício — além de poder mostrar números de instantes diferentes.
    async fn painel_do_tenant(&self, ctx: &RequestContext) -> Result<serde_json::Value, DbError>;
}
