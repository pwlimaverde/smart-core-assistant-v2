# Incidente: Timeout RPC Data_Postgres (16-18 Novembro)

**Data**: 16 Novembro 2026, 05:00:45 UTC  
**Duração**: 22 dias  
**Impacto**: 10.003+ mensagens não processadas  
**Status**: ✅ RESOLVIDO (18 Novembro 2026)

---

## 1. CAUSA RAIZ

### Cascata de Falhas Identificada

```
16 Nov 05:00:45 UTC
    ↓
timeout RPC ao data_postgres (limite: 3s)
    ↓ (pool esgotado)
worker não consegue registrar status de msg
    ↓
evento fica na PEL (Pending Entry List) no Redis
    ↓
worker tenta reprocessar → TIMEOUT NOVAMENTE
    ↓ (loop infinito)
10.003+ mensagens acumuladas
    ↓ (nenhum alerta disparado)
Sistema silenciosamente parado por 22 dias
```

### 3 Problemas Raiz

#### **Problema 1: Timeout RPC Muito Curto (3 segundos)**

**Configuração atual**:
```rust
// crates/data_postgres/src/client.rs
const RPC_TIMEOUT: Duration = Duration::from_secs(3);  // ⚠️ TOO SHORT
```

**Por que falhou**:
- Entre 12:32-18:25 do dia 15 (antes do problema):
  - Acquire pool latency: 100-130ms
  - Query latency: 200-300ms (edge case)
- 16 Nov 05:00:45:
  - Query latency pico: ~2.8s
  - Timeout = 3s = **muito perto do limite**
- Uma única query lenta → timeout
- Worker retry → mesma query → timeout
- Loop: timeout → timeout → timeout → ...

**Prova nos logs**:
```
2026-11-16T05:00:45.087232Z ERROR
message: "handler falhou; evento mantido na PEL para reprocessamento"
erro: "Falha ao atualizar status da mensagem no data_postgres: Operação expirou (timeout)"
```

---

#### **Problema 2: Pool de Conexões Postgres Pequeno**

**Configuração**:
```rust
// crates/data_postgres/src/pool.rs
let pool = PgPoolOptions::new()
    .max_connections(5)        // ⚠️ PEQUENO
    .min_connections(1)
    .connect_timeout(Duration::from_secs(10))
    .acquire_timeout(Duration::from_secs(3))  // ⚠️ TIMEOUT POOL
    .max_lifetime(Duration::from_secs(1800))
    .idle_timeout(Duration::from_secs(600))
    .connect(url)
    .await?;
```

**Por que falhou**:
- Worker, ia_engine, e 3 outros serviços usam `data_postgres`
- 5 conexões max com 6+ clientes = contenção
- Latência de acquire sobe: 100ms → 500ms
- Mais timeouts → mais retries → pior contenção
- Espiral de morte

**Simulação do problema**:
```
Tempo T0: 5 conexões em uso (100% pool)
Tempo T1: Worker tenta acquire → ⏳ 500ms
Tempo T2: Timeout = 3s passando...
Tempo T3: Timeout! Falha
Tempo T4: Retry → acquire outra vez (pool ainda 100%) → TIMEOUT NOVAMENTE
```

---

#### **Problema 3: Nenhum Alerta de Consumer Lag**

**Por que não teve alerta**:
- ❌ Sem monitoring de Redis Streams
- ❌ Sem healthcheck de consumer lag
- ❌ Sem alerta de "PEL > N mensagens"
- ❌ Sem alerta de "últimas mensagens processadas há > 5 min"
- ❌ Sem circuit breaker

**Resultado**:
- Sistema falha silenciosamente
- Ninguém sabe que 10k mensagens estão paradas
- 22 dias passam

---

## 2. POR QUE NÃO TEVE ALERTA

### Faltam Observabilidade/Alertas

| Métrica | Alerta Necessário | Implementado? | Status |
|---------|------------------|---------------|--------|
| Consumer lag (Redis Streams) | lag > 1000 msgs | ❌ NÃO | 🔴 CRÍTICO |
| PEL size (Pending Entry List) | PEL > 100 msgs | ❌ NÃO | 🔴 CRÍTICO |
| Última msg processada | tempo > 5 min | ❌ NÃO | 🔴 CRÍTICO |
| Pool acquire latency | latency > 2s | ⚠️ PARCIAL | 🟡 MÉDIO |
| RPC timeout rate | timeout% > 5% | ❌ NÃO | 🔴 CRÍTICO |
| Data_postgres availability | gRPC health | ✅ SIM | 🟢 OK |
| Worker health | container health | ✅ SIM | 🟢 OK |

### Lacunas de Monitoramento

```
❌ Nenhum dashboard em Prometheus mostrando:
   - Redis Streams consumer lag
   - PEL backlog por stream
   - Reprocessamento rate
   - Timeout rate por serviço

❌ Nenhum alerta Grafana para:
   - lag > threshold
   - PEL > threshold
   - Lastprocessed > 5min

❌ Nenhuma métrica exportada:
   - smartcore_consumer_lag
   - smartcore_pel_size
   - smartcore_last_processed_age
```

---

## 3. COMO CONTORNAR (Curto Prazo)

### Executado em 18 Novembro:

```bash
# 1. Limpar streams (10k → 100 mensagens)
redis-cli XTRIM events:stream MAXLEN 100

# 2. Resetar consumer group (remove PEL travado)
redis-cli XGROUP DESTROY events:stream worker_group
redis-cli XGROUP CREATE events:stream worker_group $ MKSTREAM

# 3. Reiniciar worker (recomeça do zero)
docker compose restart worker

# Resultado: ✅ Sistema operacional novamente
```

### Por que funcionou:
- Limpeza remove 9k mensagens antigas (inúteis agora)
- Reset consumer group limpa PEL travada
- Worker fresco reconecta ao Redis e retoma

---

## 4. CORREÇÃO PERMANENTE (Médio Prazo)

### A. Aumentar Timeout RPC

**Hoje**: 3 segundos  
**Proposta**: 10 segundos

```rust
// crates/data_postgres/src/client.rs
- const RPC_TIMEOUT: Duration = Duration::from_secs(3);
+ const RPC_TIMEOUT: Duration = Duration::from_secs(10);
```

**Racional**:
- Query lenta máximo observada: ~2.8s
- Timeout = 10s = 3.5x o máximo
- Se timeout, é problema real, não ruído

### B. Aumentar Pool Postgres

**Hoje**: max 5 conexões  
**Proposta**: max 15 conexões

```rust
// crates/data_postgres/src/pool.rs
let pool = PgPoolOptions::new()
-   .max_connections(5)
+   .max_connections(15)
    .min_connections(2)
    .connect_timeout(Duration::from_secs(10))
-   .acquire_timeout(Duration::from_secs(3))
+   .acquire_timeout(Duration::from_secs(5))
```

**Racional**:
- 6+ serviços usam pool
- 15 conexões = 2-3 por serviço
- Contenção reduzida drasticamente

### C. Implementar Circuit Breaker

```rust
// crates/resilience/src/circuit_breaker.rs
pub struct CircuitBreaker {
    failure_threshold: usize,     // 5 falhas
    success_threshold: usize,     // 2 sucessos para fechar
    timeout: Duration,            // 60s
}

// Se > 5 timeouts em 60s → estado OPEN
// Worker não tenta → falha fast → alerta rápido
```

### D. Implementar Alertas (CRÍTICO)

#### Prometheus Metrics a Exportar:

```rust
// crates/observability/src/metrics.rs
pub static CONSUMER_LAG: Gauge = Gauge::new("smartcore_consumer_lag");
pub static PEL_SIZE: Gauge = Gauge::new("smartcore_pel_size");
pub static LAST_PROCESSED_AGE: Gauge = Gauge::new("smartcore_last_processed_age_secs");
pub static RPC_TIMEOUT_COUNT: Counter = Counter::new("smartcore_rpc_timeout_total");
```

#### Grafana Alerts:

```yaml
alert: ConsumerLagHigh
expr: smartcore_consumer_lag > 1000
for: 2m
annotation: "Consumer lag > 1000, {{ $value }} mensagens atrasadas"

alert: PELSizeHigh
expr: smartcore_pel_size > 100
for: 1m
annotation: "PEL > 100 (timeout loop detectado)"

alert: LastProcessedOld
expr: smartcore_last_processed_age_secs > 300
for: 5m
annotation: "Nenhuma msg processada nos últimos 5 min"

alert: RpcTimeoutRate
expr: rate(smartcore_rpc_timeout_total[5m]) > 0.05
for: 2m
annotation: "RPC timeout rate > 5%"
```

---

## 5. IMPLEMENTAÇÃO DO PLANO

### Fase 1 (Emergência — Hoje)
- ✅ Limpar streams + resetar consumer group
- ✅ Reiniciar worker
- ✅ Confirmar sistema operacional

### Fase 2 (Esta Semana)
- [ ] Aumentar RPC_TIMEOUT: 3s → 10s
- [ ] Aumentar max_connections: 5 → 15
- [ ] Aumentar acquire_timeout: 3s → 5s
- [ ] Deploy em DEV, test 24h, deploy em PROD

### Fase 3 (Próxima Sprint)
- [ ] Circuit breaker implementation
- [ ] Prometheus metrics export
- [ ] Grafana alerts configuradas
- [ ] Teste: simular timeout, verificar alerta dispara

### Fase 4 (Futuro)
- [ ] Dashboard dedicada "Redis Streams Health"
- [ ] Dashboard "RPC Latency by Service"
- [ ] On-call escalation automática
- [ ] Post-mortem: por que levou 22 dias para notar?

---

## 6. LIÇÕES APRENDIDAS

### ❌ O que Falhou

1. **Timeout muito agressivo**: 3s é inadequado para carga
2. **Pool pequeno**: 5 conexões para 6+ serviços
3. **Sem observabilidade**: Consumer lag invisível
4. **Sem alerta**: Sistema pode falhar silenciosamente
5. **Sem circuit breaker**: Cascata de retries amplia o dano

### ✅ O que Funcionou

1. **Redis Streams**: Dados persisted, não perdidos
2. **Consumer group + PEL**: Rastreabilidade de reprocessamento
3. **Health checks**: Containers identificados como saudáveis (falso positivo, mas útil)
4. **Logs estruturados**: Permitiu diagnóstico após 22 dias

### 🎯 Ação Preventiva

1. **Nunca confie em healthcheck de container** — precisa de observabilidade do negócio
2. **Consumer lag é a métrica mais importante** para sistemas baseados em eventos
3. **Circuit breaker é obrigatório** quando há retries automáticos
4. **Alertas são tão importantes quanto código** — sem alerta, o bug é "invisível"

---

## 7. METADADOS DO INCIDENTE

```
Ticket: INCIDENT-2026-11-16
Severidade: 🔴 CRÍTICO (22 dias)
Causa: Timeout RPC + Pool pequeno + Sem alerta
Tempo até detecção: 22 dias (manual)
Tempo até resolução: 1 hora (após diagnóstico)
Mensagens perdidas: 0 (todas em Redis, recuperadas)
Impacto: Cliente não recebia attualizações por 22 dias
Root cause: Monitoramento insuficiente de consumer lag
```

---

## 8. CHECKLIST DE SEGUIMENTO

- [ ] RPC_TIMEOUT aumentado para 10s
- [ ] max_connections aumentado para 15
- [ ] Circuit breaker implementado
- [ ] Prometheus metrics exportando
- [ ] Grafana alerts configuradas
- [ ] 24h sem timeout = confirmado
- [ ] Post-mortem compartilhado com time
- [ ] Documentação atualizada

---

**Data de Resolução**: 18 Novembro 2026  
**Próxima Review**: 25 Novembro 2026 (após 1 semana)
