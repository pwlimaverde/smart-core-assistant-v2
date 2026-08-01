//! Decisão de intervenção, isolada do Docker e do relógio para poder ser testada.
//!
//! A parte difícil de um watchdog não é reiniciar — é saber **quando parar de
//! reiniciar**. Um serviço que sobe, quebra e é reiniciado a cada 30 segundos
//! para sempre é pior que um serviço parado: consome o host, enche o log e, o
//! principal, disfarça de "instabilidade" o que na verdade é uma falha
//! permanente que alguém precisa olhar.

use std::collections::HashMap;

/// O que fazer com um container **não saudável** nesta rodada. Quem está bem
/// nem chega aqui — a política existe só para graduar a intervenção.
#[derive(Debug, PartialEq, Eq)]
pub enum Decisao {
    /// Reiniciar e auditar.
    Reiniciar { tentativa: u32 },
    /// Excedeu o teto de tentativas na janela: não adianta reiniciar de novo.
    /// Auditado uma única vez, com severidade alta — daqui em diante é caso
    /// humano, e insistir só apagaria o rastro do que aconteceu.
    Desistir,
    /// Já desistimos deste container e continuamos no mesmo estado: silêncio,
    /// para não repetir o mesmo alerta a cada 30 segundos.
    AguardarSilencioso,
}

/// Estado da máquina de saúde de um container, entre rodadas.
#[derive(Debug, Clone, Default)]
struct Historico {
    tentativas: u32,
    primeira_tentativa_em: u64,
    desistiu: bool,
}

/// Contador de reinícios automáticos observado na rodada anterior. `None` na
/// primeira leitura de cada container — ver [`Politica::notar_reinicios`].
type ReiniciosVistos = std::collections::HashMap<String, i64>;

pub struct Politica {
    /// Teto de reinícios dentro da janela antes de desistir.
    max_tentativas: u32,
    /// Janela, em segundos. Passada sem novas falhas, o histórico zera — um
    /// problema hoje não deve consumir a cota de reinícios do mês que vem.
    janela_segundos: u64,
    historico: HashMap<String, Historico>,
    reinicios_vistos: ReiniciosVistos,
}

impl Politica {
    pub fn nova(max_tentativas: u32, janela_segundos: u64) -> Self {
        Self {
            max_tentativas,
            janela_segundos,
            historico: HashMap::new(),
            reinicios_vistos: ReiniciosVistos::new(),
        }
    }

    /// Quantos reinícios **automáticos** (feitos pelo Docker, via `restart:
    /// unless-stopped`) aconteceram desde a rodada anterior.
    ///
    /// Existe porque crash-loop era invisível em tempo de execução: o container
    /// sobe, morre, o Docker reergue, e o watchdog só vê `restarting` — que ele
    /// trata como "subindo", e com razão, já que intervir atropelaria o backoff
    /// do próprio Docker. Ninguém registrava o ciclo. Aqui o ciclo vira evento
    /// sem intervenção nenhuma.
    ///
    /// Devolve `None` quando não há nada a relatar: primeira leitura do
    /// container (não dá para chamar de novo o que nunca foi visto), contador
    /// estável, ou contador que **diminuiu** — o que acontece quando o container
    /// é recriado num deploy e o número volta a zero.
    pub fn notar_reinicios(&mut self, nome: &str, atual: i64) -> Option<i64> {
        match self.reinicios_vistos.insert(nome.to_string(), atual) {
            Some(anterior) if atual > anterior => Some(atual - anterior),
            _ => None,
        }
    }

    /// Se este container está em intervenção do watchdog agora. Serve para não
    /// contar como crash-loop o reinício que o próprio watchdog acabou de
    /// mandar fazer — seriam dois eventos para o mesmo incidente.
    pub fn em_intervencao(&self, nome: &str) -> bool {
        self.historico.contains_key(nome)
    }

    /// Decide o que fazer com um container não saudável, agora.
    pub fn decidir(&mut self, nome: &str, agora: u64) -> Decisao {
        let entrada = self.historico.entry(nome.to_string()).or_default();

        // Janela expirada: o incidente anterior é história, começa de novo.
        if entrada.tentativas > 0
            && agora.saturating_sub(entrada.primeira_tentativa_em) > self.janela_segundos
        {
            *entrada = Historico::default();
        }

        if entrada.desistiu {
            return Decisao::AguardarSilencioso;
        }

        if entrada.tentativas >= self.max_tentativas {
            entrada.desistiu = true;
            return Decisao::Desistir;
        }

        if entrada.tentativas == 0 {
            entrada.primeira_tentativa_em = agora;
        }
        entrada.tentativas += 1;
        Decisao::Reiniciar {
            tentativa: entrada.tentativas,
        }
    }

    /// Container voltou a ficar saudável. Devolve `true` se ele estava em
    /// intervenção — só nesse caso a recuperação é digna de registro.
    pub fn registrar_saudavel(&mut self, nome: &str) -> bool {
        match self.historico.remove(nome) {
            Some(h) => h.tentativas > 0,
            None => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primeira_falha_reinicia() {
        let mut p = Politica::nova(3, 600);
        assert_eq!(
            p.decidir("worker", 1000),
            Decisao::Reiniciar { tentativa: 1 }
        );
    }

    #[test]
    fn desiste_depois_do_teto_e_depois_silencia() {
        // O caso que motiva a política: falha permanente. Queremos três tentativas,
        // UM alerta de desistência e silêncio depois — não um alarme a cada rodada.
        let mut p = Politica::nova(3, 600);
        for tentativa in 1..=3 {
            assert_eq!(p.decidir("worker", 1000), Decisao::Reiniciar { tentativa });
        }
        assert_eq!(p.decidir("worker", 1000), Decisao::Desistir);
        assert_eq!(p.decidir("worker", 1030), Decisao::AguardarSilencioso);
        assert_eq!(p.decidir("worker", 1060), Decisao::AguardarSilencioso);
    }

    #[test]
    fn janela_expirada_zera_o_historico() {
        // Uma falha isolada hoje não pode consumir a cota de reinícios de um
        // incidente independente semanas depois.
        let mut p = Politica::nova(2, 600);
        assert_eq!(
            p.decidir("worker", 1000),
            Decisao::Reiniciar { tentativa: 1 }
        );
        assert_eq!(
            p.decidir("worker", 2000),
            Decisao::Reiniciar { tentativa: 1 }
        );
    }

    #[test]
    fn recuperacao_so_e_noticia_se_houve_intervencao() {
        let mut p = Politica::nova(3, 600);
        assert!(
            !p.registrar_saudavel("worker"),
            "container que nunca falhou não gera evento de recuperação"
        );

        p.decidir("worker", 1000);
        assert!(p.registrar_saudavel("worker"));
        // E, tendo zerado, não repete o aviso na rodada seguinte.
        assert!(!p.registrar_saudavel("worker"));
    }

    #[test]
    fn primeira_leitura_de_reinicios_nao_gera_evento() {
        // Um container que já estava de pé com 7 reinícios acumulados não deve
        // gerar alarme só porque o watchdog acabou de subir e o viu pela
        // primeira vez — o incidente é antigo.
        let mut p = Politica::nova(3, 600);
        assert_eq!(p.notar_reinicios("worker", 7), None);
    }

    #[test]
    fn crescimento_do_contador_vira_evento_com_o_delta() {
        let mut p = Politica::nova(3, 600);
        p.notar_reinicios("worker", 7);
        assert_eq!(p.notar_reinicios("worker", 9), Some(2));
    }

    #[test]
    fn contador_estavel_fica_em_silencio() {
        let mut p = Politica::nova(3, 600);
        p.notar_reinicios("worker", 7);
        assert_eq!(p.notar_reinicios("worker", 7), None);
    }

    #[test]
    fn contador_que_zera_no_deploy_nao_e_crash_loop() {
        // Container recriado começa do zero. Sem esta guarda, todo deploy
        // pareceria uma queda.
        let mut p = Politica::nova(3, 600);
        p.notar_reinicios("worker", 9);
        assert_eq!(p.notar_reinicios("worker", 0), None);
    }

    #[test]
    fn intervencao_do_watchdog_e_reconhecivel() {
        // Serve para não relatar como crash-loop o reinício que o próprio
        // watchdog mandou fazer.
        let mut p = Politica::nova(3, 600);
        assert!(!p.em_intervencao("worker"));
        p.decidir("worker", 1000);
        assert!(p.em_intervencao("worker"));
        p.registrar_saudavel("worker");
        assert!(!p.em_intervencao("worker"));
    }

    #[test]
    fn a_desistencia_e_por_container() {
        // Um serviço quebrado não pode calar o watchdog para os outros.
        let mut p = Politica::nova(1, 600);
        p.decidir("worker", 1000);
        assert_eq!(p.decidir("worker", 1000), Decisao::Desistir);
        assert_eq!(
            p.decidir("data_postgres", 1000),
            Decisao::Reiniciar { tentativa: 1 }
        );
    }
}
