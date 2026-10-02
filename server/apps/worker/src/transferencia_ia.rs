//! P4 (plano `correcoes-app-windows-flutter`) — casamento da chave de fluxo
//! devolvida pela IA com os fluxos do tenant e os rótulos da instrumentação da
//! decisão de transferência.
//!
//! O casamento era por igualdade exata de string: qualquer variação de caixa,
//! espaço ou acento na chave `"Setor - descrição"` virava "fluxo desconhecido"
//! só com um `warn` sem contexto. Aqui a comparação é feita sobre a chave
//! normalizada, e o empate (dois fluxos com a mesma chave normalizada) é
//! tratado como desconhecido — transferir para o fluxo errado é pior do que
//! não transferir.

use super::{FluxoItem, FluxosCache};
use uuid::Uuid;

/// Desfecho de uma decisão de transferência da IA — rótulo do span
/// `ia.transferencia` e da métrica `smartcore_transferencia_ia_total`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ResultadoTransferencia {
    /// O atendimento mudou de fluxo.
    Aplicada,
    /// A chave da IA não casou nenhum fluxo (ou casou mais de um).
    FluxoDesconhecido,
    /// O `data_postgres` respondeu `transferido = false`.
    NaoEfetivada,
    /// A RPC `TransferirAtendimentoParaFluxo` falhou.
    RpcFalhou,
}

impl ResultadoTransferencia {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Aplicada => "aplicada",
            Self::FluxoDesconhecido => "fluxo_desconhecido",
            Self::NaoEfetivada => "nao_efetivada",
            Self::RpcFalhou => "rpc_falhou",
        }
    }
}

/// Rótulo de baixa cardinalidade do motor para a métrica: o valor vem da
/// resposta do motor de IA e não pode virar rótulo livre.
pub(crate) fn motor_rotulo(motor: &str) -> &'static str {
    match motor {
        "jev" => "jev",
        "llm" => "llm",
        _ => "outro",
    }
}

/// Registra o desfecho no span corrente e na métrica.
pub(crate) fn registrar_resultado(resultado: ResultadoTransferencia, motor: &'static str) {
    tracing::Span::current().record("resultado", resultado.as_str());
    observability::usage_metrics::registrar_transferencia_ia(resultado.as_str(), motor);
}

/// Normaliza uma chave de fluxo para comparação: minúsculas, sem acento,
/// pontuação vira espaço e espaços repetidos colapsam num só.
///
/// Sem `unicode-normalization`: a crate só chega ao workspace de forma
/// transitiva, e os acentos que aparecem nos nomes de setor e fluxo em
/// português cabem numa tabela curta.
pub(crate) fn normalizar_chave(s: &str) -> String {
    let dobrada: String = s
        .chars()
        .flat_map(char::to_lowercase)
        .map(|c| {
            let c = sem_acento(c);
            if c.is_alphanumeric() {
                c
            } else {
                ' '
            }
        })
        .collect();
    dobrada.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Troca a letra acentuada (já minúscula) pela letra base.
fn sem_acento(c: char) -> char {
    match c {
        'á' | 'à' | 'â' | 'ã' | 'ä' => 'a',
        'é' | 'è' | 'ê' | 'ë' => 'e',
        'í' | 'ì' | 'î' | 'ï' => 'i',
        'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
        'ú' | 'ù' | 'û' | 'ü' => 'u',
        'ç' => 'c',
        'ñ' => 'n',
        outro => outro,
    }
}

/// O fluxo cuja chave normalizada é igual à da IA. `None` quando nenhum casa,
/// quando a chave é vazia ou quando há empate entre fluxos.
pub(crate) fn buscar_fluxo<'a>(fluxos: &'a [FluxoItem], chave_ia: &str) -> Option<&'a FluxoItem> {
    let alvo = normalizar_chave(chave_ia);
    if alvo.is_empty() {
        return None;
    }
    let mut casados = fluxos.iter().filter(|f| normalizar_chave(&f.chave) == alvo);
    match (casados.next(), casados.next()) {
        (Some(f), None) => Some(f),
        _ => None,
    }
}

impl FluxosCache {
    /// Descarta os fluxos do tenant, forçando a próxima leitura a ir ao
    /// `data_postgres`. Usado quando a chave da IA não casa: o cache pode
    /// estar velho logo após a criação ou renomeação de um fluxo.
    pub(crate) async fn invalidar(&self, tenant: Uuid) {
        self.inner.lock().await.remove(&tenant);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fluxo(chave: &str, fluxo_id: i32) -> FluxoItem {
        FluxoItem {
            chave: chave.to_string(),
            fluxo_id,
        }
    }

    #[test]
    fn normalizar_chave_ignora_caixa_espacos_e_acentos() {
        assert_eq!(
            normalizar_chave("  Comercial -   Orçamentos e COTAÇÕES "),
            "comercial orcamentos e cotacoes"
        );
        assert_eq!(
            normalizar_chave("comercial - orcamentos e cotacoes"),
            normalizar_chave("Comercial – Orçamentos e Cotações")
        );
    }

    #[test]
    fn normalizar_chave_trata_pontuacao_como_separador() {
        assert_eq!(normalizar_chave("Comercial-vendas"), "comercial vendas");
        assert_eq!(normalizar_chave("Comercial - vendas."), "comercial vendas");
    }

    #[test]
    fn normalizar_chave_vazia_ou_so_pontuacao_fica_vazia() {
        assert_eq!(normalizar_chave(""), "");
        assert_eq!(normalizar_chave("  -  "), "");
    }

    #[test]
    fn buscar_fluxo_casa_chave_com_caixa_e_acento_diferentes() {
        let fluxos = vec![
            fluxo("Atendimento - Fluxo responsável pela triagem", 300),
            fluxo("Comercial - Cotações e pedidos", 301),
        ];
        let achado = buscar_fluxo(&fluxos, "COMERCIAL - cotacoes  e pedidos").map(|f| f.fluxo_id);
        assert_eq!(achado, Some(301));
    }

    #[test]
    fn buscar_fluxo_sem_casamento_ou_chave_vazia_devolve_none() {
        let fluxos = vec![fluxo("Comercial - vendas", 1)];
        assert!(buscar_fluxo(&fluxos, "Financeiro - boletos").is_none());
        assert!(buscar_fluxo(&fluxos, "").is_none());
        assert!(buscar_fluxo(&[], "Comercial - vendas").is_none());
    }

    #[test]
    fn buscar_fluxo_com_empate_devolve_none() {
        // Dois fluxos que só diferem em acento/caixa: ambíguo, não transfere.
        let fluxos = vec![
            fluxo("Comercial - Cotação", 1),
            fluxo("comercial - cotacao", 2),
        ];
        assert!(buscar_fluxo(&fluxos, "Comercial - Cotação").is_none());
    }

    #[test]
    fn resultado_e_motor_tem_rotulos_estaveis() {
        assert_eq!(ResultadoTransferencia::Aplicada.as_str(), "aplicada");
        assert_eq!(
            ResultadoTransferencia::FluxoDesconhecido.as_str(),
            "fluxo_desconhecido"
        );
        assert_eq!(
            ResultadoTransferencia::NaoEfetivada.as_str(),
            "nao_efetivada"
        );
        assert_eq!(ResultadoTransferencia::RpcFalhou.as_str(), "rpc_falhou");
        assert_eq!(motor_rotulo("jev"), "jev");
        assert_eq!(motor_rotulo("llm"), "llm");
        assert_eq!(motor_rotulo("qualquer-coisa"), "outro");
    }

    #[tokio::test]
    async fn invalidar_descarta_os_fluxos_do_tenant() {
        let cache = FluxosCache::novo();
        let tenant = Uuid::new_v4();
        let outro = Uuid::new_v4();
        cache
            .gravar(tenant, std::sync::Arc::new(vec![fluxo("A - b", 1)]))
            .await;
        cache
            .gravar(outro, std::sync::Arc::new(vec![fluxo("C - d", 2)]))
            .await;

        cache.invalidar(tenant).await;

        assert!(cache.obter(tenant).await.is_none(), "tenant invalidado");
        assert!(cache.obter(outro).await.is_some(), "outro tenant intacto");
    }
}
