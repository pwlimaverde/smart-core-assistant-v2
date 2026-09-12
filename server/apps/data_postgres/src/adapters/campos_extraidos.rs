//! C1 — validação do que a IA diz ter extraído.
//!
//! Está separado do adaptador de atendimento porque é uma regra, não um acesso
//! a dados: aqui não se toca no banco. O que mora neste arquivo é a resposta a
//! uma pergunta só — *este valor pode entrar na ficha do cliente?* — e ela
//! precisa ser lida inteira, num lugar, para ser confiável.
//!
//! O piso de confiança e as guardas existem porque o LLM não tem nenhuma:
//! ele devolve um slug que talvez não exista, num tipo que talvez não bata,
//! com uma confiança que ele mesmo estimou.

use serde_json::Value;

/// Confiança mínima para um valor da IA entrar na ficha.
///
/// Constante por ora. O **D1** (regras do bot) entrega o limiar configurável
/// por tenant, e é ele que deve valer quando chegar — um número por tenant
/// para "quando confio na IA"; dois seriam duas verdades sobre a mesma coisa.
pub const PISO_CONFIANCA_PADRAO: f64 = 0.8;

/// Por que um valor extraído não foi gravado.
///
/// Enumerado, e não um booleano, porque a diferença entre os motivos é o que
/// permite calibrar: "a IA não preenche" e "a IA preenche errado" pedem ações
/// opostas, e um contador único não as distingue.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Descarte {
    SlugDesconhecido,
    ExtracaoDesligada,
    TipoInvalido,
    AbaixoDoPiso,
}

/// Converte o `valor_json` do LLM na forma tipada do campo.
///
/// `Err(motivo)` quando o valor não serve. Nada é "consertado" no caminho: um
/// valor que precisa de conserto é um valor que a IA não entendeu, e gravá-lo
/// remendado põe na ficha do cliente algo que ninguém disse.
pub fn valor_para_o_tipo(valor_json: &str, tipo: &str, opcoes: &Value) -> Result<Value, Descarte> {
    let bruto = valor_json.trim();
    if bruto.is_empty() {
        return Err(Descarte::TipoInvalido);
    }

    // O LLM manda o valor serializado; se não for JSON válido, trata-se como
    // string crua — é o erro mais comum e o mais inofensivo de acomodar.
    let v: Value = serde_json::from_str(bruto).unwrap_or_else(|_| Value::String(bruto.to_string()));

    match tipo {
        "texto" => match &v {
            Value::String(s) if !s.trim().is_empty() => Ok(Value::String(s.trim().to_string())),
            // Número ou booleano num campo de texto é aceitável — o que a
            // pessoa disse continua sendo o que ela disse.
            Value::Number(_) | Value::Bool(_) => Ok(Value::String(v.to_string())),
            _ => Err(Descarte::TipoInvalido),
        },

        "numero" => match &v {
            Value::Number(_) => Ok(v),
            // "1500" e "1.500,00" chegam como texto o tempo todo. Aceita o
            // primeiro; o segundo é ambíguo (separador de milhar ou decimal?)
            // e adivinhar erraria por um fator de mil.
            Value::String(s) => s
                .trim()
                .parse::<f64>()
                .ok()
                .and_then(serde_json::Number::from_f64)
                .map(Value::Number)
                .ok_or(Descarte::TipoInvalido),
            _ => Err(Descarte::TipoInvalido),
        },

        "data" => match &v {
            // Só AAAA-MM-DD, que é o que o prompt pede. Aceitar outros
            // formatos aqui significaria escolher entre 03/04 ser 3 de abril
            // ou 4 de março — e a escolha errada vira um compromisso na data
            // errada, sem ninguém perceber.
            Value::String(s) => {
                let s = s.trim();
                chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                    .map(|_| Value::String(s.to_string()))
                    .map_err(|_| Descarte::TipoInvalido)
            }
            _ => Err(Descarte::TipoInvalido),
        },

        "booleano" => match &v {
            Value::Bool(_) => Ok(v),
            Value::String(s) => match s.trim().to_lowercase().as_str() {
                "true" | "sim" => Ok(Value::Bool(true)),
                "false" | "nao" | "não" => Ok(Value::Bool(false)),
                _ => Err(Descarte::TipoInvalido),
            },
            _ => Err(Descarte::TipoInvalido),
        },

        "lista" => {
            // O id tem de existir no catálogo. Um valor fora de `opcoes` é
            // exatamente o caso que o campo de lista existe para impedir —
            // aceitar viraria uma lista com um item que ninguém cadastrou.
            let id = match &v {
                Value::String(s) => s.trim().to_string(),
                Value::Number(n) => n.to_string(),
                _ => return Err(Descarte::TipoInvalido),
            };
            let existe = opcoes.as_array().is_some_and(|arr| {
                arr.iter().any(|o| {
                    o.get("id").and_then(Value::as_str) == Some(id.as_str())
                        || o.as_str() == Some(id.as_str())
                })
            });
            if existe {
                Ok(Value::String(id))
            } else {
                Err(Descarte::TipoInvalido)
            }
        }

        // Tipo que não conhecemos: guarda como texto em vez de descartar. O
        // catálogo pode ganhar tipos novos antes desta função, e perder o dado
        // por isso seria pior que guardá-lo cru.
        _ => Ok(Value::String(bruto.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn texto_aceita_string_e_apara() {
        assert_eq!(
            valor_para_o_tipo("\"  15x21 cm \"", "texto", &json!([])),
            Ok(json!("15x21 cm"))
        );
    }

    #[test]
    fn texto_vazio_nao_entra() {
        // Um campo "preenchido" com nada é pior que vazio: some da lista de
        // pendentes e a IA nunca mais pergunta.
        assert_eq!(
            valor_para_o_tipo("\"   \"", "texto", &json!([])),
            Err(Descarte::TipoInvalido)
        );
    }

    #[test]
    fn numero_aceita_string_numerica() {
        assert_eq!(
            valor_para_o_tipo("\"1500\"", "numero", &json!([])),
            Ok(json!(1500.0))
        );
    }

    /// "1.500,00" é ambíguo e adivinhar erra por um fator de mil.
    #[test]
    fn numero_com_separador_de_milhar_e_descartado() {
        assert_eq!(
            valor_para_o_tipo("\"1.500,00\"", "numero", &json!([])),
            Err(Descarte::TipoInvalido)
        );
    }

    #[test]
    fn data_so_no_formato_pedido() {
        assert_eq!(
            valor_para_o_tipo("\"2026-09-15\"", "data", &json!([])),
            Ok(json!("2026-09-15"))
        );
        // 03/04 seria 3 de abril ou 4 de março? Errar aqui marca compromisso
        // no dia errado sem ninguém perceber.
        assert_eq!(
            valor_para_o_tipo("\"03/04/2026\"", "data", &json!([])),
            Err(Descarte::TipoInvalido)
        );
    }

    #[test]
    fn lista_exige_opcao_do_catalogo() {
        let opcoes = json!([{"id": "cartao", "rotulo": "Cartão"}]);
        assert_eq!(
            valor_para_o_tipo("\"cartao\"", "lista", &opcoes),
            Ok(json!("cartao"))
        );
        assert_eq!(
            valor_para_o_tipo("\"pix\"", "lista", &opcoes),
            Err(Descarte::TipoInvalido),
            "opção inventada pelo modelo não pode virar item da lista"
        );
    }

    #[test]
    fn booleano_entende_sim_e_nao() {
        assert_eq!(
            valor_para_o_tipo("\"sim\"", "booleano", &json!([])),
            Ok(json!(true))
        );
        assert_eq!(
            valor_para_o_tipo("\"não\"", "booleano", &json!([])),
            Ok(json!(false))
        );
        assert_eq!(
            valor_para_o_tipo("\"talvez\"", "booleano", &json!([])),
            Err(Descarte::TipoInvalido)
        );
    }

    /// Tipo novo no catálogo não pode fazer o dado se perder.
    #[test]
    fn tipo_desconhecido_guarda_como_texto() {
        assert_eq!(
            valor_para_o_tipo("\"algo\"", "tipo-que-ainda-nao-existe", &json!([])),
            Ok(json!("algo"))
        );
    }
}
