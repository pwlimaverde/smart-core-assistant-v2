# jsonwebtoken

- **Versão Recomendada:** 9.x
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-02
- **Propósito no Projeto:** Emissão e validação de Access Tokens JWT (HS256) para autenticação do runtime_api.
- **Documentação Oficial:** https://docs.rs/jsonwebtoken
- **Library ID (Context7):** `/keats/jsonwebtoken`

---

## Estrutura de Claims

A estrutura de Claims é um struct Serde-serializado que contém os campos padrão JWT:

```rust
#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    aud: String,         // Opcional. Audience (público alvo)
    exp: usize,          // Obrigatório. Expiration time (timestamp UTC)
    iat: usize,          // Opcional. Issued at (timestamp UTC)
    iss: String,         // Opcional. Issuer (emissor)
    nbf: usize,          // Opcional. Not Before (timestamp UTC)
    sub: String,         // Opcional. Subject (assunto/usuário)
}
```

**Nota:** `exp` é obrigatório por padrão, pois a validação de expiração é habilitada na `Validation` padrão.

---

## Encriptação e Assinatura de JWT

Função `encode()` assina um JWT com header, claims e chave:

```rust
use serde::{Serialize, Deserialize};
use jsonwebtoken::{encode, Header, EncodingKey, Algorithm};

#[derive(Serialize, Deserialize)]
struct Claims {
    sub: String,
    company: String,
    exp: u64,
}

let claims = Claims {
    sub: "user@example.com".to_owned(),
    company: "ACME".to_owned(),
    exp: 1_700_000_000,  // Timestamp Unix em segundos
};

let header = Header::new(Algorithm::HS256);
let key = EncodingKey::from_secret("my_secret_key".as_ref());
let token = encode(&header, &claims, &key)?;
// token é agora uma string JWT completa (3 partes separadas por .)
```

**Assinatura:**
```rust
pub fn encode(
    header: &Header,
    claims: &impl Serialize,
    key: &EncodingKey
) -> Result<String>
```

---

## Decodificação e Validação de JWT

Função `decode()` decodifica, verifica assinatura e valida claims:

```rust
use serde::{Serialize, Deserialize};
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm, TokenData};

#[derive(Serialize, Deserialize)]
struct Claims {
    sub: String,
    exp: u64,
}

let token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...";
let key = DecodingKey::from_secret("secret".as_ref());
let validation = Validation::new(Algorithm::HS256);

let token_data = decode::<Claims>(&token, &key, &validation)?;
println!("Subject: {}", token_data.claims.sub);
println!("Algorithm: {}", token_data.header.alg);
```

**Assinatura:**
```rust
pub fn decode<T: DeserializeOwned>(
    token: impl AsRef<[u8]>,
    key: &DecodingKey,
    validation: &Validation
) -> Result<TokenData<T>>
```

**Retorno:** `TokenData<T>` contém:
- `header: Header` — algoritmo, tipo (JWT)
- `claims: T` — claims decodificadas (estrutura genérica)

---

## Validação de Claims

Struct `Validation` configura regras de validação:

```rust
pub struct Validation {
    pub required_spec_claims: HashSet<String>,     // Claims obrigatórios
    pub leeway: u64,                               // Tolerância em segundos (padrão: 0)
    pub reject_tokens_expiring_in_less_than: u64,  // Rejeitar tokens vencendo em < N seg
    pub validate_exp: bool,                        // Validar expiração (padrão: true)
    pub validate_nbf: bool,                        // Validar "not before" (padrão: false)
    pub validate_aud: bool,                        // Validar audience (padrão: false)
    pub aud: Option<HashSet<String>>,              // Audiences aceitas
    pub iss: Option<HashSet<String>>,              // Issuers aceitas
    pub sub: Option<String>,                       // Subject esperado
    pub algorithms: Vec<Algorithm>,                // Algoritmos permitidos
    // validate_signature é privado
}
```

**Exemplo com validação customizada:**
```rust
use jsonwebtoken::{Validation, Algorithm};
use std::collections::HashSet;

let mut validation = Validation::new(Algorithm::HS256);
validation.set_audience(&["my_app"]);  // Validar audience
validation.set_issuer(&["my_issuer"]); // Validar issuer
validation.leeway = 10;                // Permitir 10 segundos de tolerância
validation.validate_exp = true;        // Validar expiração (padrão)

// Usar em decode:
let token_data = decode::<Claims>(&token, &key, &validation)?;
```

---

## Tratamento de Erros

Enum `ErrorKind` com variantes para cada tipo de erro:

| Erro | Descrição |
|------|-----------|
| `InvalidToken` | Token não tem 3 partes separadas por `.` |
| `InvalidAlgorithm` | Algoritmo no header não corresponde com a validação |
| `InvalidSignature` | Verificação de assinatura falhou |
| `ExpiredSignature` | Token expirou (timestamp `exp` ultrapassado) |
| `InvalidAudience` | Claim `aud` não corresponde com validação |
| `InvalidIssuer` | Claim `iss` não corresponde com validação |
| `ImmatureSignature` | Tempo atual antes do claim `nbf` |
| `MissingRequiredClaim` | Claim obrigatório ausente |

**Exemplo de tratamento:**
```rust
use jsonwebtoken::{decode, errors::ErrorKind};

match decode::<Claims>(&token, &key, &validation) {
    Ok(token_data) => println!("Token válido: {:?}", token_data.claims),
    Err(err) => match err.kind() {
        ErrorKind::ExpiredSignature => eprintln!("Token expirado"),
        ErrorKind::InvalidSignature => eprintln!("Assinatura inválida"),
        ErrorKind::InvalidIssuer => eprintln!("Issuer não autorizado"),
        _ => eprintln!("Erro na decodificação: {:?}", err),
    }
}
```

---

## Exemplo Completo: Criar e Verificar JWT HS256

```rust
use serde::{Deserialize, Serialize};
use jsonwebtoken::{encode, decode, Header, EncodingKey, DecodingKey, Validation, Algorithm};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Serialize, Deserialize, Debug)]
struct Claims {
    sub: String,
    iss: String,
    exp: u64,
    iat: u64,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let secret = b"minha_chave_secreta_muito_segura";
    
    // 1. Criar claims com expiração de 1 hora
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)?
        .as_secs();
    
    let claims = Claims {
        sub: "usuario@example.com".to_string(),
        iss: "meu_app".to_string(),
        exp: now + 3600,  // 1 hora
        iat: now,
    };
    
    // 2. Codificar (assinar) JWT
    let header = Header::new(Algorithm::HS256);
    let key = EncodingKey::from_secret(secret);
    let token = encode(&header, &claims, &key)?;
    println!("JWT gerado: {}", token);
    
    // 3. Decodificar e validar JWT
    let decode_key = DecodingKey::from_secret(secret);
    let validation = Validation::new(Algorithm::HS256);
    let token_data = decode::<Claims>(&token, &decode_key, &validation)?;
    
    println!("Claims válidos: {:?}", token_data.claims);
    println!("Header: {:?}", token_data.header);
    
    Ok(())
}
```

---

## Chaves (EncodingKey / DecodingKey)

Para **HS256** (HMAC com segredo compartilhado):

```rust
// Criar a partir de bytes (segredo compartilhado)
let key = EncodingKey::from_secret(b"my_secret");
let key = DecodingKey::from_secret(b"my_secret");

// Ou a partir de String
let secret_str = "my_secret_key";
let key = EncodingKey::from_secret(secret_str.as_ref());
```

**Importante:** Secretos HMAC (HS256) devem ser:
- Pelo menos 256 bits (32 bytes) de entropia
- Armazenados com segurança (variáveis de ambiente, vaults)
- Idênticos em encode e decode

---

## Notas Importantes

1. **Valores padrão de `Validation`:** Por padrão, `validate_exp = true`, então sempre forneça um campo `exp` válido nas claims.

2. **Leeway:** Use `validation.leeway = N` para tolerar pequenas diferenças de relógio entre servidores (em segundos).

3. **Algoritmos:** O algoritmo em `Header` **deve** corresponder com o em `Validation`, senão retorna `InvalidAlgorithm`.

4. **Deserialização:** Claims devem implementar `serde::Deserialize`; adicione `#[derive(Deserialize)]`.

5. **Bytes vs String:** Métodos aceitam `as_ref()` de String ou bytes diretos; use `b"secret"` para literais.
