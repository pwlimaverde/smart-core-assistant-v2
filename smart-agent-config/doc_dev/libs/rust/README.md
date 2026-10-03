# Bibliotecas Rust

Documentação centralizada das bibliotecas Rust utilizadas no **Smart Core Assistant v2**.

## Índice de Bibliotecas

| Biblioteca | Versão | Status | Propósito |
|-----------|--------|--------|----------|
| [Tonic](./tonic.md) | 0.14.6 | ✅ ATUALIZADA | Servidor gRPC com interceptor JWT, autenticação/autorização, e server streaming |
| [Tonic-Build](./tonic-build.md) | 0.14.6 | ✅ ATUALIZADA | Compilação de `.proto` → stubs gRPC em `build.rs` (protoc embutido) |
| [Tonic-Web](./tonic-web.md) | 0.12 | ✅ ATUALIZADA | Tradução gRPC-Web para clientes web/Flutter Web (HTTP/1.1) |
| [Tokio-Util](./tokio-util.md) | 0.7.12 | ✅ ATUALIZADA | Codecs para streaming, compat layer com futures, utilitários de I/O assíncrono |
| [Tower-HTTP](./tower-http.md) | 0.5.x | ✅ ATUALIZADA | Middlewares HTTP para servir arquivos, CORS, compressão, tracing com Tower/Axum |
| [aws-sdk-s3](./aws_sdk_s3.md) | 1.135.0 | ✅ ATUALIZADA | Cliente S3-compatible (MinIO dev / Cloudflare R2 prod) da crate `infrastructure_storage` |

## Instruções de Uso

Para utilizar qualquer uma destas bibliotecas, consulte o arquivo `.md` correspondente:

1. **Metadados iniciais:** Versão recomendada, status de atualização, última verificação, propósito no projeto
2. **Matriz de compatibilidade:** Versões esperadas dos crates dependentes
3. **Guia de uso rápido:** Exemplos compiláveis e padrões do projeto
4. **Histórico de atualizações:** Registro de mudanças e datas

## Última Atualização

- **Data:** 2026-10-03
- **Atualizações:** Adicionado tokio-util.md com documentação de codecs (Framed, UdpFramed), AsyncReadExt/AsyncWriteExt, compat layer para futures, utilitários de I/O. Adicionado tower-http.md com documentação de ServeDir/ServeFile (file serving), CorsLayer (CORS), CompressionLayer (compressão), TraceLayer (tracing/logging). Atualizado README.
