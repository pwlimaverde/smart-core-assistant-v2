// observability/src/pool_metrics.rs (comentários em pt-br)
use opentelemetry::{global, KeyValue};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;

/// Inicializa os Observable Gauges para exportação das métricas de saúde do PgPool.
/// Como opentelemetry 0.24.0 não possui Gauge síncrono que aceite valores pontuais,
/// registramos callbacks que observam o estado instantâneo do pool periodicamente.
pub fn monitorar_pool(pool: PgPool, intervalo: Duration) {
    let meter = global::meter("data_postgres");

    // Guardamos o pool num Arc para compartilhar entre callbacks e amostragem
    let pool_shared = Arc::new(pool);

    // 1. Conexões abertas no pool (idle + em uso)
    let pool_size = pool_shared.clone();
    let _g_size = meter
        .u64_observable_gauge("smartcore_pg_pool_size")
        .with_description("Conexoes abertas no pool PG (idle + em uso)")
        .with_callback(move |obs| {
            obs.observe(
                pool_size.size() as u64,
                &[KeyValue::new("pool", "postgres")],
            );
        })
        .init();

    // 2. Conexões ociosas (idle)
    let pool_idle = pool_shared.clone();
    let _g_idle = meter
        .u64_observable_gauge("smartcore_pg_pool_idle")
        .with_description("Conexoes ociosas no pool PG")
        .with_callback(move |obs| {
            obs.observe(
                pool_idle.num_idle() as u64,
                &[KeyValue::new("pool", "postgres")],
            );
        })
        .init();

    // 3. Conexões em uso (size - idle)
    let pool_use = pool_shared.clone();
    let _g_use = meter
        .u64_observable_gauge("smartcore_pg_pool_in_use")
        .with_description("Conexoes em uso ativo no pool PG")
        .with_callback(move |obs| {
            let em_uso = pool_use.size().saturating_sub(pool_use.num_idle() as u32);
            obs.observe(em_uso as u64, &[KeyValue::new("pool", "postgres")]);
        })
        .init();

    // Para evitar que os ObservableGauge sejam dropados (e parem de coletar),
    // nós os movemos para uma task em background que apenas dorme no intervalo.
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(intervalo);
        // Retemos os handles na task para mantê-los vivos durante o ciclo do processo
        let _keep_alive = (_g_size, _g_idle, _g_use);
        loop {
            tick.tick().await;
            tracing::debug!(
                target: "metrics::pool",
                size = pool_shared.size(),
                idle = pool_shared.num_idle(),
                "amostra periodica de saude do pool PostgreSQL gravada"
            );
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;

    #[tokio::test]
    async fn monitorar_pool_registra_gauges_e_amostra_sem_panico() {
        // `connect_lazy` NÃO abre conexão: `size()`/`num_idle()` retornam 0 e o teste
        // roda sem banco. Cobre o registro dos três ObservableGauge e a task de
        // amostragem periódica (o corpo do loop executa em ao menos um tick).
        //
        // Os callbacks de observação dos gauges (`with_callback`) só disparam num
        // ciclo real de coleta de métricas (PeriodicReader/OTLP), o que é território
        // de integração — não coberto aqui por não haver pipeline de exportação.
        let pool = PgPoolOptions::new()
            .connect_lazy("postgres://user:pass@127.0.0.1:5432/db")
            .expect("connect_lazy não deve tentar conectar");

        monitorar_pool(pool, Duration::from_millis(5));

        // Aguarda alguns intervalos para exercitar o corpo do loop de amostragem.
        tokio::time::sleep(Duration::from_millis(30)).await;
    }
}
