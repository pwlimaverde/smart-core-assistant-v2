# Arquitetura de Comunicação e Escalabilidade de Microsserviços

> **Escopo:** Unix Sockets · FlatBuffers · gRPC
> **Data:** Junho de 2026

---

## Índice

1. [Escalabilidade de Infraestrutura](#1-escalabilidade-de-infraestrutura)
2. [Abordagens de Comunicação](#2-abordagens-de-comunicação)
   - [A — Unix Domain Sockets](#abordagem-a--unix-domain-sockets-ipc)
   - [B — FlatBuffers](#abordagem-b--flatbuffers-zero-copy)
   - [C — gRPC](#abordagem-c--grpc)
3. [Suporte por Linguagem](#3-suporte-por-linguagem)
4. [Comparativo de Performance](#4-comparativo-de-performance)
5. [Estratégia de Adoção Progressiva](#5-estratégia-de-adoção-progressiva)

---

## 1. Escalabilidade de Infraestrutura

A decisão de **onde os módulos rodam** é o que dita qual protocolo de comunicação é ideal. Existem dois eixos:

| Eixo | Topologia | Gargalo Principal | Estratégia |
|---|---|---|---|
| **Vertical** | Mesma VM / mesmo host Docker | Ciclos de CPU desperdiçados | Evitar overhead de rede desnecessário |
| **Horizontal** | VMs distintas / nós de cluster | Latência e largura de banda da rede | Compactar os dados ao máximo |

---

## 2. Abordagens de Comunicação

### Abordagem A — Unix Domain Sockets (IPC)

**Foco:** máxima eficiência local — mesma máquina ou host Docker.

O sistema operacional ignora completamente a placa de rede e o TCP/IP. Em vez disso, cria um arquivo especial no sistema de arquivos. Quando um módulo envia dados para outro, os bytes são copiados **diretamente de um bloco da RAM para outro**, sem sair do kernel.

```
[ Módulo Rust ]                [ Módulo Python ]
      │                               │
      └──── /var/run/app.sock ────────┘
            (cópia direta na RAM)
            sem TCP, sem rede
```

**Características:**

- Transferências de **gigabytes por segundo** com uso quase nulo de CPU
- Sem overhead de protocolo de rede (TCP handshake, checksums, etc.)
- Restrito à **mesma máquina** — não funciona entre VMs distintas
- Requer gerenciamento do arquivo de socket no filesystem

**Quando usar:** enquanto o servidor Rust e o orquestrador Python compartilharem o mesmo host Docker, o Unix Socket é o transporte mais eficiente disponível — independentemente do protocolo de mensagens utilizado acima dele.

---

### Abordagem B — FlatBuffers (Zero-Copy)

**Foco:** máxima eficiência de CPU via rede — entre VMs separadas.

Protocolos tradicionais exigem loops de CPU para empacotar (*serializar*) e desempacotar (*deserializar*) mensagens. O FlatBuffers resolve isso com o conceito de **Zero-Copy**: a estrutura dos dados gravados na rede é **idêntica** à forma como eles se organizam na memória RAM. O receptor lê os dados diretamente do buffer de rede usando ponteiros e offsets, sem alocar memória nova nem gastar ciclos de CPU.

```
Serialização tradicional (Protobuf, JSON):
  objeto → [CPU: pack] → bytes → rede → [CPU: unpack] → objeto

FlatBuffers (Zero-Copy):
  objeto → bytes → rede → bytes (leitura direta por offset)
                                  ↑ sem etapa de unpack
```

**Características:**

- Latência de deserialização praticamente zero
- Ideal para payloads grandes (logs, histórico de mensagens, vetores de IA)
- Complexidade de código maior — manipulação manual de buffers
- Não possui streaming nativo nem geração automática de cliente/servidor

**Quando usar:** quando o módulo de agentes de IA em Python for isolado em uma VM dedicada com GPU e precisar trocar volumes massivos de dados com o servidor Rust sem que a rede ou a CPU se tornem gargalo.

---

### Abordagem C — gRPC

**Foco:** padronização, resiliência e contratos rígidos — entre VMs separadas ou localmente.

Baseia-se em **HTTP/2** para manter conexões persistentemente abertas e multiplexadas — centenas de requisições trafegando simultaneamente na mesma conexão TCP. Usa **Protocol Buffers (Protobuf)** como formato de dados, que serializa em binário compacto com custo moderado de CPU. O código de cliente e servidor é **gerado automaticamente** a partir do arquivo `.proto`.

```
Cliente                    Servidor
  │── RPC (stream ou unário) ──>│
  │                              │  HTTP/2 multiplexado
  │<── resposta/stream ──────────│
  │── outro RPC simultâneo ─────>│  mesmo canal TCP
  │<── resposta ─────────────────│
```

**Características:**

- Contrato `.proto` como fonte única de verdade — quebra em build, não em produção
- Streaming nativo: unário, server streaming, client streaming e bidirecional
- Reconexão, keepalive e timeouts embutidos no protocolo
- Geração automática de código para todas as linguagens
- Custo de CPU para serialização/deserialização Protobuf (moderado)

**Quando usar:** como espinha dorsal de toda a comunicação entre serviços — validações, chamadas síncronas, streaming de eventos em tempo real e controle de fluxo entre módulos.

---

## 3. Suporte por Linguagem

Todas as abordagens possuem suporte oficial e maduro nas linguagens do ecossistema, permitindo integração 100% poliglota:

| Tecnologia | C# (.NET) | C++ | Rust | Python |
|---|---|---|---|---|
| **Unix Sockets** | `System.Net.Sockets` | POSIX `sys/socket.h` | `std::os::unix::net` | módulo `socket` |
| **FlatBuffers** | Gerador oficial `flatc` | Linguagem de origem do projeto | Crate oficial `flatbuffers` | Suporte nativo + aceleração via NumPy |
| **gRPC** | Desenvolvido e otimizado pela Microsoft | Nativo e robusto | Crate `tonic` | Biblioteca `grpcio` |

---

## 4. Comparativo de Performance

| Critério | Unix Domain Sockets | FlatBuffers | gRPC (Protobuf) |
|---|---|---|---|
| **Alvo geográfico** | Mesma máquina | VMs distintas | VMs distintas |
| **Velocidade relativa** | Absurda — velocidade da RAM | Altíssima — rede pura | Alta — limitada pela serialização |
| **Consumo de CPU** | Praticamente zero | Mínimo (Zero-Copy) | Moderado |
| **Complexidade de código** | Média | Alta — manipulação de buffers | Baixa — geração automática |
| **Contratos de dados** | Nenhum — bytes brutos | Schema via `.fbs` | Estrito via `.proto` |
| **Streaming nativo** | Manual — fluxo de bytes | Suporta estruturas complexas | Nativo — bidirecional |
| **Reconexão automática** | Não | Não | Sim |

---

## 5. Estratégia de Adoção Progressiva

A abordagem mais inteligente é adotar as tecnologias em camadas, conforme o sistema cresce:

### Camada 1 — Comando e Controle (hoje)

**Tecnologia:** gRPC sobre Unix Domain Socket

Enquanto o servidor Rust e o orquestrador Python rodarem no mesmo host Docker, configure o transporte do gRPC para usar um **Unix Domain Socket** em vez de uma porta TCP local. Você ganha a facilidade e os contratos do gRPC com a velocidade de cópia direta na RAM — o melhor dos dois mundos.

```
# Em vez de:
grpc://localhost:50052

# Usar:
grpc+unix:///var/run/atendimento/agent.sock
```

Cobre: login, permissões, chamadas síncronas, streaming de eventos em tempo real.

### Camada 2 — Escala Horizontal (quando necessário)

**Tecnologia:** gRPC sobre TCP/TLS entre VMs

Quando o sistema crescer e os módulos forem separados em VMs distintas, basta trocar o transporte do socket Unix por um endereço TCP — o código da aplicação não muda, apenas a configuração de conexão.

```
# Transição transparente para rede:
grpc://agent-python.interno:50052
```

### Camada 3 — Transferência Massiva de IA (se necessário)

**Tecnologia:** FlatBuffers para payloads pesados

Se o módulo de agentes de IA for isolado em uma VM dedicada com GPU e começar a trocar volumes massivos de dados (vetores de embeddings, históricos longos, batches de inferência), migrar esse tráfego específico para FlatBuffers elimina o gargalo de CPU na serialização sem mudar o restante da stack.

```
Tráfego leve (comandos, eventos)  → gRPC / Protobuf   (mantido)
Tráfego pesado (dados de IA)      → FlatBuffers        (adicionado)
```

---

### Resumo visual da estratégia

```
FASE ATUAL (mesma VM)
┌─────────────────────────────────────────┐
│  Flutter ──gRPC/TLS──> Rust             │
│                         │               │
│              gRPC over Unix Socket      │
│                         │               │
│                        Python (IA)      │
└─────────────────────────────────────────┘

FASE ESCALA HORIZONTAL (VMs separadas)
┌──────────────┐     gRPC/TLS     ┌───────────────┐
│  Flutter     │ ──────────────── │  Rust (VM 1)  │
└──────────────┘                  └───────┬───────┘
                                          │ gRPC/TLS ou FlatBuffers
                                  ┌───────▼───────┐
                                  │  Python (VM 2 │
                                  │  + GPU)       │
                                  └───────────────┘
```

---

*Documento gerado em Junho de 2026 · Projeto Smart Core Assistant*
