//! Watchdog: vigia a stack, reinicia o que travou e registra cada intervenção
//! na auditoria.
//!
//! # Por que existe
//!
//! `restart: unless-stopped` só reage a processo que **morre**. Serviço travado
//! — deadlock, pool esgotado, loop de consumo parado — fica `running` para
//! sempre, e a stack continua de pé sem funcionar. Os healthchecks (introduzidos
//! junto com este serviço) marcam esse container como `unhealthy`, mas o
//! `docker compose` **não faz nada** com essa informação: reiniciar container
//! não saudável é comportamento do Swarm/Kubernetes, não do compose. Alguém
//! precisa fechar o laço, e é este serviço.
//!
//! # O gauge é a outra metade do trabalho
//!
//! O alerting não conseguia enxergar serviço fora do ar: as métricas chegam por
//! push (OTLP), então quando um serviço morre a série simplesmente **some** —
//! não vai a zero. Alerta sobre série ausente não dispara.
//!
//! O watchdog resolve isso publicando `smartcore_service_up` por serviço a
//! partir de **fora** deles. Como quem publica está vivo, o zero é publicado de
//! verdade e o alerta tem em que morder.
//!
//! # O que ele não faz
//!
//! Não reinicia indefinidamente: ver [`estado::Politica`]. Falha permanente vira
//! um alerta e para por aí — reinício infinito consome o host e disfarça de
//! instabilidade o que é defeito.

mod estado;

use bollard::query_parameters::{
    InspectContainerOptions, ListContainersOptionsBuilder, RestartContainerOptions,
};
use bollard::Docker;
use estado::{Decisao, Politica};
// O OTel vem re-exportado pelo `observability` — mesma versão que o resto da
// stack usa, sem repetir a dependência (e o risco de divergir) neste Cargo.toml.
use observability::opentelemetry::{global, KeyValue};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

/// Estado de saúde por serviço, compartilhado com o callback do gauge.
/// 1 = no ar e saudável, 0 = caído ou não saudável.
type MapaSaude = Arc<Mutex<HashMap<String, u64>>>;

/// Situação de um container nesta rodada, já traduzida do vocabulário do Docker.
#[derive(Debug, PartialEq, Eq)]
enum Situacao {
    Saudavel,
    /// Ainda dentro do `start_period` do healthcheck: não é falha.
    Subindo,
    NaoSaudavel {
        motivo: String,
    },
}

fn env_num<T: std::str::FromStr>(chave: &str, padrao: T) -> T {
    std::env::var(chave)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(padrao)
}

/// Traduz o estado do Docker para a decisão que nos interessa.
///
/// Container **sem** healthcheck declarado só pode ser julgado pelo `status`:
/// `running` passa. É um julgamento fraco de propósito — é exatamente por isso
/// que os serviços ganharam sonda de verdade; aqui é só a rede de segurança.
fn avaliar(inspecao: &bollard::models::ContainerInspectResponse) -> Situacao {
    use bollard::models::{ContainerStateStatusEnum, HealthStatusEnum};

    let Some(estado) = inspecao.state.as_ref() else {
        return Situacao::NaoSaudavel {
            motivo: "docker nao devolveu o estado do container".to_string(),
        };
    };

    if let Some(saude) = estado.health.as_ref() {
        return match saude.status {
            Some(HealthStatusEnum::HEALTHY) => Situacao::Saudavel,
            Some(HealthStatusEnum::STARTING) => Situacao::Subindo,
            Some(HealthStatusEnum::UNHEALTHY) => {
                // A última saída da sonda é o que explica a falha; sem ela, o
                // evento de auditoria diria apenas "unhealthy" e a investigação
                // começaria do zero.
                let ultima = saude
                    .log
                    .as_ref()
                    .and_then(|l| l.last())
                    .and_then(|e| e.output.clone())
                    .unwrap_or_default();
                let ultima = ultima.trim();
                Situacao::NaoSaudavel {
                    motivo: if ultima.is_empty() {
                        "healthcheck falhou".to_string()
                    } else {
                        format!(
                            "healthcheck falhou: {}",
                            ultima.chars().take(300).collect::<String>()
                        )
                    },
                }
            }
            _ => match estado.status {
                Some(ContainerStateStatusEnum::RUNNING) => Situacao::Saudavel,
                outro => Situacao::NaoSaudavel {
                    motivo: format!("container em estado {outro:?}"),
                },
            },
        };
    }

    match estado.status {
        Some(ContainerStateStatusEnum::RUNNING) => Situacao::Saudavel,
        // `restarting` é o Docker já cuidando do caso: intervir aqui só
        // atrapalharia o backoff dele.
        Some(ContainerStateStatusEnum::RESTARTING) => Situacao::Subindo,
        Some(ContainerStateStatusEnum::CREATED) => Situacao::Subindo,
        outro => Situacao::NaoSaudavel {
            motivo: format!("container em estado {outro:?}"),
        },
    }
}

#[allow(clippy::too_many_arguments)]
async fn rodada(
    docker: &Docker,
    audit: &observability::AuditLogger,
    politica: &mut Politica,
    saude: &MapaSaude,
    projeto: &str,
    ignorados: &[String],
) -> anyhow::Result<()> {
    let mut filtros = HashMap::new();
    filtros.insert(
        "label".to_string(),
        vec![format!("com.docker.compose.project={projeto}")],
    );

    let containers = docker
        .list_containers(Some(
            ListContainersOptionsBuilder::default()
                .all(true)
                .filters(&filtros)
                .build(),
        ))
        .await?;

    let agora = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    for container in containers {
        let servico = container
            .labels
            .as_ref()
            .and_then(|l| l.get("com.docker.compose.service"))
            .cloned()
            .unwrap_or_default();

        if servico.is_empty() || ignorados.iter().any(|i| i == &servico) {
            continue;
        }

        let Some(id) = container.id.as_ref() else {
            continue;
        };

        let inspecao = match docker
            .inspect_container(id, None::<InspectContainerOptions>)
            .await
        {
            Ok(i) => i,
            Err(e) => {
                tracing::warn!(servico = %servico, erro = ?e, "Falha ao inspecionar container");
                continue;
            }
        };

        // Crash-loop: o container sobe, morre e o Docker reergue sozinho. O
        // watchdog não intervém (atropelaria o backoff do Docker), mas o ciclo
        // precisa aparecer em algum lugar — antes, não aparecia em lugar nenhum
        // depois que o deploy terminava.
        let reinicios = inspecao.restart_count.unwrap_or(0);
        if let Some(novos) = politica.notar_reinicios(&servico, reinicios) {
            if !politica.em_intervencao(&servico) {
                tracing::warn!(
                    servico = %servico, novos, total = reinicios,
                    "Container reiniciou sozinho desde a ultima rodada"
                );
                audit.warn_global(
                    "service.reiniciou_sozinho",
                    &format!(
                        "Servico {servico} reiniciou sozinho {novos}x desde a ultima verificacao"
                    ),
                    serde_json::json!({
                        "servico": servico,
                        "projeto": projeto,
                        "novos": novos,
                        "total": reinicios,
                    }),
                    None,
                    None,
                    None,
                );
            }
        }

        let situacao = avaliar(&inspecao);
        saude
            .lock()
            .await
            .insert(servico.clone(), u64::from(situacao == Situacao::Saudavel));

        match situacao {
            Situacao::Subindo => {}
            Situacao::Saudavel => {
                if politica.registrar_saudavel(&servico) {
                    audit.info_global(
                        "service.recuperado",
                        &format!("Servico {servico} voltou a responder apos intervencao"),
                        serde_json::json!({ "servico": servico, "projeto": projeto }),
                        None,
                        None,
                        None,
                    );
                    tracing::info!(servico = %servico, "Servico recuperado");
                }
            }
            Situacao::NaoSaudavel { motivo } => {
                agir(
                    docker, audit, politica, projeto, &servico, id, &motivo, agora,
                )
                .await;
            }
        }
    }

    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn agir(
    docker: &Docker,
    audit: &observability::AuditLogger,
    politica: &mut Politica,
    projeto: &str,
    servico: &str,
    id: &str,
    motivo: &str,
    agora: u64,
) {
    match politica.decidir(servico, agora) {
        Decisao::AguardarSilencioso => {}
        Decisao::Desistir => {
            tracing::error!(
                servico = %servico, motivo = %motivo,
                "Teto de reinicios atingido; watchdog nao vai insistir"
            );
            audit.error_global(
                "service.restart_desistido",
                &format!(
                    "Servico {servico} continua falhando apos o teto de reinicios; intervencao humana necessaria"
                ),
                serde_json::json!({
                    "servico": servico,
                    "projeto": projeto,
                    "motivo": motivo,
                }),
                None,
                None,
                None,
            );
        }
        Decisao::Reiniciar { tentativa } => {
            tracing::warn!(
                servico = %servico, tentativa, motivo = %motivo,
                "Servico nao saudavel; reiniciando"
            );
            // Auditar ANTES de reiniciar: se o restart travar o daemon ou o
            // watchdog cair no meio, o registro de que houve intervenção já saiu.
            audit.warn_global(
                "service.nao_saudavel",
                &format!("Servico {servico} nao esta saudavel: {motivo}"),
                serde_json::json!({
                    "servico": servico,
                    "projeto": projeto,
                    "motivo": motivo,
                    "tentativa": tentativa,
                }),
                None,
                None,
                None,
            );

            match docker
                .restart_container(id, None::<RestartContainerOptions>)
                .await
            {
                Ok(()) => {
                    audit.warn_global(
                        "service.reiniciado",
                        &format!(
                            "Servico {servico} reiniciado pelo watchdog (tentativa {tentativa})"
                        ),
                        serde_json::json!({
                            "servico": servico,
                            "projeto": projeto,
                            "motivo": motivo,
                            "tentativa": tentativa,
                        }),
                        None,
                        None,
                        None,
                    );
                    tracing::info!(servico = %servico, tentativa, "Servico reiniciado");
                }
                Err(e) => {
                    tracing::error!(servico = %servico, erro = ?e, "Falha ao reiniciar o servico");
                    audit.error_global(
                        "service.restart_falhou",
                        &format!("Watchdog nao conseguiu reiniciar {servico}"),
                        serde_json::json!({
                            "servico": servico,
                            "projeto": projeto,
                            "erro": e.to_string(),
                        }),
                        None,
                        None,
                        None,
                    );
                }
            }
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry("watchdog", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    // Panic em task de background mata so a task: o processo segue vivo e a
    // funcionalidade some sem deixar rastro. O hook garante o registro estruturado.
    observability::instalar_hook_de_panic("watchdog");

    // O projeto do compose é o recorte do que este watchdog vigia. Sem ele, o
    // serviço mexeria em containers de outras stacks do mesmo host — que é
    // exatamente o caso aqui (dev, prod, evolution e observabilidade convivem).
    let projeto = std::env::var("SMARTCORE_WATCHDOG_PROJETO").map_err(|_| {
        anyhow::anyhow!(
            "SMARTCORE_WATCHDOG_PROJETO e obrigatoria (ex.: smart-core-v2-dev): sem ela o \
             watchdog nao sabe quais containers sao dele"
        )
    })?;

    let intervalo = Duration::from_secs(env_num("SMARTCORE_WATCHDOG_INTERVALO_SEGUNDOS", 30u64));
    let max_tentativas = env_num("SMARTCORE_WATCHDOG_MAX_TENTATIVAS", 3u32);
    let janela = env_num("SMARTCORE_WATCHDOG_JANELA_SEGUNDOS", 900u64);

    // O próprio watchdog e os jobs one-off ficam de fora: o primeiro se
    // reiniciaria em laço, e os segundos TERMINAM em `exited` por projeto — para
    // eles, "parado" é sucesso.
    let ignorados: Vec<String> = std::env::var("SMARTCORE_WATCHDOG_IGNORAR")
        .unwrap_or_else(|_| "watchdog,minio-setup".to_string())
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    let bus_url = std::env::var("REDIS_BUS_URL")
        .or_else(|_| std::env::var("REDIS_URL"))
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let bus_conn = infrastructure_redis::criar_conexao_com_timeouts(&bus_url)
        .await
        .map_err(|e| anyhow::anyhow!("falha ao conectar no barramento Redis: {e}"))?;
    let audit = observability::AuditLogger::new_with_redis(bus_conn, "watchdog");

    let docker = Docker::connect_with_socket_defaults()
        .map_err(|e| anyhow::anyhow!("falha ao falar com o daemon do Docker: {e}"))?;

    let saude: MapaSaude = Arc::new(Mutex::new(HashMap::new()));

    // Gauge observável (a versão 0.24 do OTel não tem gauge síncrono — mesmo
    // padrão de `observability::pool_metrics`). É esta série que dá ao alerting
    // um zero concreto quando um serviço cai.
    let saude_gauge = saude.clone();
    let meter = global::meter("watchdog");
    let _g_up = meter
        .u64_observable_gauge("smartcore_service_up")
        .with_description("1 quando o servico esta no ar e saudavel, 0 caso contrario")
        .with_callback(move |obs| {
            // O callback é síncrono; `try_lock` evita segurar o coletor caso a
            // rodada esteja escrevendo. Perder uma amostra é irrelevante — o
            // scrape seguinte vem em segundos.
            if let Ok(mapa) = saude_gauge.try_lock() {
                for (servico, valor) in mapa.iter() {
                    obs.observe(*valor, &[KeyValue::new("servico", servico.clone())]);
                }
            }
        })
        .init();

    tracing::info!(
        projeto = %projeto,
        intervalo_s = intervalo.as_secs(),
        max_tentativas,
        "Watchdog no ar"
    );
    audit.info_global(
        "watchdog.iniciado",
        &format!("Watchdog vigiando o projeto {projeto}"),
        serde_json::json!({ "projeto": projeto, "intervalo_s": intervalo.as_secs() }),
        None,
        None,
        None,
    );

    let mut politica = Politica::nova(max_tentativas, janela);
    let mut tick = tokio::time::interval(intervalo);
    let parada = observability::aguardar_sinal_de_parada();
    tokio::pin!(parada);

    loop {
        tokio::select! {
            _ = tick.tick() => {
                // Falha de uma rodada (daemon reiniciando, por exemplo) não pode
                // derrubar o vigia — ele é justamente quem deveria estar de pé
                // nessa hora.
                if let Err(e) =
                    rodada(&docker, &audit, &mut politica, &saude, &projeto, &ignorados).await
                {
                    tracing::error!(erro = ?e, "Rodada do watchdog falhou");
                }
                // Mantém o gauge vivo pelo ciclo do processo (ver pool_metrics).
                let _keep_alive = &_g_up;
            }
            _ = &mut parada => break,
        }
    }

    audit.info_global(
        "watchdog.encerrado",
        &format!("Watchdog do projeto {projeto} encerrado a pedido do supervisor"),
        serde_json::json!({ "projeto": projeto }),
        None,
        None,
        None,
    );
    // Sem esta folga, o próprio evento de encerramento não chega ao barramento.
    tokio::time::sleep(Duration::from_millis(500)).await;
    observability::shutdown_telemetry();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use bollard::models::{
        ContainerInspectResponse, ContainerState, ContainerStateStatusEnum, Health,
        HealthStatusEnum, HealthcheckResult,
    };

    fn inspecao(
        status: Option<ContainerStateStatusEnum>,
        saude: Option<HealthStatusEnum>,
        saida: Option<&str>,
    ) -> ContainerInspectResponse {
        ContainerInspectResponse {
            state: Some(ContainerState {
                status,
                health: saude.map(|s| Health {
                    status: Some(s),
                    log: saida.map(|o| {
                        vec![HealthcheckResult {
                            output: Some(o.to_string()),
                            ..Default::default()
                        }]
                    }),
                    ..Default::default()
                }),
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn container_saudavel_passa() {
        let i = inspecao(
            Some(ContainerStateStatusEnum::RUNNING),
            Some(HealthStatusEnum::HEALTHY),
            None,
        );
        assert_eq!(avaliar(&i), Situacao::Saudavel);
    }

    #[test]
    fn starting_nao_e_falha() {
        // Reiniciar durante o start_period criaria um laço de subida: o serviço
        // nunca teria tempo de terminar de iniciar.
        let i = inspecao(
            Some(ContainerStateStatusEnum::RUNNING),
            Some(HealthStatusEnum::STARTING),
            None,
        );
        assert_eq!(avaliar(&i), Situacao::Subindo);
    }

    #[test]
    fn unhealthy_carrega_a_saida_da_sonda_no_motivo() {
        // É esse texto que vai para a auditoria; sem ele o evento diria apenas
        // "não saudável" e a investigação começaria do zero.
        let i = inspecao(
            Some(ContainerStateStatusEnum::RUNNING),
            Some(HealthStatusEnum::UNHEALTHY),
            Some("data_postgres: sonda falhou: sonda excedeu o prazo de 3000 ms"),
        );
        match avaliar(&i) {
            Situacao::NaoSaudavel { motivo } => {
                assert!(motivo.contains("sonda excedeu o prazo"), "motivo: {motivo}");
            }
            outro => panic!("esperava NaoSaudavel, veio {outro:?}"),
        }
    }

    #[test]
    fn processo_vivo_sem_sonda_declarada_passa() {
        // Julgamento fraco por opção: é o melhor que dá para dizer de quem não
        // declara healthcheck. A sonda de verdade é que resolve.
        let i = inspecao(Some(ContainerStateStatusEnum::RUNNING), None, None);
        assert_eq!(avaliar(&i), Situacao::Saudavel);
    }

    #[test]
    fn container_parado_e_falha() {
        let i = inspecao(Some(ContainerStateStatusEnum::EXITED), None, None);
        assert!(matches!(avaliar(&i), Situacao::NaoSaudavel { .. }));
    }

    #[test]
    fn restarting_fica_a_cargo_do_docker() {
        // O Docker já está aplicando o próprio backoff; intervir aqui só
        // atropelaria essa recuperação.
        let i = inspecao(Some(ContainerStateStatusEnum::RESTARTING), None, None);
        assert_eq!(avaliar(&i), Situacao::Subindo);
    }
}
