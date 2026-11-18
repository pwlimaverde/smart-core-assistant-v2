// transport/src/disjuntor.rs  (comentários em pt-br)
//
// Disjuntor (circuit breaker) de dependência para consumidores do barramento.
//
// Num consumidor de Redis Streams, "falhar rápido" é o comportamento ERRADO: cada
// falha devolve o evento à PEL, o reprocessador periódico o reentrega e, depois de
// `MAX_ENTREGAS`, ele vai para a DLQ. Com a dependência fora do ar, rejeitar a
// chamada só acelera a ida de mensagens válidas para a DLQ. Aqui o disjuntor é
// contrapressão: aberto, ele SEGURA a leitura do stream — o evento continua no
// stream, o lag cresce, a métrica de estado acusa e o alerta dispara.
//
// Transições:
// - Fechado -> Aberto: `limiar_falhas` falhas de transporte dentro de `janela`.
// - Aberto -> MeioAberto: passada a `espera_aberto` (avaliado sob demanda).
// - MeioAberto -> Fechado: `sucessos_para_fechar` sucessos.
// - MeioAberto -> Aberto: qualquer falha.
//
// Só falha de TRANSPORTE conta (prazo expirado, conexão caída). Erro de negócio
// devolvido pelo serviço prova que a dependência respondeu e conta como sucesso.
//
// `limiar_falhas = 0` desliga o disjuntor (fica sempre fechado): é o interruptor
// de rollback sem rebuild.

use opentelemetry::metrics::{Counter, ObservableGauge};
use opentelemetry::KeyValue;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Estado do disjuntor. O código numérico é o valor do gauge
/// `smartcore_disjuntor_estado` (0 fechado, 1 meio-aberto, 2 aberto).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Estado {
    Fechado,
    MeioAberto,
    Aberto,
}

impl Estado {
    pub fn codigo(self) -> u64 {
        match self {
            Estado::Fechado => 0,
            Estado::MeioAberto => 1,
            Estado::Aberto => 2,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ConfigDisjuntor {
    pub limiar_falhas: usize,
    pub janela: Duration,
    pub espera_aberto: Duration,
    pub sucessos_para_fechar: u32,
}

impl Default for ConfigDisjuntor {
    fn default() -> Self {
        Self {
            limiar_falhas: 5,
            janela: Duration::from_secs(60),
            espera_aberto: Duration::from_secs(60),
            sucessos_para_fechar: 2,
        }
    }
}

impl ConfigDisjuntor {
    /// Lê `{prefixo}_LIMIAR`, `{prefixo}_JANELA_SECS`, `{prefixo}_ESPERA_SECS` e
    /// `{prefixo}_SUCESSOS`. Variável ausente ou inválida cai no default.
    pub fn from_env(prefixo: &str) -> Self {
        let d = Self::default();
        let ler = |suf: &str| -> Option<u64> {
            std::env::var(format!("{prefixo}_{suf}"))
                .ok()
                .and_then(|s| s.trim().parse().ok())
        };
        Self {
            limiar_falhas: ler("LIMIAR").map(|v| v as usize).unwrap_or(d.limiar_falhas),
            janela: ler("JANELA_SECS")
                .filter(|v| *v > 0)
                .map(Duration::from_secs)
                .unwrap_or(d.janela),
            espera_aberto: ler("ESPERA_SECS")
                .filter(|v| *v > 0)
                .map(Duration::from_secs)
                .unwrap_or(d.espera_aberto),
            sucessos_para_fechar: ler("SUCESSOS")
                .filter(|v| *v > 0)
                .map(|v| v as u32)
                .unwrap_or(d.sucessos_para_fechar),
        }
    }

    fn desligado(&self) -> bool {
        self.limiar_falhas == 0
    }
}

struct Interno {
    estado: Estado,
    falhas: VecDeque<Instant>,
    sucessos_meio_aberto: u32,
    aberto_desde: Option<Instant>,
}

pub struct Disjuntor {
    dependencia: String,
    cfg: ConfigDisjuntor,
    interno: Mutex<Interno>,
    codigo_estado: Arc<AtomicU64>,
    aberturas: Counter<u64>,
    // Mantém o gauge vivo: dropado, o callback deixa de ser coletado.
    _gauge_estado: ObservableGauge<u64>,
}

impl Disjuntor {
    /// Cria o disjuntor e registra `smartcore_disjuntor_estado` (gauge) e
    /// `smartcore_disjuntor_aberturas_total` (counter), ambos com o label
    /// `dependencia`. Sem provider de métricas configurado, os instrumentos são no-op.
    pub fn novo(dependencia: impl Into<String>, cfg: ConfigDisjuntor) -> Self {
        let dependencia = dependencia.into();
        let codigo_estado = Arc::new(AtomicU64::new(Estado::Fechado.codigo()));
        let meter = opentelemetry::global::meter("transport");

        let leitura = codigo_estado.clone();
        let rotulo = dependencia.clone();
        let gauge = meter
            .u64_observable_gauge("smartcore_disjuntor_estado")
            .with_description(
                "Estado do disjuntor da dependencia: 0 fechado, 1 meio-aberto, 2 aberto",
            )
            .with_callback(move |obs| {
                obs.observe(
                    leitura.load(Ordering::Relaxed),
                    &[KeyValue::new("dependencia", rotulo.clone())],
                );
            })
            .init();
        let aberturas = meter
            .u64_counter("smartcore_disjuntor_aberturas_total")
            .with_description("Vezes que o disjuntor da dependencia abriu")
            .init();

        if cfg.desligado() {
            tracing::warn!(dependencia = %dependencia, "disjuntor desligado por configuração (limiar 0)");
        }

        Self {
            dependencia,
            cfg,
            interno: Mutex::new(Interno {
                estado: Estado::Fechado,
                falhas: VecDeque::new(),
                sucessos_meio_aberto: 0,
                aberto_desde: None,
            }),
            codigo_estado,
            aberturas,
            _gauge_estado: gauge,
        }
    }

    pub fn dependencia(&self) -> &str {
        &self.dependencia
    }

    pub fn estado(&self) -> Estado {
        self.estado_em(Instant::now())
    }

    /// `false` apenas no estado Aberto. Meio-aberto deixa passar: é o tráfego real
    /// que serve de sonda.
    pub fn permite(&self) -> bool {
        self.estado() != Estado::Aberto
    }

    pub fn registrar_sucesso(&self) {
        self.registrar_sucesso_em(Instant::now());
    }

    pub fn registrar_falha(&self) {
        self.registrar_falha_em(Instant::now());
    }

    /// Tempo até o disjuntor passar a meio-aberto. Zero se não estiver aberto.
    pub fn espera_restante(&self) -> Duration {
        let agora = Instant::now();
        let i = self.travar();
        match (i.estado, i.aberto_desde) {
            (Estado::Aberto, Some(desde)) => self
                .cfg
                .espera_aberto
                .saturating_sub(agora.saturating_duration_since(desde)),
            _ => Duration::ZERO,
        }
    }

    /// Bloqueia enquanto o disjuntor estiver aberto. Continua batendo o liveness:
    /// o loop está vivo e esperando de propósito, e um restart do worker não traria
    /// a dependência de volta. O sinal de falha é a métrica de estado.
    pub async fn aguardar_liberacao(&self) {
        while !self.permite() {
            crate::liveness::bater();
            let espera = self
                .espera_restante()
                .clamp(Duration::from_millis(100), Duration::from_secs(5));
            tokio::time::sleep(espera).await;
        }
    }

    fn travar(&self) -> std::sync::MutexGuard<'_, Interno> {
        self.interno.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn estado_em(&self, agora: Instant) -> Estado {
        let mut g = self.travar();
        let i: &mut Interno = &mut g;
        self.avancar(i, agora);
        i.estado
    }

    fn registrar_sucesso_em(&self, agora: Instant) {
        if self.cfg.desligado() {
            return;
        }
        let mut g = self.travar();
        let i: &mut Interno = &mut g;
        self.avancar(i, agora);
        if i.estado == Estado::MeioAberto {
            i.sucessos_meio_aberto += 1;
            if i.sucessos_meio_aberto >= self.cfg.sucessos_para_fechar {
                i.estado = Estado::Fechado;
                i.falhas.clear();
                i.sucessos_meio_aberto = 0;
                i.aberto_desde = None;
                self.publicar(i.estado);
                tracing::info!(dependencia = %self.dependencia, "disjuntor FECHADO: dependência recuperada");
            }
        }
    }

    fn registrar_falha_em(&self, agora: Instant) {
        if self.cfg.desligado() {
            return;
        }
        let mut g = self.travar();
        let i: &mut Interno = &mut g;
        self.avancar(i, agora);
        let estado = i.estado;
        match estado {
            Estado::Aberto => {}
            Estado::MeioAberto => self.abrir(i, agora, "falha durante o meio-aberto"),
            Estado::Fechado => {
                i.falhas.push_back(agora);
                let janela = self.cfg.janela;
                i.falhas
                    .retain(|t| agora.saturating_duration_since(*t) <= janela);
                if i.falhas.len() >= self.cfg.limiar_falhas {
                    self.abrir(i, agora, "limiar de falhas atingido na janela");
                }
            }
        }
    }

    /// Aberto -> MeioAberto quando a espera venceu. Avaliado sob demanda: quem
    /// consulta o estado (o portão do consumidor, a cada ≤5s) move a máquina.
    fn avancar(&self, i: &mut Interno, agora: Instant) {
        if i.estado != Estado::Aberto {
            return;
        }
        let venceu = i
            .aberto_desde
            .map(|d| agora.saturating_duration_since(d) >= self.cfg.espera_aberto)
            .unwrap_or(true);
        if venceu {
            i.estado = Estado::MeioAberto;
            i.sucessos_meio_aberto = 0;
            self.publicar(i.estado);
            tracing::warn!(dependencia = %self.dependencia, "disjuntor MEIO-ABERTO: liberando tráfego de sonda");
        }
    }

    fn abrir(&self, i: &mut Interno, agora: Instant, motivo: &'static str) {
        let falhas = i.falhas.len();
        i.estado = Estado::Aberto;
        i.aberto_desde = Some(agora);
        i.falhas.clear();
        i.sucessos_meio_aberto = 0;
        self.publicar(i.estado);
        self.aberturas
            .add(1, &[KeyValue::new("dependencia", self.dependencia.clone())]);
        tracing::error!(
            dependencia = %self.dependencia,
            motivo,
            falhas_na_janela = falhas,
            espera_s = self.cfg.espera_aberto.as_secs(),
            "disjuntor ABERTO: consumo do barramento suspenso até a dependência responder"
        );
    }

    fn publicar(&self, estado: Estado) {
        self.codigo_estado.store(estado.codigo(), Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> ConfigDisjuntor {
        ConfigDisjuntor::default()
    }

    #[test]
    fn abre_ao_atingir_o_limiar_dentro_da_janela() {
        let d = Disjuntor::novo("teste", cfg());
        let t0 = Instant::now();
        for s in 0..4 {
            d.registrar_falha_em(t0 + Duration::from_secs(s * 10));
            assert_eq!(
                d.estado_em(t0 + Duration::from_secs(s * 10)),
                Estado::Fechado
            );
        }
        d.registrar_falha_em(t0 + Duration::from_secs(40));
        assert_eq!(d.estado_em(t0 + Duration::from_secs(40)), Estado::Aberto);
        assert_eq!(d.codigo_estado.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn falhas_espalhadas_alem_da_janela_nao_abrem() {
        let d = Disjuntor::novo("teste", cfg());
        let t0 = Instant::now();
        // Uma falha a cada 20s: nunca há 5 dentro de 60s.
        for s in 0..10 {
            d.registrar_falha_em(t0 + Duration::from_secs(s * 20));
        }
        assert_eq!(d.estado_em(t0 + Duration::from_secs(200)), Estado::Fechado);
    }

    #[test]
    fn passa_a_meio_aberto_depois_da_espera() {
        let d = Disjuntor::novo("teste", cfg());
        let t0 = Instant::now();
        for _ in 0..5 {
            d.registrar_falha_em(t0);
        }
        assert_eq!(d.estado_em(t0 + Duration::from_secs(59)), Estado::Aberto);
        assert_eq!(
            d.estado_em(t0 + Duration::from_secs(60)),
            Estado::MeioAberto
        );
        assert_eq!(d.codigo_estado.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn fecha_com_dois_sucessos_no_meio_aberto() {
        let d = Disjuntor::novo("teste", cfg());
        let t0 = Instant::now();
        for _ in 0..5 {
            d.registrar_falha_em(t0);
        }
        let t1 = t0 + Duration::from_secs(61);
        d.registrar_sucesso_em(t1);
        assert_eq!(d.estado_em(t1), Estado::MeioAberto);
        d.registrar_sucesso_em(t1);
        assert_eq!(d.estado_em(t1), Estado::Fechado);
        assert_eq!(d.codigo_estado.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn falha_no_meio_aberto_reabre_e_reinicia_a_espera() {
        let d = Disjuntor::novo("teste", cfg());
        let t0 = Instant::now();
        for _ in 0..5 {
            d.registrar_falha_em(t0);
        }
        let t1 = t0 + Duration::from_secs(61);
        d.registrar_sucesso_em(t1);
        d.registrar_falha_em(t1);
        assert_eq!(d.estado_em(t1 + Duration::from_secs(59)), Estado::Aberto);
        assert_eq!(
            d.estado_em(t1 + Duration::from_secs(60)),
            Estado::MeioAberto
        );
    }

    #[test]
    fn sucesso_com_o_disjuntor_aberto_nao_o_fecha() {
        let d = Disjuntor::novo("teste", cfg());
        let t0 = Instant::now();
        for _ in 0..5 {
            d.registrar_falha_em(t0);
        }
        d.registrar_sucesso_em(t0 + Duration::from_secs(1));
        d.registrar_sucesso_em(t0 + Duration::from_secs(2));
        assert_eq!(d.estado_em(t0 + Duration::from_secs(3)), Estado::Aberto);
    }

    #[test]
    fn limiar_zero_desliga_o_disjuntor() {
        let d = Disjuntor::novo(
            "teste",
            ConfigDisjuntor {
                limiar_falhas: 0,
                ..cfg()
            },
        );
        let t0 = Instant::now();
        for _ in 0..100 {
            d.registrar_falha_em(t0);
        }
        assert_eq!(d.estado_em(t0), Estado::Fechado);
    }

    #[test]
    fn config_le_o_ambiente_e_ignora_valor_invalido() {
        std::env::set_var("SMARTCORE_TESTE_DISJ_LIMIAR", "7");
        std::env::set_var("SMARTCORE_TESTE_DISJ_JANELA_SECS", "abc");
        std::env::set_var("SMARTCORE_TESTE_DISJ_ESPERA_SECS", "30");
        let c = ConfigDisjuntor::from_env("SMARTCORE_TESTE_DISJ");
        assert_eq!(c.limiar_falhas, 7);
        assert_eq!(c.janela, Duration::from_secs(60));
        assert_eq!(c.espera_aberto, Duration::from_secs(30));
        assert_eq!(c.sucessos_para_fechar, 2);
        for suf in ["LIMIAR", "JANELA_SECS", "ESPERA_SECS"] {
            std::env::remove_var(format!("SMARTCORE_TESTE_DISJ_{suf}"));
        }
    }

    #[tokio::test]
    async fn aguardar_liberacao_retorna_quando_a_espera_vence() {
        let d = Disjuntor::novo(
            "teste",
            ConfigDisjuntor {
                espera_aberto: Duration::from_millis(200),
                ..cfg()
            },
        );
        for _ in 0..5 {
            d.registrar_falha();
        }
        assert!(!d.permite());
        let inicio = Instant::now();
        tokio::time::timeout(Duration::from_secs(2), d.aguardar_liberacao())
            .await
            .expect("aguardar_liberacao deveria retornar após a espera");
        assert!(inicio.elapsed() >= Duration::from_millis(150));
        assert_eq!(d.estado(), Estado::MeioAberto);
    }
}
