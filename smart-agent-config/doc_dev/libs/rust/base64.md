# base64

- **Versão Recomendada:** 0.22.1
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-01
- **Propósito no Projeto:** Codificação/decodificação Base64 do material criptográfico (ciphertext, nonce e tag do AES-256-GCM) armazenado no JSONB `api_keys` do `TenantConfig`.
- **Documentação Oficial:** [https://docs.rs/base64](https://docs.rs/base64)
- **Library ID (Context7):** `/marshallpierce/rust-base64`

---

## 1. Contexto e Uso no Projeto

O `CipherManager` (AES-256-GCM) produz bytes brutos de ciphertext, nonce e tag. Eles são guardados no banco como strings Base64 dentro do JSONB `api_keys`. A crate `base64` faz essa ponte.

### Features de Cargo

```toml
base64 = "0.22.1"
```

---

## 2. Guia de Uso Rápido

> [!IMPORTANT]
> **Breaking change (0.21+):** as funções globais `base64::encode()` / `base64::decode()` foram **removidas**. Use um `Engine` explícito (`engine::general_purpose::STANDARD`) e o trait `Engine`.

```rust
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};

// Encode (bytes -> String)
let nonce_b64: String = BASE64.encode(&nonce_bytes);

// Decode (String -> Vec<u8>)
let nonce_bytes: Vec<u8> = BASE64
    .decode(nonce_b64)
    .map_err(|_| "Nonce inválido (Base64)")?;
```

- Importe o trait com `Engine as _` para habilitar os métodos `.encode()`/`.decode()`.
- `STANDARD` usa o alfabeto padrão com padding `=`. Para a `ENCRYPTION_KEY` em Base64, use o mesmo engine ao decodificar.

---

## 3. Histórico de Atualizações

- **2026-06-01:** Documento criado durante a reestruturação do plano `infrastructure-postgres`. Registrada a remoção das funções globais `encode`/`decode` (API atual exige `Engine`).
