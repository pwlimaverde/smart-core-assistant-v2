//! Port (abstração) do domínio WhatsApp do data_postgres.
//! O handler depende SOMENTE desta trait; a transação vive no adapter (DIP).

use async_trait::async_trait;
use infrastructure_postgres::integracoes::conexoes::DetalheDaConexao;
use infrastructure_postgres::integracoes::whatsapp::WhatsappInstance;
use infrastructure_postgres::integracoes::whitelist::WhiteList;
use infrastructure_postgres::{DbError, RequestContext};

/// Operações de persistência do domínio WhatsApp expostas aos handlers RPC.
/// Cada método encapsula a abertura/commit da transação no adapter concreto.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait WhatsappStore: Send + Sync {
    /// Cria um registro de instância (encapsula run_in_tenant_transaction + repo.criar).
    async fn criar_instancia(
        &self,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError>;

    /// Busca instância por id (tenant-scoped via RLS).
    async fn buscar_instancia(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    /// Lista instâncias ativas do tenant.
    async fn listar_ativas(&self, ctx: &RequestContext) -> Result<Vec<WhatsappInstance>, DbError>;

    /// Lista cross-tenant de instâncias conectadas (admin/BYPASSRLS no adapter).
    async fn admin_listar_conectadas(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError>;

    /// Remoção admin de instância.
    async fn admin_deletar_instancia(&self, ctx: &RequestContext, id: i32) -> Result<(), DbError>;

    /// D3 — liga/desliga a resposta automática da IA para a instância inteira.
    ///
    /// `false` no retorno = instância inexistente ou de outro tenant; o chamador
    /// precisa saber para não auditar uma alteração que não houve.
    async fn definir_resposta_bot(
        &self,
        ctx: &RequestContext,
        id: i32,
        habilitado: bool,
    ) -> Result<bool, DbError>;

    /// Atualiza o estado de conexão da instância.
    async fn atualizar_estado(
        &self,
        ctx: &RequestContext,
        id: i32,
        connection_state: &str,
    ) -> Result<(), DbError>;

    /// Atualiza o provider_id (instance_id) e telefone da instância.
    async fn atualizar_provider_id(
        &self,
        ctx: &RequestContext,
        id: i32,
        instance_id: &str,
        phone_number: Option<String>,
    ) -> Result<(), DbError>;

    /// Contrato de canal — grava o tipo do canal e a configuração NÃO secreta
    /// do provedor (`whatsapp_instance.channel_kind`/`provider_config`, 0054).
    /// `false` = instância inexistente ou de outro tenant.
    async fn gravar_config_do_canal(
        &self,
        ctx: &RequestContext,
        id: i32,
        channel_kind: &str,
        provider_config: serde_json::Value,
    ) -> Result<bool, DbError>;

    /// Contrato de canal — acha a conexão ativa pelo id externo do provedor
    /// (o `phone_number_id` da Cloud API), CROSS-TENANT: o webhook da Meta é
    /// um por app e não traz o tenant no caminho. Devolve `(id, tenant_id)`.
    async fn admin_resolver_por_id_externo(
        &self,
        ctx: &RequestContext,
        provider: &str,
        id_externo: &str,
    ) -> Result<Option<(i32, uuid::Uuid)>, DbError>;

    /// Verifica se a chave de API (token) bate com o configurado para a instância.
    async fn verificar_token(
        &self,
        ctx: &RequestContext,
        id: i32,
        token: &str,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    /// Verifica se um número de telefone está na whitelist.
    async fn verificar_telefone_whitelist(
        &self,
        ctx: &RequestContext,
        phone_number: &str,
    ) -> Result<bool, DbError>;

    /// P7 — os números ignorados do tenant, inclusive os desligados.
    async fn listar_numeros_ignorados(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError>;

    /// P7 — acrescenta um número à lista.
    async fn criar_numero_ignorado(
        &self,
        ctx: &RequestContext,
        nome: &str,
        telefone: &str,
    ) -> Result<WhiteList, DbError>;

    /// P7 — corrige ou liga/desliga um número da lista.
    async fn atualizar_numero_ignorado(
        &self,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        telefone: &str,
        ativo: bool,
    ) -> Result<Option<WhiteList>, DbError>;

    /// P7 — apaga a entrada.
    async fn remover_numero_ignorado(&self, ctx: &RequestContext, id: i32)
        -> Result<bool, DbError>;

    /// P7 — liga a conexão a um departamento (`None` desfaz o vínculo).
    async fn definir_departamento_da_conexao(
        &self,
        ctx: &RequestContext,
        id: i32,
        departamento_id: Option<i32>,
    ) -> Result<bool, DbError>;

    /// P7 — o detalhe da conexão, com o departamento e os contadores.
    async fn detalhe_da_conexao(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<DetalheDaConexao>, DbError>;

    /// P7 — o departamento de cada conexão, para a lista não precisar de N+1.
    async fn departamentos_das_conexoes(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<(i32, Option<i32>, String)>, DbError>;

    /// Liga o contato à conexão por onde ele escreveu. É o que o envio do
    /// atendente usa para saber por qual WhatsApp responder.
    async fn vincular_contato(
        &self,
        ctx: &RequestContext,
        instance_id: i32,
        jid: &str,
        contato_id: i32,
    ) -> Result<(), DbError>;
}
