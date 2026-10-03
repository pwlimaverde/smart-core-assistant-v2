# Tokio-Util

- **Versão Recomendada:** 0.7.12
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-10-03
- **Propósito no Projeto:** Utilitários assíncronos do Tokio, incluindo codecs para streaming, camada de compatibilidade com I/O padrão, utilitários de arquivo e sincronização primitivos.
- **Documentação Oficial:** [https://docs.rs/tokio-util/latest/tokio_util/](https://docs.rs/tokio-util/latest/tokio_util/)
- **Library ID Context7:** `/websites/rs_tokio-util` (Reputação: High, Score: 87.61)

---

## 1. Contexto e Uso no Projeto

O backend do Smart Core Assistant v2 utiliza `tokio-util` para complementar o runtime Tokio em três áreas principais:

1. **I/O com Frames (Codecs):** Processamento de dados estruturados em fluxos assíncronos (ex: WebSocket, protocolos customizados)
2. **Compatibilidade com Stdlib:** Adaptação entre `tokio::io::AsyncRead/Write` e `futures::io::AsyncRead/Write` para interoperabilidade com bibliotecas que usam ecosistemas diferentes
3. **Utilidades de Arquivo:** Operações de I/O em arquivos e sincronização com bridges entre código síncrono e assíncrono

---

## 2. Recursos Principais

### 2.1 Codecs e Framing

**Propósito:** Camada de abstração para serialização/desserialização estruturada sobre I/O assíncrono.

**Traits Principais:**
- `Encoder<T>`: Codifica um tipo `T` em bytes, implementando `fn encode(&mut self, item: T, dst: &mut BytesMut) -> Result<(), Self::Error>`
- `Decoder`: Decodifica bytes em um tipo, implementando `fn decode(&mut self, src: &mut BytesMut) -> Result<Option<Self::Item>, Self::Error>`
- `Decoder::decode_eof(&mut self, src: &mut BytesMut) -> Result<Option<Self::Item>, Self::Error>` (chamado no EOF)

**Assinatura Principal:**
```rust
pub fn framed<T: AsyncRead + AsyncWrite + Sized>(self, io: T) -> Framed<T, Self>
where
    Self: Sized,
{
    Framed::new(io, self)
}
```

**Exemplo de Uso:**
```rust
use tokio::net::TcpStream;
use tokio_util::codec::{Framed, LinesCodec};

let socket = TcpStream::connect("127.0.0.1:8080").await?;
let mut framed = Framed::new(socket, LinesCodec::new());

// Ler linha por linha
while let Some(line) = framed.next().await {
    let line: String = line?;
    println!("Recebido: {}", line);
}

// Enviar linha
use futures::SinkExt;
framed.send("Hello, World!".to_string()).await?;
```

**Tipos Inclusos:**
- `LinesCodec`: Linhas delimitadas por `\n`
- `BytesCodec`: Bytes puros, sem framing
- `Framed<T, U>`: Implementa `Stream + Sink` combinados

**UdpFramed:** Para datagramas UDP:
```rust
pub struct UdpFramed<C, T = UdpSocket> { /* ... */ }
```
Oferece `Stream` e `Sink` unificados para `UdpSocket` com codecs.

---

### 2.2 Extensões de I/O Assíncrono (`AsyncReadExt`, `AsyncWriteExt`)

**Propósito:** Métodos auxiliares para `AsyncRead` e `AsyncWrite`, incluindo operações com tipos primitivos (inteiros, floats) em diferentes endianness.

**Assinaturas Principais:**

#### AsyncReadExt
```rust
pub trait AsyncReadExt: AsyncRead {
    fn read<'a>(&'a mut self, buf: &'a mut [u8]) -> Read<'a, Self>
    fn read_exact<'a>(&'a mut self, buf: &'a mut [u8]) -> ReadExact<'a, Self>
    fn read_buf<'a, B: BufMut>(&'a mut self, buf: &'a mut B) -> ReadBuf<'a, Self, B>
    fn read_u8(&mut self) -> ReadU8<&mut Self>
    fn read_u16(&mut self) -> ReadU16<&mut Self>
    fn read_u32(&mut self) -> ReadU32<&mut Self>
    fn read_u64(&mut self) -> ReadU64<&mut Self>
    fn read_u16_le(&mut self) -> ReadU16Le<&mut Self>
    fn read_i8(&mut self) -> ReadI8<&mut Self>
    // ... mais tipos primitivos
    fn chain<R: AsyncRead>(self, next: R) -> Chain<Self, R>
}
```

#### AsyncWriteExt
```rust
pub trait AsyncWriteExt: AsyncWrite {
    fn write<'a>(&'a mut self, src: &'a [u8]) -> Write<'a, Self>
    fn write_all<'a>(&'a mut self, src: &'a [u8]) -> WriteAll<'a, Self>
    fn write_buf<'a, B: Buf>(&'a mut self, src: &'a mut B) -> WriteBuf<'a, Self, B>
    fn write_vectored<'a>(&'a mut self, bufs: &'a [IoSlice<'_>]) -> WriteVectored<'a, Self>
    fn write_u8(&mut self, n: u8) -> WriteU8<&mut Self>
    fn write_u16(&mut self, n: u16) -> WriteU16<&mut Self>
    fn write_u32(&mut self, n: u32) -> WriteU32<&mut Self>
    fn write_u64(&mut self, n: u64) -> WriteU64<&mut Self>
    fn write_u16_le(&mut self, n: u16) -> WriteU16Le<&mut Self>
    fn write_i8(&mut self, n: i8) -> WriteI8<&mut Self>
    // ... mais tipos primitivos
}
```

**Exemplo de Uso:**
```rust
use tokio::io::AsyncReadExt;
use tokio::net::TcpStream;

let mut socket = TcpStream::connect("127.0.0.1:8080").await?;
let mut buffer = [0u8; 1024];
socket.read_exact(&mut buffer).await?;

let value = socket.read_u32().await?; // Lê u32 em big-endian
let value_le = socket.read_u32_le().await?; // Lê u32 em little-endian
```

---

### 2.3 Camada de Compatibilidade (`compat` module)

**Propósito:** Adapter para interoperabilidade entre `tokio::io` e `futures::io`.

**Recursos Disponíveis (requer feature `compat`):**

```rust
// Tokio → Futures
pub trait TokioAsyncReadCompatExt: AsyncRead + Sized {
    fn compat(self) -> Compat<Self>
}

pub trait TokioAsyncWriteCompatExt: AsyncWrite + Sized {
    fn compat_write(self) -> Compat<Self>
}

// Futures → Tokio
pub trait FuturesAsyncReadCompatExt: futures_io::AsyncRead + Sized {
    fn compat(self) -> Compat<Self>
}

pub trait FuturesAsyncWriteCompatExt: futures_io::AsyncWrite + Sized {
    fn compat(self) -> Compat<Self>
}
```

**Exemplo de Uso:**
```rust
use tokio_util::compat::TokioAsyncReadCompatExt;
use futures::io::AsyncReadExt as FuturesAsyncReadExt;

let tokio_reader = tokio::net::TcpStream::connect("127.0.0.1:8080").await?;

// Adapta Tokio AsyncRead para Futures AsyncRead
let mut compat_reader = tokio_reader.compat();

// Agora pode usar métodos do futures::io
let mut buffer = vec![0u8; 1024];
compat_reader.read_exact(&mut buffer).await?;
```

**Casos de Uso Comuns:**
- Integrar bibliotecas que dependem de `async-tungstenite` (que espera `futures::io::AsyncRead/Write`)
- Usar bibliotecas legadas baseadas no ecosistema `futures-rs` em código Tokio moderno
- Evitar reescrita desnecessária de I/O quando migrando entre runtimes

---

### 2.4 Utilitários de Arquivo e I/O

**Módulo `io::SyncIoBridge`:** Permite usar código assíncrono em contextos síncronos (ex: dentro de `tokio::task::spawn_blocking`).

```rust
use tokio::io::AsyncRead;
use tokio::task::spawn_blocking;

async fn process_sync_io<R: AsyncRead + Unpin + Send + 'static>(
    reader: R
) -> Result<Vec<u8>, std::io::Error> {
    let result = spawn_blocking(move || {
        let mut buffer = Vec::new();
        // Dentro de spawn_blocking, o reader é processado de forma síncrona
        // usando sua implementação de AsyncRead
        std::io::copy(&mut reader, &mut buffer)?;
        Ok::<_, std::io::Error>(buffer)
    })
    .await??;
    Ok(result)
}
```

**Módulo `io::simplex`:** Cria um canal full-duplex assíncrono em memória para testes ou processamento local.

```rust
use tokio_util::io::DuplexStream;

let (mut client, server) = tokio_util::io::duplex(64);
// `client` e `server` são AsyncRead + AsyncWrite
```

---

## 3. Breaking Changes e APIs Depreciadas

### Versão 0.7.x (Atual)
- **Nenhuma breaking change em 0.7.12** em relação a versões anteriores de 0.7
- Feature `compat` continua totalmente compatível
- Codec trait (`Encoder`, `Decoder`) sem mudanças de assinatura

### Histórico de Versões Relevantes
- **0.7.0 (2024):** Estabilização de `UdpFramed`, melhorias em `Framed`, suporte melhorado a `Stream` + `Sink`
- **0.6.x (Legado):** Versão anterior; se encontrar dependências em 0.6, considere atualizar para 0.7

### Compatibilidade com Tokio
- `tokio-util 0.7.x` é compatível com **Tokio 1.0+**
- Recomenda-se usar com Tokio 1.38+ (como documentado em `tokio.md`)

---

## 4. Padrões de Implementação no Projeto

### 4.1 Usando Codecs para Protocolos Customizados

Se o backend precisar implementar um protocolo customizado:

```rust
use tokio_util::codec::{Decoder, Encoder};
use bytes::BytesMut;

pub struct CustomMessageCodec;

impl Decoder for CustomMessageCodec {
    type Item = CustomMessage;
    type Error = std::io::Error;

    fn decode(&mut self, src: &mut BytesMut) -> Result<Option<Self::Item>, Self::Error> {
        if src.len() < 4 {
            return Ok(None); // Aguarda mais dados
        }
        let len = u32::from_be_bytes([src[0], src[1], src[2], src[3]]) as usize;
        if src.len() < 4 + len {
            return Ok(None);
        }
        let payload = src.split_to(4 + len);
        // Parse payload e retorne CustomMessage
        Ok(Some(CustomMessage { /* ... */ }))
    }
}

impl Encoder<CustomMessage> for CustomMessageCodec {
    type Error = std::io::Error;

    fn encode(&mut self, item: CustomMessage, dst: &mut BytesMut) -> Result<(), Self::Error> {
        let payload = serde_json::to_vec(&item)?;
        let len = payload.len() as u32;
        dst.extend_from_slice(&len.to_be_bytes());
        dst.extend_from_slice(&payload);
        Ok(())
    }
}
```

### 4.2 Interoperabilidade com Bibliotecas `futures`

Se integrar com `async-tungstenite` ou similares:

```rust
use tokio_util::compat::TokioAsyncReadCompatExt;

let tokio_socket = tokio::net::TcpStream::connect("127.0.0.1:8080").await?;
let compat_socket = tokio_socket.compat();

// Agora `compat_socket` implementa futures::io::AsyncRead + AsyncWrite
// e pode ser passado para async_tungstenite
```

---

## Histórico de Atualizações

- **2026-10-03:** Documentação inicial criada via Context7 MCP. Cobertura de: file I/O utilities, codec handling para streaming, compat layer com std I/O. Assinaturas atuais de `Framed::new()`, `AsyncReadExt`, `AsyncWriteExt`, traits `Encoder`/`Decoder`, `UdpFramed`. Confirmação de compatibilidade com Tokio 1.38. Nenhuma breaking change identificada em 0.7.12. Documentação oficial: https://docs.rs/tokio-util/latest/tokio_util/
