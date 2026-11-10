//! V3 — endereço do cliente extraído da conversa pela IA.
//!
//! A IA devolve o valor como o cliente escreveu. Antes de gravar, ele precisa
//! aparecer inteiro, com fronteira de palavra, no texto da mensagem que o
//! originou (D4, regra 5). A extração pode errar; o texto literal não erra.

const UFS: [&str; 27] = [
    "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG", "PA", "PB", "PR",
    "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO",
];

pub fn coluna_do_slug(slug: &str) -> Option<&'static str> {
    match slug {
        "cliente.logradouro" => Some("logradouro"),
        "cliente.numero" => Some("numero"),
        "cliente.complemento" => Some("complemento"),
        "cliente.bairro" => Some("bairro"),
        "cliente.cidade" => Some("cidade"),
        "cliente.uf" => Some("uf"),
        _ => None,
    }
}

fn limite_de_caracteres(coluna: &str) -> usize {
    match coluna {
        "numero" => 10,
        "uf" => 2,
        _ => 120,
    }
}

fn normalizar(texto: &str) -> String {
    texto
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn aparece_inteiro(texto: &str, valor: &str) -> bool {
    let texto = normalizar(texto);
    let valor = normalizar(valor);
    if valor.is_empty() {
        return false;
    }
    let mut inicio = 0;
    while let Some(pos) = texto[inicio..].find(&valor) {
        let ini = inicio + pos;
        let fim = ini + valor.len();
        let antes_ok = texto[..ini]
            .chars()
            .next_back()
            .is_none_or(|c| !c.is_alphanumeric());
        let depois_ok = texto[fim..]
            .chars()
            .next()
            .is_none_or(|c| !c.is_alphanumeric());
        if antes_ok && depois_ok {
            return true;
        }
        inicio = ini + valor.chars().next().map_or(1, char::len_utf8);
    }
    false
}

/// V3 — a frase que a IA diz ter copiado precisa estar, inteira, na mensagem
/// do cliente. Se o valor for texto, ele também precisa aparecer na frase.
/// Valor numérico ou de data não é comparado letra a letra (a forma pode
/// variar: "1.500" e "1500"); a frase literal já é a prova.
pub fn frase_sustenta_valor(
    texto_da_mensagem: &str,
    frase: &str,
    valor_texto: Option<&str>,
) -> bool {
    let frase = frase.trim();
    if frase.is_empty() || !aparece_inteiro(texto_da_mensagem, frase) {
        return false;
    }
    match valor_texto {
        Some(valor) => aparece_inteiro(frase, valor.trim()),
        None => true,
    }
}

/// V3 — o texto de origem de uma rajada: o `conteudo` de cada mensagem, na
/// ordem de `ids`, unido por `\n`, sem as entradas vazias.
///
/// Espelha o `buffer_mensagens::compilar` do worker, que é como o texto que a
/// IA leu foi montado: sem a mesma junção, a frase que a IA copiou de uma
/// mensagem anterior à última da rajada nunca seria encontrada. `linhas` vem
/// do banco em ordem qualquer; id ausente nela (de outro atendimento, apagado)
/// é ignorado. `None` quando nada sobra.
pub fn montar_texto_de_origem(ids: &[i32], linhas: &[(i32, String)]) -> Option<String> {
    let partes: Vec<&str> = ids
        .iter()
        .filter_map(|id| linhas.iter().find(|(l, _)| l == id))
        .map(|(_, texto)| texto.trim())
        .filter(|t| !t.is_empty())
        .collect();
    (!partes.is_empty()).then(|| partes.join("\n"))
}

/// V3 — a mensagem da rajada que traz a frase inteira: é ela a origem do
/// valor na trilha de auditoria. Percorre na ordem de `ids` e devolve a
/// primeira. `None` quando nenhuma mensagem sozinha tem a frase (frase que
/// atravessa duas mensagens, ou vazia) — o chamador fica com a última.
pub fn mensagem_da_frase(ids: &[i32], linhas: &[(i32, String)], frase: &str) -> Option<i32> {
    let frase = frase.trim();
    if frase.is_empty() {
        return None;
    }
    ids.iter()
        .filter_map(|id| linhas.iter().find(|(l, _)| l == id))
        .find(|(_, texto)| aparece_inteiro(texto, frase))
        .map(|(id, _)| *id)
}

/// Devolve o valor pronto para gravar, ou `None` se ele não passa nas regras.
pub fn valor_de_endereco(coluna: &str, valor: &str, texto_da_mensagem: &str) -> Option<String> {
    let valor = valor.trim();
    if valor.is_empty() || valor.chars().count() > limite_de_caracteres(coluna) {
        return None;
    }
    if coluna == "uf" {
        let sigla = valor.to_uppercase();
        if !UFS.contains(&sigla.as_str()) {
            return None;
        }
        return aparece_inteiro(texto_da_mensagem, valor).then_some(sigla);
    }
    if !aparece_inteiro(texto_da_mensagem, valor) {
        return None;
    }
    Some(valor.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slug_de_endereco_mapeia_so_colunas_conhecidas() {
        assert_eq!(coluna_do_slug("cliente.bairro"), Some("bairro"));
        assert_eq!(coluna_do_slug("cliente.cpf"), None);
        assert_eq!(coluna_do_slug("cep"), None);
    }

    #[test]
    fn valor_aceito_quando_aparece_na_mensagem() {
        assert_eq!(
            valor_de_endereco(
                "logradouro",
                "Rua das Flores",
                "Moro na Rua das Flores, 120"
            ),
            Some("Rua das Flores".to_string())
        );
    }

    #[test]
    fn frase_vazia_nao_sustenta_valor() {
        assert!(!frase_sustenta_valor("moro em Recife", "", Some("Recife")));
        assert!(!frase_sustenta_valor("moro em Recife", "   ", None));
    }

    #[test]
    fn frase_fora_da_mensagem_nao_sustenta_valor() {
        assert!(!frase_sustenta_valor(
            "quero um orçamento",
            "moro em Recife",
            Some("Recife")
        ));
    }

    #[test]
    fn valor_texto_precisa_estar_na_frase() {
        assert!(frase_sustenta_valor(
            "moro em Recife, Pernambuco",
            "moro em Recife",
            Some("Recife")
        ));
        assert!(!frase_sustenta_valor(
            "moro em Recife",
            "moro em Recife",
            Some("Olinda")
        ));
    }

    #[test]
    fn valor_numerico_dispensa_comparacao_letra_a_letra() {
        assert!(frase_sustenta_valor(
            "meu orçamento é 1.500 reais",
            "1.500 reais",
            None
        ));
    }

    #[test]
    fn valor_recusado_quando_nao_esta_no_texto() {
        assert_eq!(
            valor_de_endereco("bairro", "Centro", "moro perto do parque"),
            None
        );
    }

    #[test]
    fn numero_exige_fronteira_de_palavra() {
        assert_eq!(valor_de_endereco("numero", "12", "minha casa é 1234"), None);
        assert_eq!(
            valor_de_endereco("numero", "12", "rua x, 12"),
            Some("12".to_string())
        );
    }

    #[test]
    fn uf_so_aceita_sigla_conhecida_e_normaliza_maiuscula() {
        assert_eq!(
            valor_de_endereco("uf", "sp", "sou de SP"),
            Some("SP".to_string())
        );
        assert_eq!(valor_de_endereco("uf", "XX", "sou de XX"), None);
    }

    #[test]
    fn valor_vazio_ou_longo_demais_e_recusado() {
        assert_eq!(valor_de_endereco("cidade", "   ", "x"), None);
        let longo = "a".repeat(121);
        assert_eq!(valor_de_endereco("cidade", &longo, &longo), None);
    }

    #[test]
    fn texto_de_origem_junta_a_rajada_na_ordem_dos_ids() {
        // O banco devolve em ordem qualquer; vale a ordem da rajada.
        let linhas = vec![
            (12, "do produto X".to_string()),
            (10, "oi".to_string()),
            (11, "meu CPF é 123.456.789-09".to_string()),
        ];
        assert_eq!(
            montar_texto_de_origem(&[10, 11, 12], &linhas).as_deref(),
            Some("oi\nmeu CPF é 123.456.789-09\ndo produto X")
        );
    }

    #[test]
    fn frase_de_mensagem_anterior_da_rajada_e_encontrada() {
        let linhas = vec![
            (1, "meu CPF é 123.456.789-09".to_string()),
            (2, "pode cadastrar?".to_string()),
        ];
        let texto = montar_texto_de_origem(&[1, 2], &linhas).unwrap_or_default();
        assert!(frase_sustenta_valor(
            &texto,
            "meu CPF é 123.456.789-09",
            None
        ));
    }

    #[test]
    fn texto_de_origem_ignora_id_ausente_e_entrada_vazia() {
        let linhas = vec![(1, "oi".to_string()), (2, "   ".to_string())];
        assert_eq!(
            montar_texto_de_origem(&[1, 2, 99], &linhas).as_deref(),
            Some("oi")
        );
        assert_eq!(montar_texto_de_origem(&[99], &linhas), None);
        assert_eq!(montar_texto_de_origem(&[], &linhas), None);
    }

    #[test]
    fn mensagem_da_frase_aponta_a_mensagem_certa_da_rajada() {
        let linhas = vec![
            (12, "pode cadastrar?".to_string()),
            (10, "oi".to_string()),
            (11, "meu CPF é 123.456.789-09".to_string()),
        ];
        let ids = [10, 11, 12];
        assert_eq!(
            mensagem_da_frase(&ids, &linhas, "CPF é 123.456.789-09"),
            Some(11)
        );
        assert_eq!(mensagem_da_frase(&ids, &linhas, " oi "), Some(10));
        // Frase que atravessa duas mensagens não é de nenhuma sozinha.
        assert_eq!(
            mensagem_da_frase(&ids, &linhas, "123.456.789-09 pode cadastrar"),
            None
        );
        assert_eq!(mensagem_da_frase(&ids, &linhas, ""), None);
        // Mensagem fora da rajada não conta, mesmo que venha do banco.
        assert_eq!(mensagem_da_frase(&[10], &linhas, "pode cadastrar?"), None);
    }

    #[test]
    fn mensagem_unica_sai_como_esta() {
        let linhas = vec![(7, "moro em Recife".to_string())];
        assert_eq!(
            montar_texto_de_origem(&[7], &linhas).as_deref(),
            Some("moro em Recife")
        );
    }

    #[test]
    fn comparacao_ignora_caixa_e_espacos() {
        assert!(
            valor_de_endereco("cidade", "belo   horizonte", "Moro em Belo Horizonte").is_some()
        );
    }
}
