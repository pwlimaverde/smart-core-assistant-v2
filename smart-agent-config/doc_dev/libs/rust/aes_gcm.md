# AES-GCM (aes-gcm)

- **Versão Recomendada:** 0.10.3
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Criptografia simétrica autenticada (AEAD) para segurança e cifragem em repouso de credenciais de tenants e tokens de API no banco de dados.
- **Documentação Oficial:** [https://docs.rs/aes-gcm/latest/aes_gcm/](https://docs.rs/aes-gcm/latest/aes_gcm/)

---

## 1. Contexto e Uso no Projeto

Para evitar o vazamento de chaves privadas (tokens do Evolution Go e API keys dos provedores OpenAI/Groq configurados pelos inquilinos), todas as colunas de credenciais na tabela `tenant_config` e `evolution_instance` devem ser cifradas em repouso.

A chave mestra de cifragem deve ser carregada a partir da variável de ambiente `ENCRYPTION_KEY` (chave de 256 bits codificada em Hexadecimal ou Base64) e nunca salva no código.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Cifragem Simétrica Segura (AES-256-GCM)
Utilize `Aes256Gcm` para cifragem. É obrigatório gerar um **Nonce aleatório (vetor de inicialização) único de 96 bits** para cada operação de criptografia. Nunca reuse um Nonce. O Nonce deve ser salvo junto com a string cifrada (comumente prefixando o payload em bytes).

```rust
use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};

pub struct Encryptor {
    cipher: Aes256Gcm,
}

impl Encryptor {
    pub fn new(key_bytes: &[u8; 32]) -> Self {
        let cipher = Aes256Gcm::new(key_bytes.into());
        Self { cipher }
    }

    /// Cifra a string de texto puro retornando o payload combinado (nonce + ciphertext)
    pub fn encrypt(&self, plaintext: &str) -> Result<Vec<u8>, aes_gcm::Error> {
        // 1. Gerar nonce único de 12 bytes (96 bits) usando gerador seguro
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);

        // 2. Cifrar os dados
        let ciphertext = self.cipher.encrypt(&nonce, plaintext.as_bytes())?;

        // 3. Combinar nonce + dados cifrados para salvar no banco em uma única coluna BYTEA
        let mut combined = nonce.to_vec();
        combined.extend_from_slice(&ciphertext);

        Ok(combined)
    }
}
```

### 2.2 Decifragem de Credenciais
Ao decifrar, extraia os primeiros 12 bytes do payload recuperado do banco de dados para reconstruir o Nonce, e passe o restante como o conteúdo cifrado para o decifrador.

```rust
impl Encryptor {
    /// Decifra o payload combinado (nonce + ciphertext)
    pub fn decrypt(&self, combined_data: &[u8]) -> Result<String, anyhow::Error> {
        if combined_data.len() < 12 {
            return Err(anyhow::anyhow!("Payload cifrado corrompido ou muito curto."));
        }

        // 1. Separar o nonce (primeiros 12 bytes) do texto cifrado
        let (nonce_bytes, ciphertext) = combined_data.split_at(12);
        let nonce = Nonce::from_slice(nonce_bytes);

        // 2. Decifrar dados
        let decrypted_bytes = self.cipher.decrypt(nonce, ciphertext)
            .map_err(|e| anyhow::anyhow!("Falha na descriptografia AEAD: {:?}", e))?;

        // 3. Converter para String UTF-8
        let plaintext = String::from_utf8(decrypted_bytes)
            .context("Dados decifrados não contêm UTF-8 válido")?;

        Ok(plaintext)
    }
}
```

### 2.3 Tratamento Seguro de Memória
Após decifrar uma chave de API para fazer uma chamada HTTP (como enviar mensagem ao Evolution Go), limpe/descarte a variável contendo o valor em texto puro imediatamente ao finalizar a chamada, evitando que resquícios de credenciais permaneçam em memória RAM desnecessariamente.
