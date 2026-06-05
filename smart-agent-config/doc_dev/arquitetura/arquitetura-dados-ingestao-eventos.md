# Arquitetura de Dados — Ingestão, Eventos e Persistência

> **Escopo:** Fluxo de Ingestão · Transactional Outbox · Redis Dual-Role
> **Data:** Junho de 2026

---

## Índice

1. [Fluxo de Ingestão — Evento → Banco → Postgres/Redis](#1-fluxo-de-ingestão--evento--banco--postgresredis)
2. [Transactional Outbox Pattern](#2-transactional-outbox-pattern)
3. [Cenários Práticos de Registro de Eventos](#3-cenários-práticos-de-registro-de-eventos)
4. [O Papel Duplo do Redis](#4-o-papel-duplo-do-redis)
5. [Regra Estrutural — Resumo do Fluxo de Dados](#5-regra-estrutural--resumo-do-fluxo-de-dados)

---

## 1. Fluxo de Ingestão — Evento → Banco → Postgres/Redis

Quando o módulo de gravação recebe um evento da fila (vindo do WhatsApp ou de logs), ele precisa atualizar Postgres e Redis de forma segura e ordenada. O padrão utilizado é o **Write-Behind gerenciado pelo consumidor**:

```
[ Fila de Mensagens ]
  (Redpanda / RabbitMQ)
         │
         ▼ lote de eventos
[ Módulo Gravador (Rust) ]
         │
         ├─ 1. Abre transação ACID no Postgres
         │       └─ falhou? → rollback → evento volta para a fila
         │
         ├─ 2. Postgres confirmou? → atualiza chave no Redis
         │       └─ ou invalida a chave para forçar leitura fresca
         │
         └─ 3. Envia ACK ao Broker → mensagem sai da fila
```

### Etapas detalhadas

| Etapa | Ação | Garantia |
|---|---|---|
| **1. Leitura da fila** | Módulo Rust puxa um lote de eventos | Processamento em batch, menor overhead |
| **2. Transação ACID** | INSERT no Postgres dentro de uma transação | Falha → rollback → reprocessamento automático |
| **3. Atualização do cache** | Grava ou invalida a chave no Redis | Executado **somente** após confirmação do Postgres |
| **4. ACK** | Sinal de sucesso enviado ao Broker | Mensagem removida da fila definitivamente |

> **Regra crítica:** o Redis só é tocado **após** o Postgres confirmar o commit. Jamais o inverso — isso garantiria um cache inconsistente com o banco.

---

## 2. Transactional Outbox Pattern

O cenário inverso é o mais crítico: uma alteração ocorreu no Postgres — como o sistema notifica de forma **assíncrona e confiável** outros módulos (IA em Python, UI Web) sem perder o evento caso a rede oscile?

A solução é o **Transactional Outbox Pattern**.

### Como funciona

```
[ Operação de Negócio ]
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  TRANSAÇÃO ÚNICA NO POSTGRES                                │
│  1. INSERT INTO clientes (nome, telefone) VALUES (...)      │
│  2. INSERT INTO outbox   (topico, payload) VALUES (...)     │
└─────────────────────────────────────────────────────────────┘
         │ commit atômico — ou os dois salvam, ou os dois falham
         ▼
[ Tabela outbox atualizada ]
         │
         ├─ LISTEN/NOTIFY (gatilho nativo, sub-milissegundos) ──> [ Worker Relay (Rust) ]
         │                                                                    │
         └─ CDC / Debezium (alternativa para alta escala)                     ▼
                                                                    [ Message Broker ]
                                                                         │         │
                                                                         ▼         ▼
                                                                 [ Agente IA ] [ UI Web ]
                                                                  (Python)     (Flutter)
```

### Etapas detalhadas

**1. Transação atômica**
A operação de negócio escreve na tabela principal (ex: `clientes`) e, dentro da **mesma transação**, insere uma linha na tabela `outbox` com o evento serializado:

```json
{ "evento": "cliente_criado", "id": 123 }
```

É impossível o dado ser salvo sem o evento ser registrado — ou os dois persistem, ou nenhum persiste.

**2. Worker Relay (o mensageiro)**
Um processo em segundo plano em Rust monitora a tabela `outbox`. Em vez de fazer `SELECT` a cada segundo (o que geraria gargalo), utiliza o recurso nativo do Postgres:

```sql
-- O Postgres avisa o worker em sub-milissegundos quando chega uma linha nova
LISTEN outbox_eventos;

-- Disparado pela trigger após o INSERT na tabela outbox
NOTIFY outbox_eventos, '{"id": 123}';
```

**3. Despacho e limpeza**
O worker lê o evento da `outbox`, envia ao Message Broker (ou Redis Streams) e marca o registro como processado:

```sql
UPDATE outbox SET processado_em = NOW() WHERE id = 123;
```

**4. Resiliência**
Se o Message Broker cair, o evento permanece na tabela `outbox` do Postgres aguardando o sistema se recuperar. **Zero perda de dados.**

### Quando usar CDC / Debezium

O `LISTEN/NOTIFY` cobre a maioria dos casos. O **Change Data Capture (CDC)** via Debezium é a alternativa para cenários de altíssima escala, onde o volume de eventos seria proibitivo para um worker Rust processar de forma síncrona, ou quando múltiplos sistemas externos precisam consumir as mudanças do banco de dados.

---

## 3. Cenários Práticos de Registro de Eventos

### Cenário A — Usuário cadastrou um cliente

**Caminho:** Outbox Pattern + Broker + Agente IA

```
Backend Rust
  → INSERT clientes + INSERT outbox (mesma transação)
  → Worker Relay detecta via LISTEN/NOTIFY
  → Envia evento ao Broker
  → Agente Python consome e cria perfil do cliente em segundo plano
```

O módulo de IA não bloqueia a operação de cadastro — é acionado de forma assíncrona e confiável após o commit.

---

### Cenário B — Usuário tentou acessar algo sem permissão

**Caminho:** Direto para Redis Streams (sem Outbox)

```
Módulo de Autenticação
  → Gera log de segurança
  → XADD direto no Redis Streams (fila de segurança)
  → Consumidor decide:
      ├─ Bloquear IP temporariamente no Redis
      └─ Registrar na tabela de auditoria do Postgres
```

Este evento **não altera estado de negócio** — não precisa da garantia transacional do Outbox. O Redis Streams é suficiente e mais eficiente para eventos de log e auditoria.

---

### Regra para decidir o caminho

| Tipo de evento | Caminho correto |
|---|---|
| Altera dado de negócio (Kanban, mensagens, clientes) | Postgres → Outbox → Broker |
| Log, auditoria, evento temporário | Direto no Redis Streams |
| Cache de sessão / token JWT | Redis chave-valor simples |

---

## 4. O Papel Duplo do Redis

O Redis atua em **duas frentes independentes** na arquitetura:

### Redis como Cache (Cache-Aside)

Armazena dados de acesso frequente com TTL definido, evitando leituras repetidas no Postgres:

| Dado | Estratégia |
|---|---|
| Sessões de login | Chave com TTL (ex: `session:{user_id}`) |
| Permissões de JWT | Chave com TTL curto para revogação rápida |
| Estado das janelas do Kanban | Chave temporária por colaborador |

---

### Redis como Broker de Eventos Leve (Redis Streams)

O Redis possui a estrutura **Streams** (`XADD` / `XREADGROUP`) que funciona como um broker de eventos durável com suporte a grupos de consumidores — múltiplos agentes Python podem dividir a carga de leitura dos eventos em paralelo.

```
Producer (Rust)              Redis Streams              Consumers (Python)
     │                                                         │
     │── XADD fila:seguranca ──────────────────────────────>   │
     │── XADD fila:logs ───────────────────────────────────>   │
     │                                                         │
     │                        XREADGROUP                       │
     │                   ┌────────────────┐                    │
     │                   │ Agente Python 1│ ──> processa msg 1 │
     │                   │ Agente Python 2│ ──> processa msg 2 │
     │                   └────────────────┘                    │
```

> **Vantagem para o início do projeto:** Redis Streams elimina a necessidade de subir um container pesado de Kafka ou Redpanda nas fases iniciais. A migração para Redpanda pode ser feita depois, sem alterar a lógica de negócio — apenas a configuração de conexão.

---

## 5. Regra Estrutural — Resumo do Fluxo de Dados

```
DADO CRÍTICO DE NEGÓCIO
(Kanban, mensagens recebidas, clientes)
         │
         ▼
  Gravação no Postgres
         │
         ▼
  Evento na tabela outbox (mesma transação)
         │
         ▼
  LISTEN/NOTIFY → Worker Relay (Rust)
         │
         ▼
  Message Broker → outros módulos

─────────────────────────────────────────────

DADO TEMPORÁRIO / LOG / EVENTO RÁPIDO
(tentativas de acesso, cache de tokens, auditoria)
         │
         ▼
  Redis Streams (XADD)  ou  Redis chave-valor
```

| Tipo de dado | Tecnologia | Justificativa |
|---|---|---|
| Negócio crítico | Postgres + Outbox + Broker | Durabilidade, ACID, zero perda |
| Cache de leitura rápida | Redis (chave-valor) | Latência sub-milissegundo |
| Eventos leves / logs | Redis Streams | Sem overhead transacional |
| Broker em produção | Redpanda / RabbitMQ | Escala horizontal, replay de eventos |

---

*Documento gerado em Junho de 2026 · Projeto Smart Core Assistant*
