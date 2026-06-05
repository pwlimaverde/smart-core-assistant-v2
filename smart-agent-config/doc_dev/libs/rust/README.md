# Bibliotecas Rust

Documentação centralizada das bibliotecas Rust utilizadas no **Smart Core Assistant v2**.

## Índice de Bibliotecas

| Biblioteca | Versão | Status | Propósito |
|-----------|--------|--------|----------|
| [Tonic](./tonic.md) | 0.14.6 | ✅ ATUALIZADA | Servidor gRPC com interceptor JWT, autenticação/autorização, e server streaming |
| [Tonic-Build](./tonic-build.md) | 0.14.6 | ✅ ATUALIZADA | Compilação de `.proto` → stubs gRPC em `build.rs` (protoc embutido) |
| [Tonic-Web](./tonic-web.md) | 0.12 | ✅ ATUALIZADA | Tradução gRPC-Web para clientes web/Flutter Web (HTTP/1.1) |

## Instruções de Uso

Para utilizar qualquer uma destas bibliotecas, consulte o arquivo `.md` correspondente:

1. **Metadados iniciais:** Versão recomendada, status de atualização, última verificação, propósito no projeto
2. **Matriz de compatibilidade:** Versões esperadas dos crates dependentes
3. **Guia de uso rápido:** Exemplos compiláveis e padrões do projeto
4. **Histórico de atualizações:** Registro de mudanças e datas

## Última Atualização

- **Data:** 2026-06-05
- **Atualizações:** Criado tonic-build.md com documentação completa do compiler (build.rs, protoc embutido, breaking changes 0.12→0.14, integração com projeto). Atualizado README.
