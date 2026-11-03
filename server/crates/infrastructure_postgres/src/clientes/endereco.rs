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
    fn comparacao_ignora_caixa_e_espacos() {
        assert!(
            valor_de_endereco("cidade", "belo   horizonte", "Moro em Belo Horizonte").is_some()
        );
    }
}
