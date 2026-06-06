# secrecy

- **Versão Recomendada:** 0.10.3
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-01
- **Propósito no Projeto:** Proteger chaves de API descriptografadas em memória (`SecretString`), evitando vazamento em logs/`Debug`/panics e zerando o conteúdo no `Drop`.
- **Documentação Oficial:** [https://docs.rs/secrecy](https://docs.rs/secrecy)
- **Library ID (Context7):** `/iqlusioninc/crates`

---

## 1. Contexto e Uso no Projeto

As diretrizes de segurança (`08_diretrizes_seguranca.md` §4) exigem que structs carregando credenciais usem `SecretString`/`SecretVec`. No projeto, o `CipherManager::decrypt` devolve `SecretString` e os campos de chave de API do `RuntimeConfig` (`openai_api_key`, `groq_api_key`, `google_api_key`) são `SecretString`. O `Debug` imprime `[REDACTED]` e a memória é zerada no `Drop` (via `zeroize`).

### Features de Cargo

```toml
# feature "serde" só onde o RuntimeConfig precisa ser serializado para o Redis
secrecy = { version = "0.10.3", features = ["serde"] }
```

---

## 2. Guia de Uso Rápido

```rust
use secrecy::{SecretString, ExposeSecret};

// Construção a partir de uma String descriptografada
let chave: SecretString = SecretString::from(plaintext_string);

// Debug NUNCA vaza o valor:
tracing::info!(?chave); // imprime: chave: Secret([REDACTED alloc::string::String])

// Exposição explícita e pontual apenas onde for usar a credencial:
let cliente = OpenAiClient::new(chave.expose_secret());
```

- `expose_secret()` é o **único** caminho para ler o valor — torna o acesso auditável.
- Com a feature `serde`, `SecretString` desserializa normalmente; a serialização (para publicar no Redis) é opt-in e deve ser usada de forma consciente apenas na ponte `infrastructure_redis`.
- Nunca implemente `Debug` manual em structs de credencial; deixe o `SecretString` cuidar da redação.

---

## 3. Histórico de Atualizações

- **2026-06-01:** Documento criado durante a reestruturação do plano `infrastructure-postgres`.
