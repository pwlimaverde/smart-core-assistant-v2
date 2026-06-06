# Reqwest

- **Versão Recomendada:** 0.12.4
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Cliente HTTP assíncrono para comunicação com a API REST externa do Evolution Go.
- **Documentação Oficial:** [https://docs.rs/reqwest/latest/reqwest/](https://docs.rs/reqwest/latest/reqwest/)

---

## 1. Contexto e Uso no Projeto

A crate `infrastructure_evolution` utiliza a **reqwest** para interagir com a API REST do Evolution Go (cluster de WhatsApp).
Isso engloba:
- Criação e conexão de instâncias no Control Plane.
- Consulta de status de instâncias e pairing.
- Envio de mensagens outbound (texto, mídias).

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Reutilização do Cliente HTTP
Em Rust, a struct `reqwest::Client` usa internamente um pool de conexões HTTP e gerencia handles de forma thread-safe. **Nunca instancie um novo cliente a cada request**. Crie um único cliente e compartilhe-o via referência (`&Client`) ou clone-o (o clone é barato e compartilha o mesmo pool).

```rust
use reqwest::Client;
use std::time::Duration;

pub struct EvolutionClient {
    http: Client,
    base_url: String,
    global_api_key: String,
}

impl EvolutionClient {
    pub fn new(base_url: String, global_api_key: String) -> Self {
        // Inicializa o cliente com timeouts de conexão e timeout global padrão
        let http = Client::builder()
            .connect_timeout(Duration::from_secs(3))
            .timeout(Duration::from_secs(10))
            .pool_max_idle_per_host(10)
            .build()
            .expect("Falha ao construir Reqwest Client");

        Self { http, base_url, global_api_key }
    }
}
```

### 2.2 Envio Outbound com Token da Instância
A API do Evolution Go requer cabeçalhos específicos. Diferencie chamadas administrativas (que usam a *global key*) de chamadas de envio de mensagens do tenant (que usam o *token da instância*).

```rust
pub async fn send_text_message(
    &self,
    instance_name: &str,
    instance_token: &str,
    phone_number: &str,
    message_text: &str,
) -> Result<reqwest::Response, reqwest::Error> {
    let url = format!("{}/message/sendText/{}", self.base_url, instance_name);
    
    let payload = serde_json::json!({
        "number": phone_number,
        "options": {
            "delay": 1200,
            "presence": "composing"
        },
        "text": message_text
    });

    self.http
        .post(&url)
        // Autenticação específica por instância (não usar a global key aqui)
        .header("apikey", instance_token)
        .json(&payload)
        .send()
        .await
}
```

### 2.3 Tratamento de Respostas e Falhas
Verifique sempre o status da chamada usando `.error_for_status()` para propagar falhas HTTP (4xx, 5xx) de forma idiomática na pilha de erros.

```rust
pub async fn fetch_instance_qr(
    &self,
    instance_name: &str,
) -> Result<QrResponseDto, reqwest::Error> {
    let url = format!("{}/instance/qr/{}", self.base_url, instance_name);

    let response = self.http
        .get(&url)
        .header("apikey", &self.global_api_key) // Chamada administrativa
        .send()
        .await?
        .error_for_status()?; // Retorna erro reqwest::Error se não for status 2xx

    let qr_data = response.json::<QrResponseDto>().await?;
    Ok(qr_data)
}
```
