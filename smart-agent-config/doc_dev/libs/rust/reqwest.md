# Reqwest

- **Versão Recomendada:** 0.13.4 (publicada em **2026-05-25**)
- **⚠️ Em uso no projeto:** `0.12.28` (resolvida no `Cargo.lock`; a crate não é
  declarada no workspace — entra por dependência transitiva). O salto 0.12 → 0.13
  é de major e **não foi feito**; ver a nota de verificação no fim deste doc.
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-09-06
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

### 2.4 Multipart Form (Upload de Arquivos)
Requiswet fornece `multipart::Form` e `multipart::Part` para envio de arquivos com mimetype e filename customizado.

```rust
use reqwest::multipart;

pub async fn upload_media(
    &self,
    instance_token: &str,
    file_bytes: Vec<u8>,
    file_name: &str,
    media_type: &str,
) -> Result<reqwest::Response, reqwest::Error> {
    let form = multipart::Form::new()
        .part(
            "media",
            multipart::Part::bytes(file_bytes)
                .file_name(file_name.to_string())
                .mime_str(media_type)?,
        );

    self.http
        .post(&format!("{}/message/sendMedia/instance", self.base_url))
        .header("apikey", instance_token)
        .multipart(form)
        .send()
        .await
}
```

---

## 3. Mudanças Recentes (0.13.x)

### 0.13.4 (Última — Julho 2026)
- Adição de `ClientBuilder::tls_sslkeylogfile(bool)` para suporte a variáveis de ambiente
- Novos métodos `ClientBuilder::http2_keep_alive_*` para o cliente bloqueante
- Suporte a TLS 1.3 ao usar backend `native-tls`
- **Correção importante:** Redirecionamentos agora removem headers sensíveis quando o esquema muda (ex: HTTPS → HTTP)
- Atualização da dependência hickory-resolver

### Versões 0.13.3, 0.13.2, 0.13.1
- Correções em parsing de CertificateRevocationList
- Problemas HTTP/3 corrigidos
- Compilação no Android e suporte ALPN melhorado

---

## 4. Backend TLS

**Não há breaking changes na série 0.13.x.** O TLS padrão mudou de `native-tls` para `rustls` na versão **0.13.0**. Se você ainda usa `native-tls`, ative explicitamente:

```toml
reqwest = { version = "0.13.4", features = ["native-tls"] }
```

---

## 5. Features Úteis

| Feature | Descrição |
|---------|-----------|
| `multipart` | Suporte a multipart forms (incluído por padrão) |
| `json` | Serialização/desserialização de JSON (padrão) |
| `cookies` | Gerenciamento automático de cookies |
| `http3` | Suporte experimental a HTTP/3 (requer `reqwest_unstable`) |
| `native-tls` | Backend TLS nativo do SO (padrão é `rustls`) |
| `gzip`, `brotli`, `zstd` | Compressão automática de respostas |

---

## Histórico de atualizações

- **2026-09-06:** Atualização via docs.rs e GitHub changelog. Confirmado versão 0.13.4 com TLS 1.3, multipart stável, remoção de headers em redirects HTTPS→HTTP, sem breaking changes na série 0.13.x. Formatação alinhada ao padrão doc_dev/libs.
- **2026-05-31:** Criado com padrões de reutilização de cliente, timeouts, headers customizados e tratamento de erros.

---

## Nota de verificação (2026-09-06)

A versão publicada foi confirmada direto na API do crates.io
(`https://crates.io/api/v1/crates/reqwest`): `max_stable_version = 0.13.4`,
publicada em **2026-05-25** — não em julho, como constava na primeira redação
desta atualização.

**Divergência a tratar fora deste doc:** o `Cargo.lock` do projeto resolve
`reqwest 0.12.28`. Enquanto o salto para 0.13 não for feito e testado, **o código
do projeto deve seguir a API da 0.12.x**. Este doc descreve a 0.13.4 como alvo,
não como o que está compilando hoje.
