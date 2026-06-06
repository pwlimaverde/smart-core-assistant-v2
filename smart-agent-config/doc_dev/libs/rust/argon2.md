# Argon2 (argon2)

- **Versão Recomendada:** 0.5.3
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Hashing seguro e criptográfico de senhas para o sistema de controle de acessos (Control Plane / RBAC) baseado no padrão Argon2id.
- **Documentação Oficial:** [https://docs.rs/argon2/latest/argon2/](https://docs.rs/argon2/latest/argon2/)

---

## 1. Contexto e Uso no Projeto

O cadastro de usuários administradores e atendentes no Control Plane requer persistência segura de senhas. A senha em texto puro nunca deve ser armazenada no banco. Adotamos o algoritmo **Argon2id** (vencedor do Password Hashing Competition) por ser altamente resistente a ataques de força bruta baseados em GPU/ASIC.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Geração de Hash com Sal Aleatório (Argon2id)
Utilize a struct `Argon2` com a configuração recomendada de consumo de memória e iterações (parâmetros da OWASP para criptografia contra ataques offline). É obrigatório gerar um sal (salt) aleatório e seguro por senha.

```rust
use argon2::{
    password_hash::{
        rand_core::OsRng,
        PasswordHash, PasswordHasher, PasswordVerifier, SaltString
    },
    Argon2,
};

/// Gera a hash criptográfica da senha usando Argon2id
pub fn hash_password(password: &str) -> Result<String, argon2::password_hash::Error> {
    // 1. Gerar sal aleatório seguro usando o gerador de sistema
    let salt = SaltString::generate(&mut OsRng);

    // 2. Configurar o Argon2id padrão (parâmetros de CPU/Memória adequados)
    let argon2 = Argon2::default();

    // 3. Executar o hashing
    let password_hash = argon2.hash_password(password.as_bytes(), &salt)?;

    Ok(password_hash.to_string())
}
```

### 2.2 Verificação de Senhas
A senha fornecida na autenticação deve ser confrontada com a hash guardada no banco de dados. A verificação deve usar tempo constante para mitigar ataques de temporização (Timing Attacks).

```rust
/// Verifica se a senha em texto puro corresponde à hash armazenada
pub fn verify_password(password: &str, hashed_password_str: &str) -> bool {
    // Parse da hash serializada em string para a estrutura PasswordHash
    let parsed_hash = match PasswordHash::new(hashed_password_str) {
        Ok(hash) => hash,
        Err(_) => return false,
    };

    // Executa a verificação usando a struct padrão do Argon2
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .is_ok()
}
```

### 2.3 Parâmetros do Runtime
A configuração padrão da crate `Argon2::default()` utiliza:
- `m_cost`: 65536 KB (64 MB)
- `t_cost`: 3 iterações
- `p_cost`: 4 threads de paralelismo

Caso precise ajustar esses custos devido à restrição de hardware na VM Hostinger, defina-os explicitamente usando `ParamsBuilder`.
