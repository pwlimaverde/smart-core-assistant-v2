//! Modelos de leitura do índice local — espelham os models Dart do módulo
//! operacional (`AtendimentoResumo`, `MensagemThread`, `AtendimentoEvento`).
//!
//! Datas são epoch-millis (`i64`) para casar com a borda gRPC (o Dart converte
//! para `DateTime` na fronteira). Campos opcionais viram `Option`.

use serde::{Deserialize, Serialize};

/// Resumo de um atendimento exibido na fila/Kanban.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, sqlx::FromRow)]
pub struct AtendimentoResumo {
    pub id: i64,
    pub contato_id: i64,
    pub status: String,
    pub departamento_id: Option<i64>,
    pub fluxo_atendimento_id: Option<i64>,
    pub etapa_atual_id: Option<i64>,
    pub assunto: String,
    pub prioridade: String,
    pub atendente_humano_id: Option<i64>,
    pub data_inicio: i64,
    pub data_ultima_mensagem: Option<i64>,
}

/// Mensagem de um thread de atendimento (chat lateral).
///
/// `conteudo` é PII — nunca deve ser logado em claro.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, sqlx::FromRow)]
pub struct MensagemThread {
    pub id: i64,
    pub atendimento_id: i64,
    pub tipo: String,
    pub conteudo: String,
    pub remetente: String,
    pub timestamp: i64,
    pub status_envio: String,
    pub gerado_por_ia: bool,
    pub resumo_midia: Option<String>,
}

/// Evento realtime de atendimento (espelha o `AtendimentoEvento` do módulo
/// operacional). O `payload` nunca deve carregar conteúdo de mensagem (PII).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AtendimentoEvento {
    pub tipo: String,
    pub tenant_id: String,
    pub payload: serde_json::Value,
}
