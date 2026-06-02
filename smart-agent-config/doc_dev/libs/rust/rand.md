# rand / OsRng e Geração Segura de Bytes

- **Versão Recomendada:** 0.10 (fevereiro de 2026 — última estável)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-02
- **Propósito no Projeto:** Geração criptograficamente segura de bytes para os Refresh Tokens opacos (32 bytes → base64url).
- **Documentação Oficial:** https://docs.rs/rand
- **Library ID (Context7):** `/rust-random/rand`

## Nota Importante: SysRng vs OsRng

Na versão 0.10 do `rand`, não existe mais `OsRng` como tipo separado. O equivalente moderno é **`SysRng`**, que oferece acesso direto à entropia do sistema operacional via crate `getrandom`.

### Para Refresh Tokens: Use `SysRng` (Direto do SO)

Se você precisa de bytes aleatórios **criptograficamente seguros** diretamente do SO:

```rust
use rand::rngs::SysRng;
use rand::TryRng;

fn generate_refresh_token() -> Result<[u8; 32], Box<dyn std::error::Error>> {
    let mut buf = [0u8; 32];
    SysRng.try_fill_bytes(&mut buf)?;
    // Encode to base64url
    Ok(buf)
}
```

**Características:**
- Stateless (sem estado)
- Acessa o SO diretamente (`/dev/urandom` no Linux, `CryptGenRandom` no Windows)
- Sem buffer/cache (cada chamada traz entropia fresca)
- Falha explícita via `Result` se o SO não disponibilizar randomness

## Alternativa: StdRng (CSPRNG Seeded)

Para maior performance (se você gera vários tokens em sequência), use `StdRng` seeded do SO:

```rust
use rand::rngs::StdRng;
use rand::SeedableRng;

fn generate_refresh_tokens(count: usize) -> Result<Vec<[u8; 32]>, Box<dyn std::error::Error>> {
    // Seed uma vez do SO
    let mut rng = StdRng::from_rng(rand::rngs::SysRng)?;
    
    // Gere múltiplos tokens rapidamente
    let tokens: Vec<[u8; 32]> = (0..count)
        .map(|_| rng.random())
        .collect();
    
    Ok(tokens)
}
```

**Características:**
- ChaCha12 CSPRNG (criptograficamente seguro)
- Implementa `CryptoRng` (marcado como seguro)
- Performance superior para múltiplos valores
- Seed vem do SO via `SysRng`

## Guia de Uso Rápido

### 1. Adicionar ao Cargo.toml

```toml
[dependencies]
rand = "0.10"
```

As features padrão já incluem `sys_rng` (necessária para `SysRng`).

### 2. Gerar 32 bytes seguros

```rust
use rand::rngs::SysRng;
use rand::TryRng;

let mut bytes = [0u8; 32];
SysRng.try_fill_bytes(&mut bytes)?;
```

### 3. Converter para base64url

```rust
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};

let token = URL_SAFE_NO_PAD.encode(bytes);
```

## Comparação: SysRng vs StdRng

| Aspecto | SysRng | StdRng |
|---------|--------|--------|
| **Fonte** | OS direto | OS (para seed) |
| **Algoritmo** | Nenhum (passthrough) | ChaCha12 |
| **Segurança** | ✅ Criptograficamente seguro | ✅ CryptoRng |
| **Performance** | Mais lenta (IO do SO) | Mais rápida |
| **Use case** | Tokens únicos, chaves | Múltiplos valores |
| **Falha** | `Result` (explícita) | Panics em seed |

## Nota: Não use ThreadRng para Tokens

`ThreadRng` (via `rand::rng()`) é conveniente mas **NÃO é adequado para tokens sensíveis** pois:
- Pode não ter entropy suficiente entre reseeds
- Reseeds são previsíveis em certos contextos

Sempre prefira `SysRng` ou `StdRng` com seed do `SysRng` para refresh tokens.
