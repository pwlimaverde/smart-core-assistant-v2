//! N8.5/E2 — buffer de agregação de rajada por contato.
//!
//! ## O defeito que este módulo corrige
//!
//! O worker aplicava um lock `SET NX EX 2` por remetente e deixava **só a primeira**
//! mensagem da janela acionar o bot. O cliente que escreve "oi" → "quero saber o
//! preço" → "do produto X" recebia uma resposta ao "oi": as outras duas entravam no
//! histórico e só influenciavam a pergunta *seguinte*.
//!
//! A v1 fazia o oposto (`evolution_sync/services/message_buffer.py` +
//! `_compile_message_content`): acumulava os envelopes do contato, esperava
//! `TIME_CACHE` (default 5 s) e compilava tudo com `"\n".join(texts)` antes de
//! chamar a IA uma única vez.
//!
//! ## Garantias que o lock dava de graça e o buffer precisa manter
//!
//! - **Idempotência**: o lock protegia por acaso (a segunda entrega perdia a
//!   corrida). Aqui o dedupe é explícito, por `message_id`, antes de enfileirar.
//! - **Uma resposta por rajada**: garantida pela chave `:timer` — quem consegue
//!   criá-la é o único agendador da janela.
//! - **Nunca perder mensagem**: a persistência acontece **antes** do buffer. Se o
//!   worker morrer com a rajada enfileirada, perde-se a *resposta automática*
//!   daquela janela, não a mensagem (mesmo comportamento da v1).
//!
//! ## Segurança
//!
//! O buffer guarda **conteúdo de mensagem no Redis** — PII em repouso, ainda que
//! transitória. Mitigações: TTL curto (janela × 10, teto de 300 s como na v1),
//! chave namespaced por tenant, e o conteúdo **nunca** vai para log/span/métrica —
//! só a contagem de mensagens agregadas.

use std::time::Duration;

use redis::aio::ConnectionManager;
use uuid::Uuid;

/// Janela de agregação padrão, em milissegundos. 5 s para bater com o `TIME_CACHE`
/// default da v1 — é tempo de digitação humana, não número arbitrário.
const JANELA_PADRAO_MS: u64 = 5_000;

/// Teto do TTL do buffer, em segundos (mesmo valor da v1). Buffer órfão — worker
/// que morreu no meio da janela — não pode viver para sempre carregando PII.
const TTL_MAXIMO_SEGUNDOS: u64 = 300;

/// Uma mensagem enfileirada na janela: o id serve ao dedupe, o texto à compilação.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
pub(crate) struct MensagemBufferizada {
    pub message_id: String,
    pub texto: String,
}

/// Resultado de enfileirar uma mensagem na janela do contato.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Enfileiramento {
    /// Esta chamada abriu a janela: quem recebe isto é o responsável por esperar
    /// e drenar. Exatamente uma mensagem por janela recebe este resultado.
    Agendador,
    /// A janela já estava aberta; a mensagem entrou nela e alguém já vai drenar.
    Acumulada,
    /// Sem Redis, ou o Redis falhou. O chamador deve **degradar para o
    /// comportamento antigo** (responder só a esta mensagem) — nunca engolir.
    Indisponivel,
}

/// Janela de agregação configurada. Override por tenant é lido do `RuntimeConfig`
/// (`time_cache` é chave de `CoreSettings` na v1, então o ETL da N12 já traz o
/// valor); na ausência dele vale a variável de ambiente e depois o default.
pub(crate) fn janela() -> Duration {
    let ms = std::env::var("SMARTCORE_BUFFER_JANELA_MS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .filter(|v| *v > 0)
        .unwrap_or(JANELA_PADRAO_MS);
    Duration::from_millis(ms)
}

fn chave_buffer(tenant: Uuid, sender: &str) -> String {
    format!("tenant:{tenant}:buf:{sender}")
}

fn chave_timer(tenant: Uuid, sender: &str) -> String {
    format!("tenant:{tenant}:buf:{sender}:timer")
}

/// TTL de segurança do buffer: janela × 10, limitado a `TTL_MAXIMO_SEGUNDOS`, com
/// piso de 1 s (o `EXPIRE` do Redis não aceita 0, que significaria "sem expiração"
/// em algumas implementações — e buffer sem TTL é PII imortal).
fn ttl_seguranca(janela: Duration) -> u64 {
    let bruto = janela.as_secs_f64() * 10.0;
    (bruto.ceil() as u64).clamp(1, TTL_MAXIMO_SEGUNDOS)
}

/// Compila os textos da janela como a v1 fazia: `"\n".join(texts)`, na ordem de
/// chegada, ignorando entradas vazias.
///
/// Ordem importa: "quero o preço" seguido de "do produto X" só faz sentido junto e
/// na sequência em que foi escrito.
pub(crate) fn compilar(mensagens: &[MensagemBufferizada]) -> String {
    mensagens
        .iter()
        .map(|m| m.texto.trim())
        .filter(|t| !t.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

/// Enfileira a mensagem na janela do contato e diz quem agenda o drenar.
///
/// Best-effort com degradação explícita: qualquer falha do Redis devolve
/// `Indisponivel`, e o chamador volta ao comportamento de responder só a esta
/// mensagem. Perder a agregação é aceitável; perder a resposta não é.
pub(crate) async fn enfileirar(
    conn: Option<&ConnectionManager>,
    tenant: Uuid,
    sender: &str,
    mensagem: &MensagemBufferizada,
    janela: Duration,
) -> Enfileiramento {
    let Some(conn) = conn else {
        return Enfileiramento::Indisponivel;
    };
    let mut conn = conn.clone();

    let chave = chave_buffer(tenant, sender);

    // Dedupe por `message_id`: a reentrega do mesmo evento pela PEL não pode
    // duplicar a fala do contato no texto que vai para a IA. A v1 faz a mesma
    // varredura em `set_buffer_contact`; a lista é curta (uma rajada humana), então
    // varrer sai mais barato que manter um índice paralelo.
    let existentes: Vec<String> = match redis::cmd("LRANGE")
        .arg(&chave)
        .arg(0)
        .arg(-1)
        .query_async(&mut conn)
        .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!("falha ao ler buffer de agregação: {e}");
            return Enfileiramento::Indisponivel;
        }
    };
    let ja_esta = existentes.iter().any(|bruto| {
        serde_json::from_str::<MensagemBufferizada>(bruto)
            .map(|m| m.message_id == mensagem.message_id)
            .unwrap_or(false)
    });

    // Guardado para poder desfazer o `RPUSH` se o agendamento falhar (ver abaixo).
    let mut payload_enfileirado: Option<String> = None;

    if !ja_esta {
        let payload = match serde_json::to_string(mensagem) {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!("falha ao serializar mensagem para o buffer: {e}");
                return Enfileiramento::Indisponivel;
            }
        };
        let push: Result<i64, _> = redis::cmd("RPUSH")
            .arg(&chave)
            .arg(&payload)
            .query_async(&mut conn)
            .await;
        if let Err(e) = push {
            tracing::warn!("falha ao enfileirar mensagem no buffer: {e}");
            return Enfileiramento::Indisponivel;
        }
        payload_enfileirado = Some(payload);
        let _: Result<i64, _> = redis::cmd("EXPIRE")
            .arg(&chave)
            .arg(ttl_seguranca(janela))
            .query_async(&mut conn)
            .await;
    }

    // Quem cria a chave do timer é o agendador da janela. `EX` em segundos com
    // arredondamento para cima: a chave só precisa sobreviver à espera, e expirar
    // antes do drenar deixaria uma segunda mensagem abrir janela concorrente.
    let janela_s = janela.as_secs_f64().ceil().max(1.0) as u64;
    let agendou: Result<bool, _> = redis::cmd("SET")
        .arg(chave_timer(tenant, sender))
        .arg("1")
        .arg("NX")
        .arg("EX")
        .arg(janela_s + 1)
        .query_async(&mut conn)
        .await;

    match agendou {
        Ok(true) => Enfileiramento::Agendador,
        Ok(false) => Enfileiramento::Acumulada,
        Err(e) => {
            // Falha pontual entre dois comandos da MESMA conexão: o `RPUSH` já
            // passou, o `SET` não. Sem desfazer o push, o chamador responderia a
            // esta mensagem sozinha (degradação) **e** ela continuaria no buffer
            // para o agendador anterior drenar — o contato receberia duas
            // respostas ao mesmo fragmento.
            //
            // O `LREM` remove exatamente a entrada que acabamos de inserir
            // (`count=-1`: da cauda para o início, uma ocorrência). Se ele também
            // falhar, a duplicata volta a ser possível — mas aí o Redis está
            // realmente fora, e o TTL do buffer limita o estrago.
            tracing::warn!("falha ao agendar janela de agregação: {e}");
            if let Some(payload) = payload_enfileirado {
                let desfez: Result<i64, _> = redis::cmd("LREM")
                    .arg(&chave)
                    .arg(-1)
                    .arg(&payload)
                    .query_async(&mut conn)
                    .await;
                if let Err(e) = desfez {
                    tracing::warn!(
                        "falha ao desfazer o enfileiramento após agendamento falho \
                         (possível resposta duplicada nesta janela): {e}"
                    );
                }
            }
            Enfileiramento::Indisponivel
        }
    }
}

/// Script Lua que lê e apaga o buffer numa operação só.
///
/// Sem atomicidade aqui, uma mensagem que chegasse entre o `LRANGE` e o `DEL`
/// seria lida por ninguém e apagada — a fala do cliente sumiria da resposta sem
/// deixar rastro. Também apaga o `:timer`, liberando a próxima janela.
const LUA_DRENAR: &str = r#"
local itens = redis.call('LRANGE', KEYS[1], 0, -1)
redis.call('DEL', KEYS[1])
redis.call('DEL', KEYS[2])
return itens
"#;

/// Drena a janela do contato: devolve tudo que foi acumulado e libera a chave do
/// timer para a próxima rajada.
///
/// Devolve lista vazia quando não há Redis ou o drain falha — o chamador trata
/// isso como "nada a agregar" e segue com o que tiver em mãos.
pub(crate) async fn drenar(
    conn: Option<&ConnectionManager>,
    tenant: Uuid,
    sender: &str,
) -> Vec<MensagemBufferizada> {
    let Some(conn) = conn else {
        return Vec::new();
    };
    let mut conn = conn.clone();

    let brutos: Vec<String> = match redis::Script::new(LUA_DRENAR)
        .key(chave_buffer(tenant, sender))
        .key(chave_timer(tenant, sender))
        .invoke_async(&mut conn)
        .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!("falha ao drenar buffer de agregação: {e}");
            return Vec::new();
        }
    };

    brutos
        .iter()
        .filter_map(|b| serde_json::from_str::<MensagemBufferizada>(b).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(id: &str, texto: &str) -> MensagemBufferizada {
        MensagemBufferizada {
            message_id: id.to_string(),
            texto: texto.to_string(),
        }
    }

    /// O comportamento central da fase: a rajada vira UMA pergunta, na ordem em
    /// que o cliente escreveu.
    #[test]
    fn compila_a_rajada_na_ordem_de_chegada() {
        let rajada = vec![
            msg("1", "oi"),
            msg("2", "quero saber o preço"),
            msg("3", "do produto X"),
        ];
        assert_eq!(compilar(&rajada), "oi\nquero saber o preço\ndo produto X");
    }

    /// Mensagem única precisa sair idêntica ao que saía antes do buffer — é a
    /// regressão que protege o caso mais comum de todos.
    #[test]
    fn mensagem_unica_nao_ganha_separador() {
        assert_eq!(compilar(&[msg("1", "bom dia")]), "bom dia");
    }

    /// Mídia sem legenda entra no buffer com texto vazio (o pipeline de mídia
    /// cuida dela à parte); ela não pode virar linha em branco na pergunta.
    #[test]
    fn entrada_vazia_nao_vira_linha_em_branco() {
        let rajada = vec![msg("1", "oi"), msg("2", "   "), msg("3", "tudo bem?")];
        assert_eq!(compilar(&rajada), "oi\ntudo bem?");
        assert_eq!(compilar(&[]), "");
    }

    #[test]
    fn ttl_do_buffer_tem_piso_e_teto() {
        // Janela curta não pode gerar EXPIRE 0 (que em alguns caminhos significa
        // "sem expiração" — PII imortal no Redis).
        assert_eq!(ttl_seguranca(Duration::from_millis(50)), 1);
        // 5 s (default) × 10 = 50 s.
        assert_eq!(ttl_seguranca(Duration::from_secs(5)), 50);
        // Janela absurda é limitada ao teto herdado da v1.
        assert_eq!(ttl_seguranca(Duration::from_secs(600)), TTL_MAXIMO_SEGUNDOS);
    }

    /// Sem Redis o buffer não pode fingir que funcionou: o chamador precisa saber
    /// que deve responder à mensagem sozinha.
    #[tokio::test]
    async fn sem_redis_declara_indisponivel_em_vez_de_engolir() {
        let r = enfileirar(
            None,
            Uuid::new_v4(),
            "5511999998888",
            &msg("1", "oi"),
            Duration::from_secs(5),
        )
        .await;
        assert_eq!(r, Enfileiramento::Indisponivel);
        assert!(drenar(None, Uuid::new_v4(), "5511999998888")
            .await
            .is_empty());
    }

    #[test]
    fn janela_ignora_valor_invalido_e_zero() {
        // Zero desligaria a agregação em silêncio: cai no default.
        std::env::set_var("SMARTCORE_BUFFER_JANELA_MS", "0");
        assert_eq!(janela(), Duration::from_millis(JANELA_PADRAO_MS));
        std::env::set_var("SMARTCORE_BUFFER_JANELA_MS", "nao-e-numero");
        assert_eq!(janela(), Duration::from_millis(JANELA_PADRAO_MS));
        std::env::set_var("SMARTCORE_BUFFER_JANELA_MS", "1200");
        assert_eq!(janela(), Duration::from_millis(1200));
        std::env::remove_var("SMARTCORE_BUFFER_JANELA_MS");
    }
}
