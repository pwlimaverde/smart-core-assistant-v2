# Arquitetura Técnica — Painel Kanban & Chat de Atendimento (WhatsApp)

> **Stack Principal:** Dioxus (Fullstack Rust) · gRPC · Docker (Rust & Python)
> **Data:** Junho de 2026

---

## Índice

1. [Introdução e Requisitos Core](#1-introdução-e-requisitos-core)
2. [Arquitetura de Rede e Topologia com Docker](#2-arquitetura-de-rede-e-topologia-com-docker)
3. [Contrato de Dados — `atendimento.proto`](#3-contrato-de-dados--atendimentoproto)
4. [Camada de Interface Unificada (Dioxus + WASM / Windows)](#4-camada-de-interface-unificada-dioxus--wasm--windows)
5. [Servidor Central — Rust / Axum + Tonic](#5-servidor-central--rust--axum--tonic)
6. [Orquestração Multi-Serviços — `docker-compose.yml`](#6-orquestração-multi-serviços--docker-composeyml)
7. [Plano de Execução e Roadmap](#7-plano-de-execução-e-roadmap)

---

## 1. Introdução e Requisitos Core

Este documento estabelece as diretrizes de engenharia para o sistema de atendimento baseado em cards e chat em tempo real, estruturado em torno de três pilares fundamentais:

| Pilar | Descrição |
|---|---|
| **Codebase Único de Interface** | O mesmo código-fonte em Rust gerencia a aplicação nativa Windows e a aplicação Web |
| **Contratos Estritos (gRPC)** | Eliminação de APIs REST e tipagem fraca (JSON manual) em favor de comunicação binária auto-gerada |
| **Eficiência de Baixo Nível** | Rust no servidor e no cliente para latência mínima, previsível e consumo de memória drasticamente menor que soluções baseadas em Electron |

---

## 2. Arquitetura de Rede e Topologia com Docker

O ecossistema é conteinerizado via Docker para isolar os serviços de backend. As pontas de consumo (UI Windows e UI Web) se conectam via **gRPC nativo** e **gRPC-Web**, respectivamente.

### Diagrama de Topologia

```
[ FRONTEND UNIFICADO: DIOXUS ]
       │
       ├─ (Windows Nativo) ───> [ gRPC Puro / HTTP/2 (Porta 50051) ] ──────────┐
       │                                                                         ▼
       └─ (Web / WASM) ────────> [ gRPC-Web / HTTP/1.1-2 (Porta 50051) ] ──> [ SERVIDOR CENTRAL ]
                                                                                 (Rust / Axum-Tonic)
                                                                                       │
                                                                                 (gRPC Interno / 50052)
                                                                                       ▼
                                                                             [ ORQUESTRADOR IA ]
                                                                              (Python / Agentes)
```

### Fluxo de Comunicação Interno

```
1. ENTRADA       →  Webhook do WhatsApp envia mensagem ao Servidor Central (Rust)
2. PROC. DE IA   →  Servidor Rust dispara chamada gRPC interna ao Orquestrador Python
                    com o histórico recente; Python executa os agentes e retorna
                    a resposta de forma síncrona/binária
3. TRANSMISSÃO   →  Servidor Rust propaga a alteração para a UI (Windows e Web)
                    via gRPC Server Streaming
```

---

## 3. Contrato de Dados — `atendimento.proto`

> ⚠️ **Este arquivo é a única fonte de verdade para toda a estrutura de dados do sistema.**
> Qualquer alteração no fluxo de dados deve ser iniciada aqui.

### Serviços Definidos

| RPC | Entrada | Saída | Tipo |
|---|---|---|---|
| `ObterCardsKanban` | `KanbanRequest` | `KanbanResponse` | Unário |
| `MoverCard` | `MoverCardRequest` | `MoverCardResponse` | Unário |
| `ObterHistoricoChat` | `ChatRequest` | `ChatResponse` | Unário |
| `EnviarMensagem` | `MensagemRequest` | `MensagemResponse` | Unário |
| `StreamAtendimentos` | `StreamRequest` | `stream EventoAtendimento` | **Server Streaming** |

### Valores Enumerados (Campos de Status)

| Campo | Valores Aceitos |
|---|---|
| `CardKanban.coluna_status` | `"novo"` · `"em_atendimento"` · `"finalizado"` |
| `Mensagem.remetente` | `"cliente"` · `"agente"` · `"ia"` |
| `EventoAtendimento.tipo` | `"NOVA_MENSAGEM"` · `"CARD_MOVIDO"` · `"NOVO_ATENDIMENTO"` |

### Arquivo Completo

```protobuf
syntax = "proto3";

package atendimento;

service AtendimentoService {
  // Fluxo do Painel Kanban
  rpc ObterCardsKanban (KanbanRequest) returns (KanbanResponse);
  rpc MoverCard (MoverCardRequest) returns (MoverCardResponse);

  // Fluxo do Chat Lateral (WhatsApp)
  rpc ObterHistoricoChat (ChatRequest) returns (ChatResponse);
  rpc EnviarMensagem (MensagemRequest) returns (MensagemResponse);

  // Sincronização em Tempo Real (Server Streaming)
  rpc StreamAtendimentos (StreamRequest) returns (stream EventoAtendimento);
}

message KanbanRequest {}

message CardKanban {
  string id = 1;
  string cliente_nome = 2;
  string ultima_mensagem = 3;
  string coluna_status = 4; // "novo" | "em_atendimento" | "finalizado"
  int64  timestamp = 5;
}

message KanbanResponse {
  repeated CardKanban cards = 1;
}

message MoverCardRequest {
  string card_id   = 1;
  string nova_coluna = 2;
}

message MoverCardResponse {
  bool sucesso = 1;
}

message ChatRequest {
  string atendimento_id = 1;
}

message Mensagem {
  string id        = 1;
  string texto     = 2;
  string remetente = 3; // "cliente" | "agente" | "ia"
  int64  timestamp = 4;
}

message ChatResponse {
  repeated Mensagem mensagens = 1;
}

message MensagemRequest {
  string atendimento_id = 1;
  string texto          = 2;
}

message MensagemResponse {
  bool enviado = 1;
}

message StreamRequest {
  string token_autenticacao = 1;
}

message EventoAtendimento {
  string tipo      = 1; // "NOVA_MENSAGEM" | "CARD_MOVIDO" | "NOVO_ATENDIMENTO"
  string dados_json = 2;
}
```

---

## 4. Camada de Interface Unificada (Dioxus + WASM / Windows)

A lógica de rede é escrita uma única vez usando **compilação condicional nativa do Rust**. A interface gráfica permanece intacta; apenas o driver de transporte é alternado em tempo de compilação.

### `src/network.rs` — Cliente gRPC Adaptativo

```rust
use tonic::transport::Channel;
use crate::atendimento::atendimento_service_client::AtendimentoServiceClient;

// ── TARGET: WEB (WebAssembly) ────────────────────────────────────────────────
#[cfg(target_arch = "wasm32")]
pub async fn criar_cliente_grpc() -> AtendimentoServiceClient<Channel> {
    use tonic_web_wasm::client::Client;

    // Transforma chamadas gRPC nativas em gRPC-Web (HTTP/1.1 envelopado) automaticamente
    let cliente_web = Client::new("https://api.seu-sistema.com".to_string());
    let canal = Channel::from_static("https://api.seu-sistema.com").connect_lazy();

    AtendimentoServiceClient::with_origin(canal, "https://api.seu-sistema.com".parse().unwrap())
}

// ── TARGET: DESKTOP (Windows Nativo) ────────────────────────────────────────
#[cfg(not(target_arch = "wasm32"))]
pub async fn criar_cliente_grpc() -> AtendimentoServiceClient<Channel> {
    // Canal HTTP/2 puro de ultra-alta performance direto para o Docker
    let canal = Channel::from_static("https://api.seu-sistema.com")
        .connect()
        .await
        .expect("Erro crítico: Servidor gRPC inacessível pelo Windows.");

    AtendimentoServiceClient::new(canal)
}
```

### `src/components/kanban.rs` — Componente Visual Unificado

Contém o **Painel Kanban** e o **modal reativo de chat**, reativos via Signals do Dioxus 0.5+.

```rust
use dioxus::prelude::*;
use crate::network::criar_cliente_grpc;
use crate::atendimento::KanbanRequest;

#[component]
pub fn PainelKanban() -> Element {
    // Estados Reativos Globais (Signals do Dioxus 0.5+)
    let mut cards                  = use_signal(|| vec![]);
    let mut chat_aberto            = use_signal(|| false);
    let mut atendimento_selecionado = use_signal(|| String::new());

    // Carregamento assíncrono multiplataforma via gRPC
    let _ = use_resource(move || async move {
        let mut cliente = criar_cliente_grpc().await;
        if let Ok(resposta) = cliente.obter_cards_kanban(KanbanRequest {}).await {
            cards.set(resposta.into_inner().cards);
        }
    });

    rsx! {
        div { class: "flex h-screen w-screen overflow-hidden bg-slate-900 text-white font-sans",

            // ── Colunas do Painel Kanban ──────────────────────────────────────
            div { class: "flex flex-1 p-6 space-x-4 overflow-x-auto",
                for card in cards.read().iter() {
                    div {
                        class: "bg-slate-800 p-4 rounded-lg shadow-md cursor-pointer hover:bg-slate-700 min-w-[280px] h-fit",
                        onclick: move |_| {
                            atendimento_selecionado.set(card.id.clone());
                            chat_aberto.set(true);
                        },
                        h3 { class: "font-bold text-lg text-emerald-400", "{card.cliente_nome}" }
                        p  { class: "text-sm text-slate-300 truncate mt-1", "{card.ultima_mensagem}" }
                        span { class: "text-xs bg-slate-900 px-2 py-1 rounded text-slate-400 mt-2 inline-block",
                            "ID: {card.id}"
                        }
                    }
                }
            }

            // ── Modal de Atendimento Lateral (Chat WhatsApp) ─────────────────
            if chat_aberto() {
                div { class: "w-96 bg-slate-950 border-l border-slate-800 flex flex-col justify-between p-4 shadow-2xl",

                    // Header
                    div { class: "flex justify-between items-center border-b border-slate-800 pb-3",
                        div {
                            h2 { class: "text-lg font-bold text-white", "Chat de Atendimento" }
                            p  { class: "text-xs text-slate-400", "ID: {atendimento_selecionado}" }
                        }
                        button {
                            class: "text-slate-400 hover:text-red-400 text-sm font-semibold transition-colors",
                            onclick: move |_| chat_aberto.set(false),
                            "[ Fechar ]"
                        }
                    }

                    // Corpo de Mensagens
                    div { class: "flex-1 overflow-y-auto my-4 space-y-3 pr-2",
                        // Espaço reservado para renderização do histórico via stream
                    }

                    // Input e Ações
                    div { class: "flex flex-col space-y-2 border-t border-slate-800 pt-3",
                        input {
                            class: "w-full p-2.5 bg-slate-800 border border-slate-700 rounded text-white focus:outline-none focus:border-emerald-500 text-sm",
                            placeholder: "Digite uma mensagem..."
                        }
                        button {
                            class: "w-full bg-emerald-600 py-2 rounded text-sm font-bold hover:bg-emerald-500 active:bg-emerald-700 transition-colors shadow",
                            "Enviar via WhatsApp"
                        }
                    }
                }
            }
        }
    }
}
```

---

## 5. Servidor Central — Rust / Axum + Tonic

Configurado com camada de compatibilidade **híbrida**: aceita tanto gRPC puro (Windows/sistemas) quanto gRPC-Web (sandbox do navegador/WASM).

### `src/main.rs`

```rust
use tonic::transport::Server;
use tonic_web::GrpcWebLayer;
use tower_http::cors::{CorsLayer, Any};
use crate::atendimento::atendimento_service_server::AtendimentoServiceServer;

mod atendimento_impl; // Regras de negócio e persistência

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let endereco          = "0.0.0.0:50051".parse()?;
    let implementação_servico = atendimento_impl::MeuAtendimentoService::default();

    // CORS — necessário para requisições vindas do Navegador (WASM)
    let cors_layer = CorsLayer::new()
        .allow_origin(Any)
        .allow_headers(Any)
        .allow_methods(Any);

    println!("[INFO] Servidor Core gRPC ativo na porta 50051...");

    Server::builder()
        .accept_http1(true)          // Suporte a gRPC-Web sobre HTTP/1.1
        .layer(cors_layer)
        .layer(GrpcWebLayer::new())  // Middleware de tradução gRPC-Web
        .add_service(AtendimentoServiceServer::new(implementação_servico))
        .serve(endereco)
        .await?;

    Ok(())
}
```

> **Nota:** `accept_http1(true)` é obrigatório para suportar conexões gRPC-Web originadas do browser.

---

## 6. Orquestração Multi-Serviços — `docker-compose.yml`

Mapeamento de infraestrutura local/produção com isolamento de rede entre banco de dados, servidor Rust e agentes Python.

```yaml
version: '3.8'

services:

  database:
    image: postgres:15-alpine
    container_name: sistema_db
    environment:
      POSTGRES_DB:       sistema_atendimento
      POSTGRES_PASSWORD: senha_segura_db_2026
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  server-rust:
    build:
      context:    ./server-rust
      dockerfile: Dockerfile
    container_name: core_backend_rust
    ports:
      - "50051:50051"   # Porta unificada: gRPC Nativo + gRPC-Web
    environment:
      - DATABASE_URL=postgres://postgres:senha_segura_db_2026@database:5432/sistema_atendimento
      - PYTHON_AGENT_URL=http://agent-python:50052
    depends_on:
      - database

  agent-python:
    build:
      context:    ./agent-python
      dockerfile: Dockerfile
    container_name: ia_orquestrador_python
    ports:
      - "50052:50052"   # Comunicação interna gRPC Rust → Python
    depends_on:
      - server-rust

volumes:
  postgres_data:
```

### Mapa de Portas

| Serviço | Porta | Protocolo | Descrição |
|---|---|---|---|
| `server-rust` | `50051` | gRPC + gRPC-Web | Ponto de entrada unificado para UI |
| `agent-python` | `50052` | gRPC (interno) | Comunicação interna Rust → Python |
| `database` | `5432` | TCP/PostgreSQL | Banco de dados relacional |

---

## 7. Plano de Execução e Roadmap

> Siga o cronograma estritamente para evitar erros de compilação cruzada no Dioxus.

### Fase 1 — Validação do Contrato *(Sem UI)*

- [ ] Escrever o arquivo `atendimento.proto` final
- [ ] Rodar o compilador `protoc` no Rust e no Python
- [ ] Verificar ausência de conflitos nas estruturas de dados e classes geradas

### Fase 2 — Mock de Dados no Backend

- [ ] Subir o Docker com o servidor Rust instanciando a estrutura Tonic
- [ ] Implementar métodos gRPC retornando **dados estáticos** (Mocks)
- [ ] Validar integridade da rede e das rotas

### Fase 3 — Ambiente Multi-Target Dioxus

- [ ] Criar a aplicação base no Dioxus
- [ ] Configurar `Cargo.toml` adicionando dependências WASM (`tonic-web-wasm`) sob flag `target web`
- [ ] Executar `cargo run` (janela Windows) e `dx serve` (versão Web)
- [ ] Confirmar que ambas as telas leem e exibem o mesmo dado estático da Fase 2

### Fase 4 — Integração de Inteligência Artificial

- [ ] Desenvolver o servidor Python com o framework de agentes
- [ ] Conectar a chamada interna gRPC Rust → Python
- [ ] Validar recebimento de respostas em formato binário

### Fase 5 — UI Avançada e Produção

- [ ] Implementar o design do Kanban com Tailwind CSS no Dioxus
- [ ] Substituir polling por **gRPC Server Streaming** para mensagens em tempo real
- [ ] Compilar binários otimizados: `cargo build --release`

---

*Documento gerado em Junho de 2026 · Projeto Smart Core Assistant*
