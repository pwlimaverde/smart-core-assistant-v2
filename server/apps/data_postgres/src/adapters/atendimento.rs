//! Adapter concreto do domínio Atendimento: reusa os repositórios de mensagens e
//! atendimentos de infrastructure_postgres e encapsula a transação. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::atendimentos::atendimentos::{
    status_do_tipo_etapa, status_e_fim_de_linha, tipo_etapa_do_status, Atendimento,
    AtendimentoRepository, PostgresAtendimentoRepository,
};
use infrastructure_postgres::atendimentos::campos::{
    CampoPersonalizadoRepository, PostgresCampoPersonalizadoRepository,
    PostgresValorCampoRepository, ValorCampoRepository,
};
use infrastructure_postgres::atendimentos::etiquetas::{
    EtiquetaRepository, NotaRepository, PostgresEtiquetaRepository, PostgresNotaRepository,
};
use infrastructure_postgres::atendimentos::mensagens::{
    DestinoEnvioOutbound, Mensagem, MensagemRepository, PostgresMensagemRepository,
};
use infrastructure_postgres::atendimentos::movimentos::{
    MovimentoFluxoRepository, PostgresMovimentoFluxoRepository,
};
use infrastructure_postgres::clientes::contatos::{ContatoRepository, PostgresContatoRepository};
use infrastructure_postgres::idempotencia;
use infrastructure_postgres::operacional::atendentes::{
    AtendenteRepository, PostgresAtendenteRepository,
};
use infrastructure_postgres::operacional::fluxos::{
    EtapaFluxoRepository, FluxoAtendimentoRepository, FluxoDisponivel,
    PostgresEtapaFluxoRepository, PostgresFluxoAtendimentoRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};
use uuid::Uuid;

use crate::ports::atendimento::MidiaEnviada;
use crate::ports::{
    AtendimentoStore, CampoColetadoDto, CampoPendenteDto, CamposAtendimentoDto, OrigemMensagem,
    TicketKanbanOutcome, TransferenciaFluxoOutcome,
};

/// A saudação que o contato recebe quando alguém assume a conversa.
///
/// A v1 mandava um texto fixo — "Olá, meu nome é X, sou Vendedor da Ecoprint,
/// irei continuar seu atendimento" —, o que só funcionava num sistema de uma
/// empresa só. Aqui o cargo e a empresa saem do cadastro: é o mesmo
/// comportamento, dito por cada tenant com as palavras dele.
///
/// Cargo e empresa vazios não viram buraco no texto ("sou  da ,"): a frase
/// encolhe. Conta nova costuma ter os dois em branco, e uma saudação
/// esquisita é a primeira coisa que o cliente lê.
fn texto_da_saudacao(nome_atendente: &str, cargo: &str, empresa: &str) -> String {
    let cargo = cargo.trim();
    let empresa = empresa.trim();
    let quem = match (cargo.is_empty(), empresa.is_empty()) {
        (false, false) => format!(", sou {cargo} da {empresa}"),
        (false, true) => format!(", sou {cargo}"),
        (true, false) => format!(", da {empresa}"),
        (true, true) => String::new(),
    };
    format!("Olá, meu nome é {nome_atendente}{quem}, irei continuar seu atendimento.")
}

/// N8.5/E3 — pede a avaliação ao contato quando a conversa termina.
///
/// ## O defeito
///
/// `avaliacao` e `feedback` existem desde a migration 0006 e só apareciam em
/// SELECT. Ninguém nunca perguntou a nota — mas o scheduler rodava
/// `processar_feedback_vencido` e marcava como "expirado" todo atendimento
/// resolvido. A v2 expirava uma pesquisa que jamais existiu.
///
/// ## Regras
///
/// - **Só em `resolvido`.** Não se pede nota de atendimento que o cliente
///   cancelou nem de um arquivado administrativamente: no primeiro caso não houve
///   atendimento a avaliar, no segundo não há ninguém do outro lado esperando.
/// - **Só uma vez por atendimento** (`marcar_feedback_solicitado` é idempotente).
/// - **Só se o tenant quiser** (`pesquisa_satisfacao_ativa`).
/// - **Na MESMA transação do encerramento.** Se o status mudasse e a pesquisa não
///   saísse, o atendimento entraria na contagem de "aguardando resposta" sem
///   nunca ter perguntado nada — recriando o bug numa forma nova.
///
/// Devolve `true` quando a pesquisa foi criada.
async fn solicitar_pesquisa_satisfacao(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    novo_status: &str,
) -> Result<bool, DbError> {
    if novo_status != "resolvido" {
        return Ok(false);
    }

    // Cascata Tenant > CoreSettings resolvida em uma consulta só: o adapter não
    // tem o `TenantConfigCache` (ele vive no serviço, não na transação), e abrir
    // um round-trip de cache aqui dentro quebraria a atomicidade que é o ponto.
    let cfg = sqlx::query_as::<_, (Option<String>, Option<bool>, Option<String>, Option<String>)>(
        r#"SELECT tc.msg_pesquisa_satisfacao,
                  tc.pesquisa_satisfacao_ativa,
                  txt.value,
                  flag.value
           FROM (SELECT 1) AS _base
           LEFT JOIN tenants_tenantconfig tc ON tc.tenant_id = $1
           LEFT JOIN settings_manager_coresettings txt ON txt.key = 'MSG_PESQUISA_SATISFACAO'
           LEFT JOIN settings_manager_coresettings flag ON flag.key = 'PESQUISA_SATISFACAO_ATIVA'"#,
    )
    .bind(ctx.tenant_id)
    .fetch_optional(&mut **tx)
    .await?;

    let (msg_tenant, ativa_tenant, msg_global, flag_global) = cfg.unwrap_or_default();

    // Default `true`: pedir avaliação é o comportamento da v1, e desligá-lo por
    // omissão apagaria a métrica de satisfação logo na migração.
    let ativa = ativa_tenant.unwrap_or_else(|| {
        flag_global
            .map(|v| v.eq_ignore_ascii_case("true"))
            .unwrap_or(true)
    });
    if !ativa {
        return Ok(false);
    }

    // Contato na whitelist de IGNORADOS não recebe a pesquisa.
    //
    // Parece redundante — quem está na lista não gera atendimento, porque o
    // `webhook_ingress` descarta na ingestão. Mas o filtro age no momento da
    // MENSAGEM, e a lista muda com o tempo: um número adicionado à whitelist
    // depois de já ter um atendimento aberto (diretoria, número de teste que
    // virou interno) continuaria recebendo o pedido de avaliação ao encerrarem
    // a conversa dele. A checagem aqui é o que faz a lista valer para o ciclo
    // inteiro, e não só para a porta de entrada.
    let ignorado: Option<i32> = sqlx::query_scalar(
        r#"SELECT 1
           FROM oraculo_atendimento a
           JOIN oraculo_contato c ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
           JOIN whatsapp_whitelist w
             ON w.tenant_id = a.tenant_id AND w.phone_number = c.telefone AND w.active = TRUE
           WHERE a.tenant_id = $1 AND a.id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;
    if ignorado.is_some() {
        return Ok(false);
    }

    let texto = msg_tenant
        .filter(|t| !t.trim().is_empty())
        .or(msg_global)
        .filter(|t| !t.trim().is_empty())
        .unwrap_or_else(|| TEXTO_PESQUISA_PADRAO.to_string());

    let repo = PostgresAtendimentoRepository;
    // Idempotência: a segunda passagem pelo mesmo encerramento não repergunta.
    if !repo
        .marcar_feedback_solicitado(tx, ctx, atendimento_id)
        .await?
    {
        return Ok(false);
    }

    let msg = PostgresMensagemRepository
        .criar(
            tx,
            ctx,
            infrastructure_postgres::atendimentos::mensagens::NovaMensagem {
                atendimento_id,
                tipo: "extendedTextMessage",
                conteudo: &texto,
                // "bot": a pergunta é do sistema, não de um atendente. O worker
                // envia mensagens de bot que ainda estão `pending` — a resposta
                // que ele mesmo já entregou nasce `sent` e não é reenviada.
                remetente: "bot",
                message_id_whatsapp: None,
                mensagem_citada_id: None,
                ja_entregue: false,
            },
        )
        .await?;
    repo.touch_last_message(tx, ctx, atendimento_id).await?;

    let evento = serde_json::json!({
        "message_id": msg.id.to_string(),
        "sender_id": msg.remetente,
        "content": msg.conteudo,
        "timestamp": msg.timestamp.timestamp_millis(),
    });
    sqlx::query(
        "INSERT INTO outbox (tenant_id, event_type, payload, traceparent) VALUES ($1, $2, $3, $4)",
    )
    .bind(ctx.tenant_id)
    .bind("message.persisted")
    .bind(serde_json::to_vec(&evento).map_err(|e| DbError::ConfigError(e.to_string()))?)
    .bind("")
    .execute(&mut **tx)
    .await?;

    Ok(true)
}

/// Último elo da cascata do texto da pesquisa. A migration 0028 semeia o mesmo
/// texto como CoreSetting; esta constante cobre a base que ainda não a rodou.
const TEXTO_PESQUISA_PADRAO: &str = "Seu atendimento foi encerrado. Que nota de 1 a 5 você dá para o atendimento que recebeu? Se quiser, escreva também o que achou.";

/// Implementação Postgres da port Atendimento.
/// `admin_pool` (BYPASSRLS) é usado apenas nas varreduras cross-tenant do
/// scheduler do worker (F4.3b); quando ausente, recai no pool de aplicação
/// (RLS ativa, resultado vazio) com aviso observável — mesmo padrão de
/// `PgWhatsappStore::admin_listar_conectadas`.
#[derive(Clone)]
pub struct PgAtendimentoStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
}

impl PgAtendimentoStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
    }
}

#[async_trait]
impl AtendimentoStore for PgAtendimentoStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn listar_mensagens(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let mensagens = repo
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id, limit, offset)
                .await?;
            Ok((mensagens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, status = status))]
    async fn listar_atendimentos(
        &self,
        ctx: &RequestContext,
        status: &str,
        departamento_id: Option<i32>,
        limit: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        let repo = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let status = status.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let atendimentos = repo
                .listar_por_status(&mut tx, &ctx, &status, departamento_id, limit)
                .await?;
            Ok((atendimentos, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn persistir_mensagem(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        tipo: &str,
        conteudo: &str,
        remetente: &str,
        traceparent: &str,
        action_id: Option<Uuid>,
        origem: OrigemMensagem,
    ) -> Result<Mensagem, DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let tipo = tipo.to_string();
        let conteudo = conteudo.to_string();
        let remetente = remetente.to_string();
        let traceparent = traceparent.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            // N7.2 — dedupe atômico: reenviar o mesmo action_id (ex.: mensagem
            // outbound do atendente via sync offline) devolve a mensagem já
            // persistida da primeira vez, sem duplicar nem republicar no outbox.
            if let Some(action_id) = action_id {
                if let Some(resultado) =
                    idempotencia::buscar_acao_aplicada(&mut tx, tenant_id, action_id).await?
                {
                    let msg: Mensagem = serde_json::from_value(resultado).map_err(|e| {
                        DbError::ConfigError(format!(
                            "resultado idempotente corrompido para action_id {action_id}: {e}"
                        ))
                    })?;
                    return Ok((msg, tx));
                }
            }

            // Dedupe pela chave natural do provedor: o barramento é at-least-once,
            // então o MESMO evento do WhatsApp pode chegar duas vezes (reentrega da
            // PEL após falha de um passo posterior do handler). Sem esta checagem a
            // mensagem apareceria duplicada no chat do atendente — e o bot
            // responderia duas vezes. Vale para todo caminho que informe o stanzaId,
            // inclusive os que não têm `action_id`.
            if let Some(ref wa_id) = origem.message_id_whatsapp {
                if let Some(msg) = repo.buscar_por_whatsapp_id(&mut tx, &ctx, wa_id).await? {
                    tracing::debug!(
                        mensagem_id = msg.id,
                        "mensagem já persistida para este stanzaId; reentrega ignorada"
                    );
                    return Ok((msg, tx));
                }
            }

            // Citação (reply): o webhook informa o stanzaId da mensagem citada; o
            // banco guarda o id interno. Não encontrar a citada é normal (mensagem
            // anterior à integração, ou já purgada) — a mensagem entra sem citação.
            let mensagem_citada_id = match origem.citando_message_id_whatsapp {
                Some(ref citado) if !citado.is_empty() => repo
                    .buscar_por_whatsapp_id(&mut tx, &ctx, citado)
                    .await?
                    .map(|m| m.id),
                _ => None,
            };

            let msg = repo
                .criar(
                    &mut tx,
                    &ctx,
                    infrastructure_postgres::atendimentos::mensagens::NovaMensagem {
                        atendimento_id,
                        tipo: &tipo,
                        conteudo: &conteudo,
                        remetente: &remetente,
                        message_id_whatsapp: origem.message_id_whatsapp.as_deref(),
                        mensagem_citada_id,
                        ja_entregue: origem.ja_entregue,
                    },
                )
                .await?;

            let repo_atendimento = PostgresAtendimentoRepository;
            repo_atendimento.touch_last_message(&mut tx, &ctx, atendimento_id).await?;

            // Padrão OUTBOX: insere o evento de domínio na MESMA transação ACID.
            let event_payload = serde_json::json!({
                "message_id": msg.id.to_string(),
                "sender_id": msg.remetente,
                "content": msg.conteudo,
                "timestamp": msg.timestamp.timestamp_millis(),
            });
            let event_payload_bytes = serde_json::to_vec(&event_payload)
                .map_err(|e| DbError::ConfigError(e.to_string()))?;

            sqlx::query(
                "INSERT INTO outbox (tenant_id, event_type, payload, traceparent) VALUES ($1, $2, $3, $4)",
            )
            .bind(tenant_id)
            .bind("message.persisted")
            .bind(event_payload_bytes)
            .bind(&traceparent)
            .execute(&mut *tx)
            .await?;

            if let Some(action_id) = action_id {
                let resultado = serde_json::to_value(&msg).map_err(|e| {
                    DbError::ConfigError(format!("falha ao serializar mensagem: {e}"))
                })?;
                idempotencia::registrar_acao_aplicada(&mut tx, tenant_id, action_id, &resultado)
                    .await?;
            }

            Ok((msg, tx))
        })
        .await
    }

    /// `skip_all`: `bytes` entra por campo; nada mais desta chamada é seguro
    /// logar (a chave devolvida identifica o objeto do tenant).
    #[tracing::instrument(
        skip_all,
        fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, bytes = bytes)
    )]
    async fn autorizar_upload_midia(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        bytes: i64,
    ) -> Result<String, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let pool = self.pool.clone();
        run_in_tenant_transaction(&pool, tenant_id, move |mut tx| async move {
            // O atendimento tem de existir NESTE tenant. A RLS já isola, então
            // "não encontrado" cobre também "é de outro tenant" — e é o que deve
            // ser dito de volta: confirmar a existência de um id alheio já
            // vazaria informação.
            let atendimento = PostgresAtendimentoRepository
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .ok_or(DbError::NotFound)?;

            // Mesmo RBAC fino do arrasto: quem não pode mexer no cartão não
            // manda arquivo na conversa dele.
            if let Some(fluxo_id) = atendimento.fluxo_atendimento_id {
                ctx.exigir_fluxo(fluxo_id)?;
            }

            // Quota de armazenamento (N7.1). Diferente do resto do sistema, aqui
            // ela MORDE: o guard nasceu log-only para observação, mas deixar o
            // upload passar da quota significa pagar armazenamento que o plano
            // não cobre, num caminho que o próprio tenant dispara à vontade.
            let uso: Option<(i64, i64)> = sqlx::query_as(
                r#"SELECT COALESCE(u.total_bytes, 0), COALESCE(p.max_storage_bytes, 0)
                   FROM tenants_tenant t
                   LEFT JOIN tenants_storage_usage u ON u.tenant_id = t.id
                   LEFT JOIN tenants_subscription s ON s.tenant_id = t.id
                   LEFT JOIN tenants_plan p ON p.id = s.plan_id
                   WHERE t.id = $1"#,
            )
            .bind(tenant_id)
            .fetch_optional(&mut *tx)
            .await
            // A coluna de limite pode não existir em base antiga: tratar a falha
            // da consulta como "sem limite conhecido" evita bloquear o envio por
            // um detalhe de esquema.
            .unwrap_or(None);

            if let Some((usado, limite)) = uso {
                // Limite 0 = plano sem teto declarado.
                if limite > 0 && usado + bytes > limite {
                    return Err(DbError::ConfigError(
                        "limite de armazenamento do plano atingido".to_string(),
                    ));
                }
            }

            // A chave é do servidor, nunca do cliente: deixá-lo escolher
            // permitiria sobrescrever a mídia de outra conversa do mesmo tenant.
            // O `data_storage` prefixa o tenant, então ela não repete aqui.
            let chave = format!("outbound/{}/{}", atendimento_id, Uuid::now_v7());
            Ok((chave, tx))
        })
        .await
    }

    /// `skip_all`: legenda e nome do arquivo são conteúdo do usuário.
    #[tracing::instrument(
        skip_all,
        fields(
            tenant_id = %ctx.tenant_id,
            atendimento_id = midia.atendimento_id,
            categoria = %midia.categoria,
            bytes = midia.bytes
        )
    )]
    async fn enviar_midia(
        &self,
        ctx: &RequestContext,
        midia: MidiaEnviada,
        traceparent: &str,
        action_id: Option<Uuid>,
    ) -> Result<Mensagem, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let traceparent = traceparent.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, move |mut tx| async move {
            // Mesmo dedupe do envio de texto (N7.2): reenviar o mesmo action_id
            // devolve a mensagem já criada em vez de duplicar o anexo no chat.
            if let Some(action_id) = action_id {
                if let Some(resultado) =
                    idempotencia::buscar_acao_aplicada(&mut tx, tenant_id, action_id).await?
                {
                    let msg: Mensagem = serde_json::from_value(resultado).map_err(|e| {
                        DbError::ConfigError(format!("resultado idempotente corrompido: {e}"))
                    })?;
                    return Ok((msg, tx));
                }
            }

            // O tipo segue o vocabulário do WhatsApp, que é o que o worker manda
            // adiante e o que a v1 gravava — não uma taxonomia nossa.
            let tipo = match midia.categoria.as_str() {
                "image" => "imageMessage",
                "audio" if midia.is_ptt => "audioMessage",
                "audio" => "audioMessage",
                "video" => "videoMessage",
                _ => "documentMessage",
            };

            let msg = PostgresMensagemRepository
                .criar(
                    &mut tx,
                    &ctx,
                    infrastructure_postgres::atendimentos::mensagens::NovaMensagem {
                        atendimento_id: midia.atendimento_id,
                        tipo,
                        // A legenda é o texto da bolha; sem ela, o nome do
                        // arquivo é o que o atendente vê no lugar do vazio.
                        conteudo: if midia.legenda.trim().is_empty() {
                            &midia.nome_arquivo
                        } else {
                            &midia.legenda
                        },
                        remetente: "atendente",
                        message_id_whatsapp: None,
                        mensagem_citada_id: None,
                        // Ainda não passou pelo WhatsApp: é o worker que envia.
                        ja_entregue: false,
                    },
                )
                .await?;

            // Ponteiro do objeto + metadados que a tela precisa para montar o
            // player sem baixar o arquivo.
            sqlx::query(
                r#"UPDATE oraculo_mensagem
                   SET arquivo_midia = $3,
                       mimetype_midia = $4,
                       nome_arquivo_midia = $5,
                       tamanho_midia = $6
                   WHERE tenant_id = $1 AND id = $2"#,
            )
            .bind(tenant_id)
            .bind(msg.id)
            .bind(&midia.chave)
            .bind(&midia.mimetype)
            .bind(&midia.nome_arquivo)
            .bind(midia.bytes)
            .execute(&mut *tx)
            .await?;

            PostgresAtendimentoRepository
                .touch_last_message(&mut tx, &ctx, midia.atendimento_id)
                .await?;

            // Contabilidade de armazenamento na MESMA transação da mensagem: se
            // fosse depois, uma falha entre as duas deixaria bytes no bucket que
            // o tenant nunca pagaria.
            sqlx::query(
                r#"INSERT INTO tenants_storage_usage (tenant_id, total_bytes)
                   VALUES ($1, $2)
                   ON CONFLICT (tenant_id)
                   DO UPDATE SET total_bytes = tenants_storage_usage.total_bytes + $2,
                                 updated_at = NOW()"#,
            )
            .bind(tenant_id)
            .bind(midia.bytes)
            .execute(&mut *tx)
            .await?;

            let evento = serde_json::json!({
                "message_id": msg.id.to_string(),
                "sender_id": msg.remetente,
                "content": msg.conteudo,
                "timestamp": msg.timestamp.timestamp_millis(),
                // O worker precisa saber que é mídia para chamar SendWhatsappMedia
                // em vez de SendWhatsappMessage.
                "midia": {
                    "chave": midia.chave,
                    "mimetype": midia.mimetype,
                    "categoria": midia.categoria,
                    "nome_arquivo": midia.nome_arquivo,
                    "is_ptt": midia.is_ptt,
                },
            });
            sqlx::query(
                "INSERT INTO outbox (tenant_id, event_type, payload, traceparent) \
                 VALUES ($1, $2, $3, $4)",
            )
            .bind(tenant_id)
            .bind("message.persisted")
            .bind(serde_json::to_vec(&evento).map_err(|e| DbError::ConfigError(e.to_string()))?)
            .bind(&traceparent)
            .execute(&mut *tx)
            .await?;

            if let Some(action_id) = action_id {
                let resultado =
                    serde_json::to_value(&msg).map_err(|e| DbError::ConfigError(e.to_string()))?;
                idempotencia::registrar_acao_aplicada(&mut tx, tenant_id, action_id, &resultado)
                    .await?;
            }

            Ok((msg, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn listar_midias(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, move |mut tx| async move {
            let rows = sqlx::query_as::<_, Mensagem>(
                r#"SELECT * FROM oraculo_mensagem
                   WHERE tenant_id = $1 AND atendimento_id = $2
                     AND arquivo_midia IS NOT NULL
                     -- Mídia purgada pela retenção continua com o ponteiro, mas o
                     -- objeto não existe mais: mostrá-la daria um player quebrado.
                     AND midia_purgada_em IS NULL
                   ORDER BY timestamp DESC
                   LIMIT $3 OFFSET $4"#,
            )
            .bind(tenant_id)
            .bind(atendimento_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&mut *tx)
            .await?;
            Ok((rows, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, telefone = %telefone))]
    async fn resolver_atendimento_para_contato(
        &self,
        ctx: &RequestContext,
        telefone: &str,
        push_name: Option<String>,
    ) -> Result<(i32, Atendimento, bool), DbError> {
        let repo_contato = PostgresContatoRepository;
        let repo_atendimento = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let telefone = telefone.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            // 1. Busca ou cria o contato
            let contato = match repo_contato
                .buscar_por_telefone(&mut tx, &ctx, &telefone)
                .await?
            {
                Some(c) => c,
                None => {
                    repo_contato
                        .salvar(&mut tx, &ctx, &telefone, push_name.as_deref())
                        .await?
                }
            };

            let mut is_new = false;
            // 2. Busca se já existe um atendimento ativo para o contato
            let atendimento = match repo_atendimento
                .buscar_ativo_por_contato(&mut tx, &ctx, contato.id)
                .await?
            {
                Some(a) => a,
                None => {
                    is_new = true;
                    // Cria um novo atendimento
                    repo_atendimento
                        .criar(&mut tx, &ctx, contato.id, None, None, None)
                        .await?
                }
            };

            Ok(((contato.id, atendimento, is_new), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, message_id_whatsapp = %message_id_whatsapp, status = %status))]
    async fn atualizar_status_mensagem(
        &self,
        ctx: &RequestContext,
        message_id_whatsapp: &str,
        status: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let message_id_whatsapp = message_id_whatsapp.to_string();
        let status = status.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.atualizar_status_por_whatsapp_id(&mut tx, &ctx, &message_id_whatsapp, &status)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn aplicar_politica_ticket_kanban(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<TicketKanbanOutcome, DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_fluxo = PostgresFluxoAtendimentoRepository;
        let repo_etapa = PostgresEtapaFluxoRepository;
        let repo_movimento = PostgresMovimentoFluxoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let atendimento = match repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
            {
                Some(a) => a,
                None => {
                    let outcome = TicketKanbanOutcome {
                        status: "desconhecido".to_string(),
                        reason: Some("atendimento_inexistente".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Idempotência: se já está numa etapa, não move de novo.
            if atendimento.etapa_atual_id.is_some() {
                let outcome = TicketKanbanOutcome {
                    status: atendimento.status.clone(),
                    fluxo_id: atendimento.fluxo_atendimento_id,
                    etapa_id: atendimento.etapa_atual_id,
                    reason: Some("ja_posicionado".to_string()),
                    ..Default::default()
                };
                return Ok((outcome, tx));
            }

            // Resolve o fluxo: o do atendimento (se houver) ou o primeiro ativo do tenant.
            let fluxo = match atendimento.fluxo_atendimento_id {
                Some(fid) => repo_fluxo.buscar_por_id(&mut tx, &ctx, fid).await?,
                None => repo_fluxo.buscar_primeiro_ativo(&mut tx, &ctx).await?,
            };
            let fluxo = match fluxo {
                Some(f) => f,
                None => {
                    let outcome = TicketKanbanOutcome {
                        status: atendimento.status.clone(),
                        reason: Some("sem_fluxo".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Etapa de entrada (tipo 'fila') do fluxo.
            let etapa = match repo_etapa
                .get_etapa_inicial(&mut tx, &ctx, fluxo.id)
                .await?
            {
                Some(e) => e,
                None => {
                    let outcome = TicketKanbanOutcome {
                        status: atendimento.status.clone(),
                        fluxo_id: Some(fluxo.id),
                        reason: Some("sem_etapa_inicial".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Posiciona o atendimento e registra o movimento automático de entrada.
            repo_atendimento
                .atribuir_fluxo_etapa(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    fluxo.id,
                    Some(fluxo.departamento_id),
                    etapa.id,
                )
                .await?;
            repo_movimento
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    None,
                    etapa.id,
                    None,
                    Some("entrada automática no fluxo"),
                    true,
                )
                .await?;

            let outcome = TicketKanbanOutcome {
                moved: true,
                status: "fila".to_string(),
                etapa_id: Some(etapa.id),
                etapa_nome: Some(etapa.nome),
                fluxo_id: Some(fluxo.id),
                reason: None,
            };
            Ok((outcome, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, etapa_destino_id = etapa_destino_id))]
    async fn mover_etapa_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_destino_id: i32,
        motivo: &str,
        action_id: Option<Uuid>,
    ) -> Result<(), DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_movimento = PostgresMovimentoFluxoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let motivo = (!motivo.is_empty()).then(|| motivo.to_string());
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            // N7.2 — dedupe atômico: reenviar a mesma ação (mesmo action_id) não
            // reaplica o movimento, só confirma o já aplicado (mesma transação).
            if let Some(action_id) = action_id {
                if idempotencia::buscar_acao_aplicada(&mut tx, tenant_id, action_id)
                    .await?
                    .is_some()
                {
                    return Ok(((), tx));
                }
            }

            let atendimento = repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .ok_or(DbError::NotFound)?;

            // RBAC fino por fluxo (WS-5a): só quem tem flow_permission do fluxo atual
            // do atendimento (ou bypass kanban:admin/tenant:admin) pode movê-lo.
            if let Some(fluxo_id) = atendimento.fluxo_atendimento_id {
                ctx.exigir_fluxo(fluxo_id)?;
            }

            let etapa_origem_id = atendimento.etapa_atual_id;

            repo_atendimento
                .atualizar_etapa(&mut tx, &ctx, atendimento_id, etapa_destino_id, None)
                .await?;

            // A coluna manda no status. Um cartão parado na finalização com
            // status `fila` é uma contradição que quem opera lê como sistema
            // quebrado — e é o próprio quadro que a pessoa acabou de mexer.
            //
            // As regras por tipo de etapa são as da v1
            // (`board_service._aplicar_regras_tipo_etapa`), incluindo o que
            // NÃO se faz: voltar para a fila não religa o bot.
            if let Some(etapa) = PostgresEtapaFluxoRepository
                .buscar_por_id(&mut tx, &ctx, etapa_destino_id)
                .await?
            {
                // O nome da coluna de finalização decide entre resolvido,
                // cancelado e arquivado — um fluxo tem mais de uma.
                if let Some(novo_status) = status_do_tipo_etapa(&etapa.tipo_etapa, &etapa.nome) {
                    // Um `cancelado` não vira `resolvido` só porque o cartão
                    // andou dentro da finalização: os dois encerram, por
                    // motivos diferentes, e o relatório distingue.
                    let manter = status_e_fim_de_linha(&atendimento.status)
                        && status_e_fim_de_linha(novo_status);
                    if !manter && atendimento.status != novo_status {
                        repo_atendimento
                            .atualizar_status(&mut tx, &ctx, atendimento_id, novo_status)
                            .await?;
                        repo_atendimento
                            .registrar_historico_status(
                                &mut tx,
                                &ctx,
                                atendimento_id,
                                novo_status,
                                &format!("Movido para \"{}\" no quadro", etapa.nome),
                            )
                            .await?;

                        // N8.5/E3: arrastar o cartão para a finalização encerra a
                        // conversa tanto quanto apertar o botão — os dois caminhos
                        // precisam pedir a avaliação, senão a pesquisa depende de
                        // por onde o atendente encerrou.
                        solicitar_pesquisa_satisfacao(&mut tx, &ctx, atendimento_id, novo_status)
                            .await?;
                    }
                }

                match etapa.tipo_etapa.as_str() {
                    // Assumir: quem arrasta para "em atendimento" vira dono da
                    // conversa e DESLIGA o bot. Sem isso, o robô seguiria
                    // respondendo por cima de quem acabou de assumir — é a
                    // regra-chave da v1 (`transferir_para_humano`).
                    "trabalho" if atendimento.atendente_humano_id.is_none() => {
                        // Nem todo usuário do tenant é atendente: um admin que
                        // arrasta um cartão não vira dono da conversa. Sem
                        // atendente correspondente, o cartão anda e o bot fica
                        // como está.
                        if let Some(atendente) = PostgresAtendenteRepository
                            .buscar_por_usuario(&mut tx, &ctx, ctx.user_id)
                            .await?
                        {
                            repo_atendimento
                                .assumir_atendimento(&mut tx, &ctx, atendimento_id, atendente.id)
                                .await?;
                            repo_atendimento
                                .registrar_historico_status(
                                    &mut tx,
                                    &ctx,
                                    atendimento_id,
                                    "em_atendimento",
                                    &format!("Assumido por {}", atendente.nome),
                                )
                                .await?;

                            // Saudação automática (v1:
                            // `transferir_para_humano_com_saudacao`). O bot
                            // acabou de ser desligado; sem uma palavra, o
                            // contato fica falando com o silêncio até alguém
                            // digitar.
                            let empresa = sqlx::query_scalar!(
                                "SELECT name FROM tenants_tenant WHERE id = $1",
                                ctx.tenant_id
                            )
                            .fetch_optional(&mut *tx)
                            .await?
                            .unwrap_or_default();

                            let saudacao =
                                texto_da_saudacao(&atendente.nome, &atendente.cargo, &empresa);

                            // Na MESMA transação do movimento: se o cartão
                            // andar e a saudação não sair, o contato fica sem
                            // resposta com o bot já desligado.
                            let msg = PostgresMensagemRepository
                                .criar(
                                    &mut tx,
                                    &ctx,
                                    infrastructure_postgres::atendimentos::mensagens::NovaMensagem {
                                        atendimento_id,
                                        tipo: "extendedTextMessage",
                                        conteudo: &saudacao,
                                        // `atendente` é o que o worker procura
                                        // no outbox para enviar de verdade.
                                        remetente: "atendente",
                                        message_id_whatsapp: None,
                                        mensagem_citada_id: None,
                                        ja_entregue: false,
                                    },
                                )
                                .await?;
                            repo_atendimento
                                .touch_last_message(&mut tx, &ctx, atendimento_id)
                                .await?;

                            let evento = serde_json::json!({
                                "message_id": msg.id.to_string(),
                                "sender_id": msg.remetente,
                                "content": msg.conteudo,
                                "timestamp": msg.timestamp.timestamp_millis(),
                            });
                            sqlx::query(
                                "INSERT INTO outbox (tenant_id, event_type, payload, traceparent) \
                                 VALUES ($1, $2, $3, $4)",
                            )
                            .bind(tenant_id)
                            .bind("message.persisted")
                            .bind(
                                serde_json::to_vec(&evento)
                                    .map_err(|e| DbError::ConfigError(e.to_string()))?,
                            )
                            .bind("")
                            .execute(&mut *tx)
                            .await?;
                        }
                    }
                    // Voltar para a fila é devolver a conversa: mantê-la
                    // atribuída a quem a largou faria o rodízio pular quem está
                    // livre. O bot NÃO é religado aqui (ver `desatribuir`).
                    "fila" if atendimento.atendente_humano_id.is_some() => {
                        repo_atendimento
                            .desatribuir(&mut tx, &ctx, atendimento_id)
                            .await?;
                    }
                    _ => {}
                }
            }

            repo_movimento
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    etapa_origem_id,
                    etapa_destino_id,
                    None,
                    motivo.as_deref(),
                    false,
                )
                .await?;

            if let Some(action_id) = action_id {
                idempotencia::registrar_acao_aplicada(
                    &mut tx,
                    tenant_id,
                    action_id,
                    &serde_json::json!({ "status": "success" }),
                )
                .await?;
            }

            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, novo_status = %novo_status))]
    async fn definir_status_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        novo_status: String,
        motivo: String,
    ) -> Result<serde_json::Value, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, move |mut tx| async move {
            let repo = PostgresAtendimentoRepository;
            let atendimento = repo
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .ok_or(DbError::NotFound)?;

            // Mesmo RBAC fino do arrasto: quem não pode mover o cartão também
            // não pode encerrar a conversa por outro botão.
            if let Some(fluxo_id) = atendimento.fluxo_atendimento_id {
                ctx.exigir_fluxo(fluxo_id)?;
            }

            repo.atualizar_status(&mut tx, &ctx, atendimento_id, &novo_status)
                .await?;
            repo.registrar_historico_status(
                &mut tx,
                &ctx,
                atendimento_id,
                &novo_status,
                if motivo.is_empty() {
                    "Estado alterado pelo atendente"
                } else {
                    &motivo
                },
            )
            .await?;

            if novo_status == "fila" && atendimento.atendente_humano_id.is_some() {
                repo.desatribuir(&mut tx, &ctx, atendimento_id).await?;
            }

            // N8.5/E3 — encerrou, então pergunta. Na mesma transação: um
            // atendimento que vira "resolvido" sem a pesquisa sair entraria na
            // contagem de "aguardando resposta" sem ter perguntado nada.
            let pesquisa_solicitada =
                solicitar_pesquisa_satisfacao(&mut tx, &ctx, atendimento_id, &novo_status).await?;

            // A coluna acompanha. Quando o fluxo não tem etapa daquele tipo, o
            // cartão fica onde está — mover para lugar nenhum seria pior que
            // deixá-lo visível na coluna antiga.
            let mut etapa_destino = None;
            if let (Some(fluxo_id), Some(tipo)) = (
                atendimento.fluxo_atendimento_id,
                tipo_etapa_do_status(&novo_status),
            ) {
                if let Some(etapa) = PostgresEtapaFluxoRepository
                    .buscar_por_tipo(&mut tx, &ctx, fluxo_id, tipo)
                    .await?
                {
                    if Some(etapa.id) != atendimento.etapa_atual_id {
                        repo.atualizar_etapa(&mut tx, &ctx, atendimento_id, etapa.id, None)
                            .await?;
                        PostgresMovimentoFluxoRepository
                            .criar(
                                &mut tx,
                                &ctx,
                                atendimento_id,
                                atendimento.etapa_atual_id,
                                etapa.id,
                                None,
                                (!motivo.is_empty()).then_some(motivo.as_str()),
                                // Automático: o histórico distingue o que uma
                                // pessoa arrastou do que o sistema mexeu.
                                true,
                            )
                            .await?;
                        etapa_destino = Some(etapa.id);
                    }
                }
            }

            let json = serde_json::json!({
                "sucesso": true,
                "status": novo_status,
                "etapa_atual_id": etapa_destino.or(atendimento.etapa_atual_id),
                // Sai no retorno para o handler poder auditar
                // `atendimento.pesquisa_solicitada`: a trilha de auditoria é
                // publicada no barramento, e a transação não tem acesso a ela.
                "pesquisa_solicitada": pesquisa_solicitada,
            });
            Ok((json, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(limite = limite, ttl_horas = ttl_horas))]
    async fn listar_feedback_vencido(
        &self,
        ctx: &RequestContext,
        limite: i64,
        ttl_horas: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        if self.admin_pool.is_none() {
            tracing::warn!(
                "listar_feedback_vencido sem DATABASE_ADMIN_URL: a RLS bloqueará a \
                 varredura cross-tenant e a lista virá vazia"
            );
        }
        let effective_pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let repo = PostgresAtendimentoRepository;
        let mut tx = effective_pool.begin().await?;
        let rows = repo
            .listar_feedback_vencido(&mut tx, ctx, limite, ttl_horas)
            .await?;
        tx.commit().await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn marcar_feedback_expirado(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_feedback_expirado(&mut tx, &ctx, atendimento_id)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn aguardando_avaliacao(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        ttl_horas: i64,
    ) -> Result<bool, DbError> {
        let repo = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, move |mut tx| async move {
            let r = repo
                .aguardando_avaliacao(&mut tx, &ctx, atendimento_id, ttl_horas)
                .await?;
            Ok((r, tx))
        })
        .await
    }

    /// `skip_all` e sem `comentario` nos campos: é texto livre do cliente (PII).
    /// Só a nota entra no span.
    #[tracing::instrument(
        skip_all,
        fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, nota = nota)
    )]
    async fn registrar_avaliacao(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        comentario: &str,
    ) -> Result<bool, DbError> {
        let repo = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let comentario = comentario.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, move |mut tx| async move {
            let r = repo
                .registrar_avaliacao(&mut tx, &ctx, atendimento_id, nota, &comentario)
                .await?;
            Ok((r, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(limite = limite, idade_max_dias = idade_max_dias))]
    async fn listar_midias_expiradas(
        &self,
        ctx: &RequestContext,
        limite: i64,
        idade_max_dias: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        if self.admin_pool.is_none() {
            tracing::warn!(
                "listar_midias_expiradas sem DATABASE_ADMIN_URL: a RLS bloqueará a \
                 varredura cross-tenant e a lista virá vazia"
            );
        }
        let effective_pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let repo = PostgresMensagemRepository;
        let mut tx = effective_pool.begin().await?;
        let rows = repo
            .listar_midias_expiradas(&mut tx, ctx, limite, idade_max_dias)
            .await?;
        tx.commit().await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_midia_purgada(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_midia_purgada(&mut tx, &ctx, mensagem_id)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn resolver_destino_envio_outbound(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<Option<DestinoEnvioOutbound>, DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let destino = repo
                .resolver_destino_envio_outbound(&mut tx, &ctx, mensagem_id)
                .await?;
            Ok((destino, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, dead_letter_id = dead_letter_id))]
    async fn reprocessar_dead_letter(
        &self,
        ctx: &RequestContext,
        dead_letter_id: i32,
        traceparent: &str,
    ) -> Result<String, DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let traceparent = traceparent.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let status = repo
                .reprocessar_dead_letter(&mut tx, &ctx, dead_letter_id, &traceparent)
                .await?;
            Ok((status.to_string(), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_mensagem_enviada(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        message_id_whatsapp: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let message_id_whatsapp = message_id_whatsapp.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_mensagem_enviada(&mut tx, &ctx, mensagem_id, &message_id_whatsapp)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_mensagem_falha_envio(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_mensagem_falha_envio(&mut tx, &ctx, mensagem_id)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn anexar_analise_midia(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        arquivo_midia: &str,
        analise_midia: &str,
        resumo_midia: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        // String vazia = campo ausente; converte para `None` (não sobrescreve).
        let arquivo = (!arquivo_midia.is_empty()).then(|| arquivo_midia.to_string());
        let analise = (!analise_midia.is_empty()).then(|| analise_midia.to_string());
        let resumo = (!resumo_midia.is_empty()).then(|| resumo_midia.to_string());
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.anexar_analise_midia(
                &mut tx,
                &ctx,
                mensagem_id,
                arquivo.as_deref(),
                analise.as_deref(),
                resumo.as_deref(),
            )
            .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_fluxos_do_tenant(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<FluxoDisponivel>, DbError> {
        let repo = PostgresFluxoAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let fluxos = repo.listar_ativos_do_tenant(&mut tx, &ctx).await?;
            Ok((fluxos, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, fluxo_id = fluxo_id))]
    async fn transferir_atendimento_para_fluxo(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
    ) -> Result<TransferenciaFluxoOutcome, DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_fluxo = PostgresFluxoAtendimentoRepository;
        let repo_etapa = PostgresEtapaFluxoRepository;
        let repo_movimento = PostgresMovimentoFluxoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            // Fluxo destino precisa existir e estar ativo.
            let fluxo = match repo_fluxo.buscar_por_id(&mut tx, &ctx, fluxo_id).await? {
                Some(f) if f.ativo => f,
                _ => {
                    let outcome = TransferenciaFluxoOutcome {
                        reason: Some("fluxo_inexistente".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Etapa de entrada (tipo 'fila') do fluxo destino.
            let etapa = match repo_etapa
                .get_etapa_inicial(&mut tx, &ctx, fluxo.id)
                .await?
            {
                Some(e) => e,
                None => {
                    let outcome = TransferenciaFluxoOutcome {
                        fluxo_id: Some(fluxo.id),
                        fluxo_nome: Some(fluxo.nome),
                        reason: Some("sem_etapa_inicial".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            let etapa_origem = repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .and_then(|a| a.etapa_atual_id);

            repo_atendimento
                .transferir_fluxo_etapa(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    fluxo.id,
                    fluxo.departamento_id,
                    etapa.id,
                )
                .await?;
            repo_movimento
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    etapa_origem,
                    etapa.id,
                    None,
                    Some("transferência automática pela IA"),
                    true,
                )
                .await?;

            let outcome = TransferenciaFluxoOutcome {
                transferido: true,
                fluxo_id: Some(fluxo.id),
                fluxo_nome: Some(fluxo.nome),
                etapa_id: Some(etapa.id),
                etapa_nome: Some(etapa.nome),
                reason: None,
            };
            Ok((outcome, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn resolver_campos_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<CamposAtendimentoDto, DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_campo = PostgresCampoPersonalizadoRepository;
        let repo_valor = PostgresValorCampoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let fluxo_id = repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .and_then(|a| a.fluxo_atendimento_id);

            // Catálogo aplicável: globais (sem filtro de fluxo) + os do fluxo atual
            // do atendimento, quando houver.
            let mut definicoes = repo_campo
                .listar_por_escopo(&mut tx, &ctx, "GLOBAL", None)
                .await?;
            if let Some(fluxo_id) = fluxo_id {
                definicoes.extend(
                    repo_campo
                        .listar_por_escopo(&mut tx, &ctx, "FLUXO", Some(fluxo_id))
                        .await?,
                );
            }

            let valores = repo_valor
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id)
                .await?;

            let mut coletados = Vec::new();
            let mut pendentes = Vec::new();
            for def in definicoes {
                let valor_existente = valores.iter().find(|v| v.campo_id == def.id);
                match valor_existente {
                    Some(v) => coletados.push(CampoColetadoDto {
                        slug: def.slug,
                        nome: def.nome,
                        // O valor é JSONB livre; string "crua" evita aspas duplas
                        // indevidas quando já é uma string JSON.
                        valor: v
                            .valor
                            .as_str()
                            .map(str::to_string)
                            .unwrap_or_else(|| v.valor.to_string()),
                    }),
                    None if def.obrigatorio => pendentes.push(CampoPendenteDto {
                        slug: def.slug,
                        nome: def.nome,
                        descricao: def.descricao,
                        hint: def.extrair_hint,
                    }),
                    None => {}
                }
            }

            Ok((
                CamposAtendimentoDto {
                    coletados,
                    pendentes,
                },
                tx,
            ))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, nota = nota))]
    async fn atualizar_sentimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        label: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let label = label.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.atualizar_sentimento(&mut tx, &ctx, atendimento_id, nota, &label)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn detalhe_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<serde_json::Value, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let repo_etiqueta = PostgresEtiquetaRepository;
            let catalogo = repo_etiqueta.listar_ativas(&mut tx, &ctx).await?;
            let aplicadas = repo_etiqueta
                .listar_do_atendimento(&mut tx, &ctx, atendimento_id)
                .await?;
            let notas = PostgresNotaRepository
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id)
                .await?;

            let json = serde_json::json!({
                "catalogo": catalogo,
                "etiquetas": aplicadas,
                "notas": notas,
            });
            Ok((json, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, nome = %nome))]
    async fn criar_etiqueta(
        &self,
        ctx: &RequestContext,
        nome: String,
        cor: String,
    ) -> Result<serde_json::Value, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let etiqueta = PostgresEtiquetaRepository
                .criar(&mut tx, &ctx, &nome, Some(&cor))
                .await?;
            let json = serde_json::to_value(&etiqueta)
                .map_err(|e| DbError::ConfigError(format!("falha ao serializar: {e}")))?;
            Ok((json, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, aplicar = aplicar))]
    async fn alternar_etiqueta(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
        aplicar: bool,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let repo = PostgresEtiquetaRepository;
            if aplicar {
                repo.aplicar(&mut tx, &ctx, atendimento_id, etiqueta_id)
                    .await?;
            } else {
                repo.remover(&mut tx, &ctx, atendimento_id, etiqueta_id)
                    .await?;
            }
            Ok((true, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn criar_nota(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        texto: String,
    ) -> Result<serde_json::Value, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            // `criado_por_id` fica nulo: o autor é um `auth_user`, e nem todo
            // usuário do tenant tem linha em `oraculo_atendente`. Gravar o id
            // errado seria pior que não gravar autor nenhum.
            let nota = PostgresNotaRepository
                .criar(&mut tx, &ctx, atendimento_id, &texto, None)
                .await?;
            let json = serde_json::to_value(&nota)
                .map_err(|e| DbError::ConfigError(format!("falha ao serializar: {e}")))?;
            Ok((json, tx))
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::texto_da_saudacao;

    /// A saudação é a primeira coisa que o contato lê depois que o bot cala.
    /// Um texto com buraco ("sou  da ,") é pior que um texto curto.
    #[test]
    fn com_cargo_e_empresa_a_frase_e_a_da_v1() {
        assert_eq!(
            texto_da_saudacao("Ana", "Vendedora", "Ecoprint"),
            "Olá, meu nome é Ana, sou Vendedora da Ecoprint, irei continuar seu atendimento."
        );
    }

    #[test]
    fn sem_cargo_a_frase_encolhe_em_vez_de_abrir_buraco() {
        assert_eq!(
            texto_da_saudacao("Ana", "", "Ecoprint"),
            "Olá, meu nome é Ana, da Ecoprint, irei continuar seu atendimento."
        );
    }

    #[test]
    fn sem_empresa_tambem() {
        assert_eq!(
            texto_da_saudacao("Ana", "Vendedora", ""),
            "Olá, meu nome é Ana, sou Vendedora, irei continuar seu atendimento."
        );
    }

    #[test]
    fn conta_nova_sem_cargo_nem_empresa_ainda_se_apresenta() {
        // É o caso mais comum de quem acabou de instalar: os dois em branco.
        assert_eq!(
            texto_da_saudacao("Ana", "", ""),
            "Olá, meu nome é Ana, irei continuar seu atendimento."
        );
    }

    #[test]
    fn espaco_em_branco_conta_como_vazio() {
        // Um campo com espaços passa em `is_empty` e produziria "sou   da  ,".
        assert_eq!(
            texto_da_saudacao("Ana", "   ", "  "),
            "Olá, meu nome é Ana, irei continuar seu atendimento."
        );
    }
}
