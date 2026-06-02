# sha2

- **Versão Recomendada:** 0.10.x
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-02
- **Propósito no Projeto:** Hash SHA-256 dos Refresh Tokens antes de armazenar no Redis (nunca o token em claro).
- **Documentação Oficial:** https://docs.rs/sha2
- **Library ID (Context7):** `/rustcrypto/hashes`

---

## Guia de Uso Rápido

### 1. One-Shot Hashing (Digest)

Para hashing simples em uma única operação, use `Sha256::digest()`:

```rust
use sha2::{Sha256, Digest};

let token = "my_refresh_token_123";
let hash = Sha256::digest(token.as_bytes());
// hash é um GenericArray<u8, U32> (32 bytes)
```

**Características:**
- Função estática, não requer estado mutável
- Ideal para tokens curtos e únicos
- Consome os dados de entrada

---

### 2. Conversão para String Hexadecimal

Para armazenar no Redis, converta o hash para string hexadecimal usando `base16ct`:

```rust
use sha2::{Sha256, Digest};
use base16ct::lower;

let token = "my_refresh_token_123";
let hash = Sha256::digest(token.as_bytes());

// Converter para string hex (64 caracteres para SHA-256)
let hex_hash = lower::encode_string(&hash);
println!("Hash armazenado: {}", hex_hash);
// Exemplo output: b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
```

**Nota:** `base16ct::lower` produz hex em minúsculas. Use `base16ct::upper` para maiúsculas.

---

### 3. Usando a Trait Digest para Múltiplas Atualizações

Quando precisa acumular dados antes de finalizar:

```rust
use sha2::{Sha256, Digest};

let mut hasher = Sha256::new();
hasher.update(b"primeiro_dado");
hasher.update(b"segundo_dado");
let hash = hasher.finalize();
```

**Características:**
- `Digest` trait fornece `.update()` e `.finalize()`
- `.update()` pode ser chamado múltiplas vezes
- `.finalize()` consome o hasher e retorna o hash

---

### 4. Encadeamento (Chain Pattern)

Alternativa mais funcional:

```rust
use sha2::{Sha256, Digest};

let hash = Sha256::new()
    .chain_update(b"bloco1")
    .chain_update(b"bloco2")
    .finalize();
```

---

## Exemplo Completo: Hashing de Refresh Token para Redis

```rust
use sha2::{Sha256, Digest};
use base16ct::lower;

fn hash_refresh_token(token: &str) -> String {
    let hash = Sha256::digest(token.as_bytes());
    lower::encode_string(&hash)
}

fn main() {
    let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...";
    let hashed = hash_refresh_token(token);
    println!("Token original (NUNCA armazenar): {}", token);
    println!("Hash para Redis: {}", hashed);
    // Hash para Redis: 5d41402abc4b2a76b9719d911017c592a45a1e7e...
}
```

---

## Cargo.toml

```toml
[dependencies]
sha2 = "0.10"
base16ct = { version = "0.2", features = ["alloc"] }
```

---

## Notas de Implementação

1. **Não armazene tokens em claro no Redis** — sempre use o hash SHA-256
2. **Use `lower::encode_string()`** para produzir strings hex compatíveis com chaves Redis
3. **SHA-256 produz 64 caracteres hexadecimais** (32 bytes × 2)
4. **`Digest` trait é genérica** — funciona com qualquer algoritmo (SHA-1, SHA-512, etc.)
5. **Performance:** One-shot API (`Sha256::digest`) é tão eficiente quanto construir o hasher manualmente para dados únicos

---

## Referências

- [RustCrypto Hashes](https://github.com/rustcrypto/hashes) — implementação pura de Rust
- [base16ct docs](https://docs.rs/base16ct) — encoding para hexadecimal
- [Digest Trait](https://docs.rs/digest/latest/digest/trait.Digest.html) — trait padrão para funções de hash
