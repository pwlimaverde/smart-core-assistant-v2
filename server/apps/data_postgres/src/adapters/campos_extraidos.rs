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

/// Confiança mínima para um valor da IA entrar na ficha, quando a config do
/// tenant não pôde ser lida.
///
/// Desde o B4 o piso de verdade é a `confianca_minima_automatica` do tenant —
/// um número por tenant para "quando confio na IA"; dois seriam duas verdades
/// sobre a mesma coisa. Esta constante é só a rede de segurança.
pub const PISO_CONFIANCA_PADRAO: f64 = 0.8;

/// Converte o `valor_json` do LLM na forma tipada do campo.
///
/// `None` quando o valor não serve para o tipo. Nada é "consertado" no
/// caminho: um valor que precisa de conserto é um valor que a IA não
/// entendeu, e gravá-lo remendado põe na ficha do cliente algo que ninguém
/// disse.
///
/// Esta função responde a **uma** pergunta — o valor casa com o tipo? Os
/// outros motivos de descarte (slug fora do catálogo, extração desligada,
/// confiança abaixo do piso) são do chamador, que os conta separadamente:
/// a diferença entre eles é o que permite calibrar o piso depois.
pub fn valor_para_o_tipo(valor_json: &str, tipo: &str, opcoes: &Value) -> Option<Value> {
    let bruto = valor_json.trim();
    if bruto.is_empty() {
        return None;
    }

    // O LLM manda o valor serializado; se não for JSON válido, trata-se como
    // string crua — é o erro mais comum e o mais inofensivo de acomodar.
    let v: Value = serde_json::from_str(bruto).unwrap_or_else(|_| Value::String(bruto.to_string()));

    match tipo {
        "texto" => match &v {
            Value::String(s) if !s.trim().is_empty() => Some(Value::String(s.trim().to_string())),
            // Número ou booleano num campo de texto é aceitável — o que a
            // pessoa disse continua sendo o que ela disse.
            Value::Number(_) | Value::Bool(_) => Some(Value::String(v.to_string())),
            _ => None,
        },

        "numero" => match &v {
            Value::Number(_) => Some(v),
            // "1500" e "1.500,00" chegam como texto o tempo todo. Aceita o
            // primeiro; o segundo é ambíguo (separador de milhar ou decimal?)
            // e adivinhar erraria por um fator de mil.
            Value::String(s) => s
                .trim()
                .parse::<f64>()
                .ok()
                .and_then(serde_json::Number::from_f64)
                .map(Value::Number),
            _ => None,
        },

        "data" => match &v {
            // Só AAAA-MM-DD, que é o que o prompt pede. Aceitar outros
            // formatos aqui significaria escolher entre 03/04 ser 3 de abril
            // ou 4 de março — e a escolha errada vira um compromisso na data
            // errada, sem ninguém perceber.
            Value::String(s) => {
                let s = s.trim();
                chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                    .ok()
                    .map(|_| Value::String(s.to_string()))
            }
            _ => None,
        },

        "cpf" => match &v {
            Value::String(s) => {
                let digitos: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
                (digitos.len() == 11 && crate::cpf_valido(&digitos))
                    .then_some(Value::String(digitos))
            }
            _ => None,
        },
        "cnpj" => match &v {
            Value::String(s) => {
                let digitos: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
                (digitos.len() == 14 && crate::cnpj_valido(&digitos))
                    .then_some(Value::String(digitos))
            }
            _ => None,
        },
        "booleano" => match &v {
            Value::Bool(_) => Some(v),
            Value::String(s) => match s.trim().to_lowercase().as_str() {
                "true" | "sim" => Some(Value::Bool(true)),
                "false" | "nao" | "não" => Some(Value::Bool(false)),
                _ => None,
            },
            _ => None,
        },

        "lista" => {
            // O id tem de existir no catálogo. Um valor fora de `opcoes` é
            // exatamente o caso que o campo de lista existe para impedir —
            // aceitar viraria uma lista com um item que ninguém cadastrou.
            let id = match &v {
                Value::String(s) => s.trim().to_string(),
                Value::Number(n) => n.to_string(),
                _ => return None,
            };
            let existe = opcoes.as_array().is_some_and(|arr| {
                arr.iter().any(|o| {
                    o.get("id").and_then(Value::as_str) == Some(id.as_str())
                        || o.as_str() == Some(id.as_str())
                })
            });
            if existe {
                Some(Value::String(id))
            } else {
                None
            }
        }

        // Tipo que não conhecemos: guarda como texto em vez de descartar. O
        // catálogo pode ganhar tipos novos antes desta função, e perder o dado
        // por isso seria pior que guardá-lo cru.
        //
        // Guarda o valor **desserializado**, não `bruto`: o LLM manda
        // `"algo"` com as aspas do JSON, e gravá-las literalmente poria na
        // ficha do cliente um texto com aspas que ninguém escreveu.
        _ => match &v {
            Value::String(s) => Some(Value::String(s.trim().to_string())),
            _ => Some(Value::String(bruto.to_string())),
        },
    }
}

/// Literal que a frase de origem tem de conter para o campo ser gravado (V3).
///
/// Só o tipo `texto` exige literal. Usa o mesmo parse de [`valor_para_o_tipo`]:
/// valor que não é JSON válido (ex.: `0123` sem aspas) vale como texto cru e
/// continua exigindo o literal — sem isso a trava sumia justamente aí.
pub fn literal_exigido(valor_json: &str, tipo: &str) -> Option<String> {
    match tipo {
        "texto" => valor_para_o_tipo(valor_json, "texto", &Value::Null)
            .and_then(|v| v.as_str().map(str::to_string)),
        _ => None,
    }
}

/// `true` quando os dígitos de `valor` aparecem na `frase` como número
/// inteiro, não como pedaço de um número maior.
///
/// Duas formas valem:
///
/// 1. Um token sem espaço — dígitos e a máscara de CPF/CNPJ (`.`, `-`, `/`) —
///    com exatamente os dígitos do valor. Assim `123.456.789-09` casa com
///    `12345678909`, mas o CNPJ `11.222.333/0001-81` não sustenta o "CPF"
///    `11222333000`.
/// 2. Os blocos da máscara oficial separados por **um** espaço (ou por um
///    caractere de máscara): `123 456 789 09` para CPF (3-3-3-2) e
///    `11 222 333 0001 81` para CNPJ (2-3-3-4-2). É como muita gente digita
///    no celular. Fora desse desenho exato o espaço separa números
///    diferentes: `12345 678909` são dois números, e `55 123 456 789 09` é
///    uma sequência maior — nenhum dos dois sustenta um documento.
pub fn digitos_delimitados(frase: &str, valor: &str) -> bool {
    let digitos = |s: &str| -> String { s.chars().filter(char::is_ascii_digit).collect() };
    let alvo = digitos(valor);
    if alvo.is_empty() {
        return false;
    }
    if frase
        .split(|c: char| !(c.is_ascii_digit() || matches!(c, '.' | '-' | '/')))
        .any(|token| digitos(token) == alvo)
    {
        return true;
    }
    blocos_da_mascara(frase, &alvo)
}

/// Forma 2 de [`digitos_delimitados`]: os blocos da máscara oficial, cada um
/// separado do seguinte por exatamente um caractere (espaço ou máscara).
fn blocos_da_mascara(frase: &str, alvo: &str) -> bool {
    let desenho: &[usize] = match alvo.len() {
        11 => &[3, 3, 3, 2],
        14 => &[2, 3, 3, 4, 2],
        _ => return false,
    };
    // Cada grupo de dígitos, com o que há entre ele e o grupo anterior.
    let mut grupos: Vec<(String, String)> = Vec::new();
    let mut separador = String::new();
    let mut atual = String::new();
    for c in frase.chars() {
        if c.is_ascii_digit() {
            atual.push(c);
        } else {
            if !atual.is_empty() {
                grupos.push((std::mem::take(&mut separador), std::mem::take(&mut atual)));
            }
            separador.push(c);
        }
    }
    if !atual.is_empty() {
        grupos.push((separador, atual));
    }
    let liga = |sep: &str| matches!(sep, " " | "." | "-" | "/");
    // Cadeias máximas de grupos ligados: a cadeia inteira tem de ser o
    // documento, senão ele seria pedaço de uma sequência maior.
    let mut inicio = 0;
    while inicio < grupos.len() {
        let mut fim = inicio + 1;
        while fim < grupos.len() && liga(&grupos[fim].0) {
            fim += 1;
        }
        let cadeia = &grupos[inicio..fim];
        if cadeia.len() == desenho.len()
            && cadeia.iter().zip(desenho).all(|((_, g), n)| g.len() == *n)
            && cadeia.iter().map(|(_, g)| g.as_str()).collect::<String>() == alvo
        {
            return true;
        }
        inicio = fim;
    }
    false
}

/// Minúsculas e sem acento: a comparação de evidência (dia da semana, mês,
/// rótulo de lista) não pode depender de o cliente ter acentuado.
fn sem_acento(texto: &str) -> String {
    texto
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'á' | 'à' | 'â' | 'ã' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            outro => outro,
        })
        .collect()
}

/// Palavras (letras e dígitos) do texto, minúsculas e sem acento.
fn palavras(texto: &str) -> Vec<String> {
    sem_acento(texto)
        .split(|c: char| !c.is_alphanumeric())
        .filter(|p| !p.is_empty())
        .map(str::to_string)
        .collect()
}

const MESES: [&str; 12] = [
    "janeiro",
    "fevereiro",
    "marco",
    "abril",
    "maio",
    "junho",
    "julho",
    "agosto",
    "setembro",
    "outubro",
    "novembro",
    "dezembro",
];

fn unidade_por_extenso(palavra: &str) -> Option<u32> {
    Some(match palavra {
        "um" => 1,
        "dois" => 2,
        "tres" => 3,
        "quatro" => 4,
        "cinco" => 5,
        "seis" => 6,
        "sete" => 7,
        "oito" => 8,
        "nove" => 9,
        _ => return None,
    })
}

/// Dia do mês escrito por extenso a partir da posição `i`, e quantas palavras
/// ele ocupa. "um" sozinho fica de fora: é artigo na maioria das frases.
fn dia_por_extenso(p: &[String], i: usize) -> Option<(u32, usize)> {
    let palavra = p.get(i)?.as_str();
    let dezena = match palavra {
        "vinte" => Some(20),
        "trinta" => Some(30),
        _ => None,
    };
    if let Some(dezena) = dezena {
        if p.get(i + 1).map(String::as_str) == Some("e") {
            if let Some(u) = p.get(i + 2).and_then(|s| unidade_por_extenso(s)) {
                return Some((dezena + u, 3));
            }
        }
        return Some((dezena, 1));
    }
    let dia = match palavra {
        "primeiro" => 1,
        "dez" => 10,
        "onze" => 11,
        "doze" => 12,
        "treze" => 13,
        "quatorze" | "catorze" => 14,
        "quinze" => 15,
        "dezesseis" => 16,
        "dezessete" => 17,
        "dezoito" => 18,
        "dezenove" => 19,
        // Só "dia um": fora disso é artigo.
        "um" => return (i > 0 && p[i - 1] == "dia").then_some((1, 1)),
        outra => unidade_por_extenso(outra)?,
    };
    Some((dia, 1))
}

/// V3 — a frase do cliente sustenta a **data** que a IA devolveu?
///
/// A frase estar na mensagem não basta: com "oi" como frase a IA gravaria
/// qualquer data. A frase precisa trazer um sinal do dia, conferido aqui:
///
/// - data escrita com barra (`03/05`, `03/05/2026`, dia antes do mês) ou em
///   ISO: dia e mês (e ano, se escrito) têm de ser os do valor — havendo data
///   assim na frase e nenhuma batendo, recusa;
/// - o número do dia (`dia 3`, `3 de maio`) ou o dia por extenso;
/// - o dia da semana do valor (`sexta`);
/// - `hoje`, `amanhã` e `depois de amanhã`, com um dia de folga porque o
///   servidor compara em UTC e o cliente escreveu no fuso dele.
///
/// Mês citado por nome tem de ser o mês do valor. Frase sem nenhum desses
/// sinais ("no fim do mês", "semana que vem") não sustenta data: o campo
/// segue pendente e a IA pergunta o dia.
pub fn frase_sustenta_data(frase: &str, data: chrono::NaiveDate, hoje: chrono::NaiveDate) -> bool {
    use chrono::Datelike;

    let p = palavras(frase);
    let meses_citados: Vec<u32> = p
        .iter()
        .filter_map(|w| MESES.iter().position(|m| m == w))
        .map(|i| i as u32 + 1)
        .collect();
    if !meses_citados.is_empty() && !meses_citados.contains(&data.month()) {
        return false;
    }

    // Datas numéricas: `d/m[/a]` e `aaaa-mm-dd`.
    let numero = |s: &str| s.parse::<u32>().ok();
    let mut houve_data_numerica = false;
    for trecho in frase.split(|c: char| !(c.is_ascii_digit() || matches!(c, '/' | '-'))) {
        let barra: Vec<&str> = trecho.split('/').collect();
        let hifen: Vec<&str> = trecho.split('-').collect();
        let candidata: Option<(u32, u32, Option<u32>)> =
            if (2..=3).contains(&barra.len()) && !trecho.contains('-') {
                numero(barra[0])
                    .zip(numero(barra[1]))
                    .map(|(d, m)| (d, m, barra.get(2).and_then(|a| numero(a))))
            } else if hifen.len() == 3 && hifen[0].len() == 4 && !trecho.contains('/') {
                match (numero(hifen[0]), numero(hifen[1]), numero(hifen[2])) {
                    (Some(a), Some(m), Some(d)) => Some((d, m, Some(a))),
                    _ => None,
                }
            } else {
                None
            };
        let Some((d, m, ano)) = candidata else {
            continue;
        };
        if !(1..=31).contains(&d) || !(1..=12).contains(&m) {
            continue;
        }
        houve_data_numerica = true;
        let ano_ok = ano.is_none_or(|a| {
            let cheio = data.year().unsigned_abs();
            a == cheio || a == cheio % 100
        });
        if d == data.day() && m == data.month() && ano_ok {
            return true;
        }
    }
    if houve_data_numerica {
        return false;
    }

    // O número do dia, em algarismos.
    if frase
        .split(|c: char| !c.is_ascii_digit())
        .filter_map(numero)
        .any(|n| n == data.day())
    {
        return true;
    }

    // O dia por extenso.
    let mut i = 0;
    while i < p.len() {
        match dia_por_extenso(&p, i) {
            Some((dia, _)) if dia == data.day() => return true,
            Some((_, usadas)) => i += usadas,
            None => i += 1,
        }
    }

    // O dia da semana.
    let dia_semana = match data.weekday() {
        chrono::Weekday::Mon => "segunda",
        chrono::Weekday::Tue => "terca",
        chrono::Weekday::Wed => "quarta",
        chrono::Weekday::Thu => "quinta",
        chrono::Weekday::Fri => "sexta",
        chrono::Weekday::Sat => "sabado",
        chrono::Weekday::Sun => "domingo",
    };
    if p.iter().any(|w| w == dia_semana) {
        return true;
    }

    // Datas relativas, com um dia de folga para o fuso.
    let distancia = (data - hoje).num_days();
    p.iter().enumerate().any(|(i, w)| {
        let faixa = match w.as_str() {
            "hoje" => -1..=1,
            "amanha" if i >= 2 && p[i - 2] == "depois" && p[i - 1] == "de" => 1..=3,
            "amanha" => 0..=2,
            _ => return false,
        };
        faixa.contains(&distancia)
    })
}

/// V3 — a frase do cliente sustenta a **opção de lista** que a IA devolveu?
///
/// O id gravado é interno ("couche_fosco"); o cliente escreve o rótulo, ou
/// parte dele. Vale quando a frase traz, como palavra inteira e sem olhar
/// acento nem caixa:
///
/// - o rótulo ou o id inteiro da opção; ou
/// - uma palavra do rótulo/id que nenhuma outra opção tem ("fosco" entre
///   "Couchê fosco" e "Couchê brilho"). Palavra comum a outra opção
///   ("couchê") não distingue nada e não vale; palavra de uma ou duas letras
///   só vale se for número ("Plano 2").
pub fn frase_sustenta_lista(frase: &str, id: &str, opcoes: &Value) -> bool {
    let p = palavras(frase);
    let Some(lista) = opcoes.as_array() else {
        return false;
    };
    let id_e_rotulo = |o: &Value| -> (String, String) {
        match o {
            Value::String(s) => (s.clone(), s.clone()),
            _ => {
                let campo = |chave: &str| o.get(chave).and_then(Value::as_str).unwrap_or_default();
                (campo("id").to_string(), campo("rotulo").to_string())
            }
        }
    };
    let mut da_escolhida: Vec<Vec<String>> = Vec::new();
    let mut das_outras: Vec<String> = Vec::new();
    for o in lista {
        let (o_id, o_rotulo) = id_e_rotulo(o);
        if o_id == id {
            da_escolhida.push(palavras(&o_id));
            da_escolhida.push(palavras(&o_rotulo));
        } else {
            das_outras.extend(palavras(&o_id));
            das_outras.extend(palavras(&o_rotulo));
        }
    }
    let contem = |seq: &[String]| !seq.is_empty() && p.windows(seq.len()).any(|j| j == seq);
    if da_escolhida.iter().any(|seq| contem(seq)) {
        return true;
    }
    da_escolhida.iter().flatten().any(|w| {
        let serve = w.chars().count() >= 3 || w.chars().all(|c| c.is_ascii_digit());
        serve && !das_outras.contains(w) && p.contains(w)
    })
}

/// V3 — a frase do cliente sustenta o **número** que a IA devolveu?
///
/// Só confere quando a frase tem algarismos: aí um deles tem de ser o valor
/// ("1.500", "1500", "1.500,50", "1 500"), ou o valor dividido por mil ou
/// por um milhão quando a frase diz "mil"/"k" ou "milhão". Número escrito
/// por extenso ("quinhentos") não é verificável aqui e segue valendo a frase
/// literal, como antes.
pub fn frase_sustenta_numero(frase: &str, valor: f64) -> bool {
    // Trechos numéricos da frase: (início, fim, texto), em bytes.
    let mut trechos: Vec<(usize, usize, &str)> = Vec::new();
    let mut pos = 0;
    while let Some(d) = frase[pos..].find(|c: char| c.is_ascii_digit()) {
        let ini = pos + d;
        let fim = frase[ini..]
            .find(|c: char| !(c.is_ascii_digit() || matches!(c, '.' | ',')))
            .map_or(frase.len(), |f| ini + f);
        let texto = frase[ini..fim].trim_end_matches(['.', ',']);
        trechos.push((ini, ini + texto.len(), texto));
        pos = fim;
    }
    if trechos.is_empty() {
        return true;
    }

    let so_digitos = |t: &str| t.chars().all(|c| c.is_ascii_digit());
    let mut candidatos: Vec<f64> = Vec::new();
    for (i, (_, _, texto)) in trechos.iter().enumerate() {
        // Brasileiro (ponto de milhar, vírgula decimal) e a leitura crua.
        candidatos.extend(texto.replace('.', "").replace(',', ".").parse::<f64>().ok());
        candidatos.extend(texto.parse::<f64>().ok());
        // Milhar com espaço: "1 500", "2 500 000".
        if so_digitos(texto) && texto.len() <= 3 {
            let mut junto = (*texto).to_string();
            let mut j = i;
            while let Some((ini, _, proximo)) = trechos.get(j + 1) {
                if &frase[trechos[j].1..*ini] != " " || !so_digitos(proximo) || proximo.len() != 3 {
                    break;
                }
                junto.push_str(proximo);
                candidatos.extend(junto.parse::<f64>().ok());
                j += 1;
            }
        }
    }

    let p = palavras(frase);
    let diz_mil = p.iter().any(|w| {
        w == "mil"
            || w.strip_suffix('k')
                .is_some_and(|n| n.chars().all(|c| c.is_ascii_digit()))
    });
    let diz_milhao = p.iter().any(|w| w.starts_with("milh"));
    let igual = |a: f64, b: f64| (a - b).abs() <= 1e-9 * a.abs().max(b.abs()).max(1.0);
    candidatos.iter().any(|c| {
        igual(*c, valor)
            || (diz_mil && igual(*c * 1_000.0, valor))
            || (diz_milhao && igual(*c * 1_000_000.0, valor))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn digitos_delimitados_cpf_com_mascara_casa() {
        assert!(digitos_delimitados(
            "meu cpf é 123.456.789-09, obrigado",
            "12345678909"
        ));
    }

    #[test]
    fn digitos_delimitados_sequencia_maior_nao_casa() {
        assert!(!digitos_delimitados(
            "o cnpj é 11.222.333/0001-81",
            "11222333000"
        ));
        assert!(!digitos_delimitados("tel 5511999998888", "11999998888"));
    }

    #[test]
    fn digitos_delimitados_cnpj_com_mascara_casa() {
        assert!(digitos_delimitados(
            "CNPJ:11.222.333/0001-81.",
            "11222333000181"
        ));
    }

    #[test]
    fn digitos_delimitados_aceita_blocos_da_mascara_com_espaco() {
        // CPF 3-3-3-2 e CNPJ 2-3-3-4-2, um espaço entre os blocos.
        assert!(digitos_delimitados(
            "meu cpf: 123 456 789 09, pode anotar",
            "12345678909"
        ));
        assert!(digitos_delimitados("123.456.789 09", "12345678909"));
        assert!(digitos_delimitados(
            "cnpj 11 222 333 0001 81",
            "11222333000181"
        ));
    }

    #[test]
    fn digitos_delimitados_espaco_fora_do_desenho_nao_casa() {
        // Dois números que, colados, dariam os dígitos do documento.
        assert!(!digitos_delimitados("pedido 12345 678909", "12345678909"));
        assert!(!digitos_delimitados("1 2 3 4 5 6 7 8 9 0 9", "12345678909"));
        // Dois espaços ou quebra de linha não ligam blocos.
        assert!(!digitos_delimitados("123  456 789 09", "12345678909"));
        assert!(!digitos_delimitados("123 456\n789 09", "12345678909"));
        // Pedaço de uma sequência maior.
        assert!(!digitos_delimitados("55 123 456 789 09", "12345678909"));
        assert!(!digitos_delimitados("123 456 789 09 77", "12345678909"));
    }

    fn dia(a: i32, m: u32, d: u32) -> chrono::NaiveDate {
        chrono::NaiveDate::from_ymd_opt(a, m, d).unwrap_or_default()
    }

    #[test]
    fn data_exige_o_dia_na_frase() {
        let hoje = dia(2026, 4, 20);
        let valor = dia(2026, 5, 3);
        assert!(frase_sustenta_data("dia 3 de maio", valor, hoje));
        assert!(frase_sustenta_data("pode ser no dia 03", valor, hoje));
        assert!(frase_sustenta_data("03/05", valor, hoje));
        assert!(frase_sustenta_data("3/5/26", valor, hoje));
        assert!(frase_sustenta_data("2026-05-03", valor, hoje));
        assert!(frase_sustenta_data("dia três", valor, hoje));
        // Frase que está na mensagem mas não fala do dia.
        assert!(!frase_sustenta_data("oi, tudo bem?", valor, hoje));
        assert!(!frase_sustenta_data("no fim do mês", valor, hoje));
        assert!(!frase_sustenta_data("dia 13", valor, hoje));
    }

    #[test]
    fn data_recusa_mes_ou_data_numerica_diferente() {
        let hoje = dia(2026, 4, 20);
        let valor = dia(2026, 5, 3);
        assert!(!frase_sustenta_data("dia 3 de junho", valor, hoje));
        // Dia e mês trocados: 05/03 é 5 de março.
        assert!(!frase_sustenta_data("05/03", valor, hoje));
        assert!(!frase_sustenta_data("03/05/2027", valor, hoje));
        assert!(frase_sustenta_data("dia 3 de MAIO", valor, hoje));
    }

    #[test]
    fn data_aceita_dia_da_semana_e_relativas() {
        let hoje = dia(2026, 4, 20); // segunda-feira
        assert!(frase_sustenta_data("sexta-feira", dia(2026, 4, 24), hoje));
        assert!(frase_sustenta_data("no sábado", dia(2026, 4, 25), hoje));
        assert!(!frase_sustenta_data("sexta", dia(2026, 4, 25), hoje));
        assert!(frase_sustenta_data("amanhã cedo", dia(2026, 4, 21), hoje));
        assert!(frase_sustenta_data("hoje", dia(2026, 4, 20), hoje));
        assert!(frase_sustenta_data(
            "depois de amanhã",
            dia(2026, 4, 22),
            hoje
        ));
        // "amanhã" não sustenta uma data daqui a dez dias.
        assert!(!frase_sustenta_data("amanhã", dia(2026, 4, 30), hoje));
        assert!(!frase_sustenta_data("hoje", dia(2026, 4, 23), hoje));
    }

    #[test]
    fn data_por_extenso_composta_e_artigo() {
        let hoje = dia(2026, 4, 1);
        assert!(frase_sustenta_data(
            "vinte e dois de abril",
            dia(2026, 4, 22),
            hoje
        ));
        // "vinte e dois" não vale como dia 2 nem como dia 20.
        assert!(!frase_sustenta_data(
            "vinte e dois de abril",
            dia(2026, 4, 2),
            hoje
        ));
        // "um" como artigo não é o dia 1; "dia um" e "primeiro" são.
        assert!(!frase_sustenta_data("um dia desses", dia(2026, 4, 1), hoje));
        assert!(frase_sustenta_data("dia um", dia(2026, 5, 1), hoje));
        assert!(frase_sustenta_data(
            "primeiro de maio",
            dia(2026, 5, 1),
            hoje
        ));
    }

    #[test]
    fn lista_exige_rotulo_id_ou_palavra_propria_da_opcao() {
        let opcoes = json!([
            {"id": "couche_fosco", "rotulo": "Couchê fosco"},
            {"id": "couche_brilho", "rotulo": "Couchê brilho"},
            {"id": "offset", "rotulo": "Offset"},
        ]);
        assert!(frase_sustenta_lista(
            "quero no couchê fosco",
            "couche_fosco",
            &opcoes
        ));
        assert!(frase_sustenta_lista(
            "pode ser FOSCO",
            "couche_fosco",
            &opcoes
        ));
        assert!(frase_sustenta_lista("papel offset", "offset", &opcoes));
        // "couchê" é comum a duas opções: não distingue.
        assert!(!frase_sustenta_lista(
            "quero couchê",
            "couche_fosco",
            &opcoes
        ));
        // A frase fala de outra opção.
        assert!(!frase_sustenta_lista(
            "couchê brilho",
            "couche_fosco",
            &opcoes
        ));
        assert!(!frase_sustenta_lista("oi, tudo bem?", "offset", &opcoes));
        // Palavra inteira: "offsetado" não é "offset".
        assert!(!frase_sustenta_lista("offsetado", "offset", &opcoes));
    }

    #[test]
    fn lista_de_textos_simples_e_palavra_curta() {
        let opcoes = json!(["Plano 1", "Plano 2", "Plano de ouro"]);
        assert!(frase_sustenta_lista("quero o plano 2", "Plano 2", &opcoes));
        assert!(frase_sustenta_lista("o 2", "Plano 2", &opcoes));
        assert!(frase_sustenta_lista("o de ouro", "Plano de ouro", &opcoes));
        // "de" tem duas letras e não é número: não sustenta sozinha.
        assert!(!frase_sustenta_lista("de", "Plano de ouro", &opcoes));
        assert!(!frase_sustenta_lista("plano", "Plano 2", &opcoes));
        // Sem opções não há o que conferir.
        assert!(!frase_sustenta_lista("plano 2", "Plano 2", &Value::Null));
    }

    #[test]
    fn numero_com_algarismo_na_frase_tem_de_bater() {
        assert!(frase_sustenta_numero("1.500 reais", 1500.0));
        assert!(frase_sustenta_numero("1500", 1500.0));
        assert!(frase_sustenta_numero("uns 1.500,50", 1500.5));
        assert!(frase_sustenta_numero("1 500 unidades", 1500.0));
        assert!(frase_sustenta_numero("2 500 000", 2_500_000.0));
        assert!(frase_sustenta_numero("2 mil cartões", 2000.0));
        assert!(frase_sustenta_numero("10k", 10_000.0));
        assert!(frase_sustenta_numero("1,5 milhão", 1_500_000.0));
        assert!(frase_sustenta_numero("são 3.", 3.0));
        // A frase diz um número e a IA devolveu outro.
        assert!(!frase_sustenta_numero("1.500 reais", 9999.0));
        assert!(!frase_sustenta_numero("2 caixas", 2000.0));
        assert!(!frase_sustenta_numero("12 345", 345.5));
    }

    #[test]
    fn numero_por_extenso_segue_valendo_a_frase() {
        assert!(frase_sustenta_numero("quinhentos reais", 500.0));
        assert!(frase_sustenta_numero("meia dúzia", 6.0));
    }

    #[test]
    fn digitos_delimitados_valor_sem_digitos_nao_casa() {
        assert!(!digitos_delimitados("qualquer coisa", ""));
    }

    #[test]
    fn literal_exigido_aceita_texto_cru_como_literal() {
        // `0123` não é JSON válido: vira texto cru e o literal continua exigido.
        assert_eq!(literal_exigido("0123", "texto"), Some("0123".to_string()));
        assert_eq!(
            literal_exigido("\" Rua A \"", "texto"),
            Some("Rua A".to_string())
        );
    }

    #[test]
    fn literal_exigido_so_para_texto() {
        assert_eq!(literal_exigido("\"2026-01-02\"", "data"), None);
        assert_eq!(literal_exigido("\"12345678909\"", "cpf"), None);
    }

    #[test]
    fn texto_aceita_string_e_apara() {
        assert_eq!(
            valor_para_o_tipo("\"  15x21 cm \"", "texto", &json!([])),
            Some(json!("15x21 cm"))
        );
    }

    /// Documento extraído pela IA só entra com dígito verificador válido.
    #[test]
    fn cpf_e_cnpj_so_entram_validos() {
        assert_eq!(
            valor_para_o_tipo("\"529.982.247-25\"", "cpf", &json!([])),
            Some(json!("52998224725"))
        );
        assert_eq!(
            valor_para_o_tipo("\"529.982.247-26\"", "cpf", &json!([])),
            None
        );
        assert_eq!(
            valor_para_o_tipo("\"11.222.333/0001-81\"", "cnpj", &json!([])),
            Some(json!("11222333000181"))
        );
        assert_eq!(
            valor_para_o_tipo("\"11.222.333/0001-82\"", "cnpj", &json!([])),
            None
        );
    }

    #[test]
    fn texto_vazio_nao_entra() {
        // Um campo "preenchido" com nada é pior que vazio: some da lista de
        // pendentes e a IA nunca mais pergunta.
        assert_eq!(valor_para_o_tipo("\"   \"", "texto", &json!([])), None);
    }

    #[test]
    fn numero_aceita_string_numerica() {
        assert_eq!(
            valor_para_o_tipo("\"1500\"", "numero", &json!([])),
            Some(json!(1500.0))
        );
    }

    /// "1.500,00" é ambíguo e adivinhar erra por um fator de mil.
    #[test]
    fn numero_com_separador_de_milhar_e_descartado() {
        assert_eq!(
            valor_para_o_tipo("\"1.500,00\"", "numero", &json!([])),
            None
        );
    }

    #[test]
    fn data_so_no_formato_pedido() {
        assert_eq!(
            valor_para_o_tipo("\"2026-09-15\"", "data", &json!([])),
            Some(json!("2026-09-15"))
        );
        // 03/04 seria 3 de abril ou 4 de março? Errar aqui marca compromisso
        // no dia errado sem ninguém perceber.
        assert_eq!(
            valor_para_o_tipo("\"03/04/2026\"", "data", &json!([])),
            None
        );
    }

    #[test]
    fn lista_exige_opcao_do_catalogo() {
        let opcoes = json!([{"id": "cartao", "rotulo": "Cartão"}]);
        assert_eq!(
            valor_para_o_tipo("\"cartao\"", "lista", &opcoes),
            Some(json!("cartao"))
        );
        assert_eq!(
            valor_para_o_tipo("\"pix\"", "lista", &opcoes),
            None,
            "opção inventada pelo modelo não pode virar item da lista"
        );
    }

    #[test]
    fn booleano_entende_sim_e_nao() {
        assert_eq!(
            valor_para_o_tipo("\"sim\"", "booleano", &json!([])),
            Some(json!(true))
        );
        assert_eq!(
            valor_para_o_tipo("\"não\"", "booleano", &json!([])),
            Some(json!(false))
        );
        assert_eq!(
            valor_para_o_tipo("\"talvez\"", "booleano", &json!([])),
            None
        );
    }

    /// Tipo novo no catálogo não pode fazer o dado se perder.
    #[test]
    fn tipo_desconhecido_guarda_como_texto() {
        assert_eq!(
            valor_para_o_tipo("\"algo\"", "tipo-que-ainda-nao-existe", &json!([])),
            Some(json!("algo"))
        );
    }
}
