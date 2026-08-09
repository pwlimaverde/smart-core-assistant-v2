# Lettre

- **Versão Recomendada:** 0.11.22
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-08-09
- **Library ID (Context7):** `/websites/rs_lettre` (High reputation, 86.68 score)
- **Propósito no Projeto:** Cliente SMTP assíncrono com Tokio para envio de e-mails, suportando mensagens multipart (texto + HTML), autenticação segura e TLS (STARTTLS e SMTPS).
- **Documentação Oficial:** [https://docs.rs/lettre/latest/lettre/](https://docs.rs/lettre/latest/lettre/)

---

## 1. Contexto e Uso no Projeto

A crate `lettre` é o cliente SMTP principal para o Smart Core Assistant v2. Responsável por:
- Envio assíncrono de e-mails via tokio 1.38.
- Construção de mensagens com suporte a multipart (plain text + HTML).
- Autenticação segura com credenciais (integração com `secrecy` para senhas).
- Suporte a TLS (STARTTLS no port 587, SMTPS implícito no port 465).
- Pool de conexões para reutilização eficiente (feature `pool`, habilitada por padrão).

---

## 2. Features Necessárias no Cargo

```toml
[dependencies]
lettre = { version = "0.11", features = [
    "builder",           # MessageBuilder para construir mensagens
    "tokio1",            # AsyncSmtpTransport com Tokio 1.x
    "rustls",            # TLS via rustls (mais leve que native-tls)
    "pool",              # Connection pool (habilitado por padrão)
] }
secrecy = "0.8"          # Para credenciais sensíveis
tokio = { version = "1.38", features = ["full"] }
```

**Notas:**
- Use `rustls` (recomendado) ou `native-tls` para TLS. Não misture nos mesmos binários.
- A feature `tokio1` é obrigatória para async com Tokio 1.x. Alternativa: `async-std1` (mas native-tls não funciona com async-std).
- Feature `pool` mantém um pool de conexões por padrão; desabilite apenas se cria nova instância a cada e-mail.

---

## 3. Padrões de Implementação e Boas Práticas

### 3.1 Reutilização do Transporte SMTP

Assim como `reqwest::Client`, **crie uma única instância de `AsyncSmtpTransport` e reutilize-a**. O pool interno evita overhead de re-conexão.

```rust
use lettre::{
    AsyncSmtpTransport,
    AsyncTransport,
    Message,
    Tokio1Executor,
    transport::smtp::authentication::Credentials,
};
use std::sync::Arc;

pub struct EmailClient {
    mailer: Arc<AsyncSmtpTransport<Tokio1Executor>>,
}

impl EmailClient {
    /// Constrói o cliente a partir de uma URL SMTP.
    /// Formato: smtps://usuario:senha@smtp.example.com:465
    pub async fn new(smtp_url: &str) -> Result<Self, lettre::error::Error> {
        let mailer = AsyncSmtpTransport::<Tokio1Executor>::from_url(smtp_url)?
            .build();
        
        Ok(Self {
            mailer: Arc::new(mailer),
        })
    }

    /// Alternativa: construção manual com credenciais separadas
    pub async fn new_with_credentials(
        host: &str,
        port: u16,
        username: &str,
        password: &str,
    ) -> Result<Self, lettre::error::Error> {
        let mailer = AsyncSmtpTransport::<Tokio1Executor>::relay(host)?
            .port(port)
            .credentials(Credentials::new(
                username.to_owned(),
                password.to_owned(),
            ))
            .build();

        Ok(Self {
            mailer: Arc::new(mailer),
        })
    }

    /// Testa a conexão SMTP (retorna true se OK)
    pub async fn test_connection(&self) -> Result<bool, lettre::error::Error> {
        self.mailer.test_connection().await
    }
}
```

### 3.2 Construção de Mensagens Multipart

Use `MessageBuilder` com `MultiPart::alternative_plain_html()` para suportar clientes que não renderizam HTML e oferecer fallback.

```rust
use lettre::message::{Message, MultiPart, SinglePart};

pub async fn send_email(
    &self,
    from: &str,
    to: &str,
    subject: &str,
    plain_text: &str,
    html_body: &str,
) -> Result<lettre::smtp::SmtpResponse, lettre::error::Error> {
    let email = Message::builder()
        .from(from.parse()?)
        .to(to.parse()?)
        .subject(subject)
        .multipart(MultiPart::alternative_plain_html(
            plain_text.to_owned(),
            html_body.to_owned(),
        ))?;

    self.mailer.send(email).await
}
```

**Alternativa com replies e múltiplos destinatários:**

```rust
let email = Message::builder()
    .from("NoBody <nobody@domain.tld>".parse()?)
    .reply_to("Yuin <yuin@domain.tld>".parse()?)
    .to("Hei <hei@domain.tld>".parse()?)
    .cc("cc@domain.tld".parse()?)
    .subject("Olá!")
    .multipart(MultiPart::alternative_plain_html(
        "Texto simples".to_owned(),
        "<p>Texto <b>HTML</b></p>".to_owned(),
    ))?;

self.mailer.send(email).await?;
```

### 3.3 Autenticação SMTP e TLS

Lettre suporta três esquemas TLS via URL:

| Esquema | Comportamento | Porta | Segurança |
|---------|---------------|-------|-----------|
| `smtps://` | SMTP over TLS (implícito) | 465 | ✅ Recomendado |
| `smtp://` com `tls=required` | STARTTLS obrigatório | 587 | ✅ Seguro |
| `smtp://` com `tls=opportunistic` | STARTTLS opcional | 587 | ⚠️ Vulnerável a MITM |
| `smtp://` (sem TLS) | Sem criptografia | 587 | ❌ Não usar em produção |

**Exemplo com credenciais seguras (via `secrecy`):**

```rust
use secrecy::{Secret, ExposeSecret};
use lettre::transport::smtp::authentication::Credentials;

// Armazena com secrecy e expõe apenas quando necessário
let password: Secret<String> = Secret::new("senha_confidencial".to_owned());

let credentials = Credentials::new(
    "usuario@example.com".to_owned(),
    password.expose_secret().clone(),
);

let mailer = AsyncSmtpTransport::<Tokio1Executor>::relay("smtp.gmail.com")?
    .port(587)
    .credentials(credentials)
    .build();
```

### 3.4 Pool de Conexões

Com a feature `pool` habilitada (padrão), lettre gerencia automaticamente um pool de conexões. Customize via `AsyncSmtpTransportBuilder::pool_config()`:

```rust
use lettre::transport::smtp::pool::PoolConfig;
use std::time::Duration;

let pool_config = PoolConfig::new()
    .min_idle(2)                              // Manter 2 conexões ociosas
    .max_size(10)                             // Máximo 10 conexões
    .idle_timeout(Duration::from_secs(300)); // Timeout de 5 minutos

let mailer = AsyncSmtpTransport::<Tokio1Executor>::relay("smtp.example.com")?
    .pool_config(pool_config)
    .build();
```

**Importante:** O pool só funciona se você **reutilizar a mesma instância** de `AsyncSmtpTransport`. Criar uma nova instância a cada e-mail desabilita os benefícios do pooling.

### 3.5 Tratamento de Erros

Lettre retorna `lettre::error::Error` para falhas de conexão, autenticação e envio. Combine com o padrão de retorno do projeto:

```rust
use lettre::error::Error as LettreError;

pub async fn send_verification_email(
    &self,
    email: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let message = Message::builder()
        .from("noreply@smartcore.dev".parse()?)
        .to(email.parse()?)
        .subject("Verificação de E-mail")
        .body("Clique no link para verificar.".to_owned())?;

    match self.mailer.send(message).await {
        Ok(response) => {
            eprintln!("E-mail enviado: {:?}", response);
            Ok(())
        }
        Err(LettreError::Transport(ref e)) => {
            eprintln!("Erro de transporte SMTP: {}", e);
            Err(Box::new(e.clone()))
        }
        Err(e) => Err(Box::new(e)),
    }
}
```

---

## 4. Mini-Exemplo Compilável (Async/Tokio)

```rust
use lettre::{
    AsyncSmtpTransport,
    AsyncTransport,
    Message,
    Tokio1Executor,
    message::MultiPart,
    transport::smtp::authentication::Credentials,
};
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Cria o cliente SMTP
    let credentials = Credentials::new(
        "seu_usuario@gmail.com".to_owned(),
        "sua_senha_ou_token".to_owned(),
    );

    let mailer = AsyncSmtpTransport::<Tokio1Executor>::relay("smtp.gmail.com")?
        .port(587)
        .credentials(credentials)
        .timeout(Some(Duration::from_secs(10)))
        .build();

    // Testa a conexão
    match mailer.test_connection().await {
        Ok(true) => println!("✓ Conexão SMTP OK"),
        Ok(false) => println!("✗ Conexão falhou"),
        Err(e) => eprintln!("Erro na conexão: {}", e),
    }

    // Constrói mensagem multipart
    let email = Message::builder()
        .from("seu_usuario@gmail.com".parse()?)
        .to("destino@example.com".parse()?)
        .subject("Olá do Lettre")
        .multipart(MultiPart::alternative_plain_html(
            "Este é um e-mail de teste em texto simples.".to_owned(),
            "<h1>E-mail de Teste</h1><p>Este é um <b>e-mail HTML</b>.</p>".to_owned(),
        ))?;

    // Envia
    match mailer.send(email).await {
        Ok(response) => {
            println!("✓ E-mail enviado com sucesso!");
            println!("  Response: {:?}", response);
        }
        Err(e) => {
            eprintln!("✗ Erro ao enviar e-mail: {}", e);
            return Err(Box::new(e));
        }
    }

    Ok(())
}
```

**Para compilar e rodar:**

```bash
cargo new email_client
cd email_client

# Edite Cargo.toml (conforme seção 2)
cargo run
```

---

## 5. APIs Depreciadas e Breaking Changes

### Versão 0.11.22 (Atual)

- ✅ `AsyncSmtpTransport<Tokio1Executor>` — Padrão moderno, estável.
- ✅ `MessageBuilder` com `multipart()` — API recomendada.
- ✅ `AsyncTransport` trait — Interface padrão para envio.

### Mudanças Recentes (Versão 0.10 → 0.11)

- **Builder API Remodelada:** `AsyncSmtpTransportBuilder` agora oferece `.pool_config()` para customização explícita.
- **Timeout Explícito:** Use `.timeout(Some(Duration::from_secs(X)))` ao construir o transport (anteriormente implícito).
- **Pool Habilitado por Padrão:** Antes era opt-in via feature; agora é padrão quando feature `pool` está presente.

### Compatibilidade Futura

- Lettre segue SemVer; versões 0.12.x podem trazer mudanças menores.
- Monitore [https://docs.rs/lettre/latest/](https://docs.rs/lettre/latest/) para breaking changes.

---

## 6. Integração com Secrecy (Credenciais Seguras)

Use `secrecy::Secret<T>` para armazenar senhas SMTP sem exposição em logs ou dumps de memória:

```rust
use lettre::transport::smtp::authentication::Credentials;
use secrecy::{Secret, ExposeSecret};

pub fn create_credentials(
    username: String,
    password: Secret<String>,
) -> Credentials {
    Credentials::new(
        username,
        password.expose_secret().clone(), // Expor apenas quando necessário
    )
}
```

A `Secret<T>` zera a memória ao ser dropada, reduzindo risco de credential leaks.

---

## 7. Checklist de Implementação

- [ ] Feature `tokio1` habilitada em `Cargo.toml`
- [ ] Features `builder`, `rustls`, `pool` presentes
- [ ] `AsyncSmtpTransport` instanciado uma única vez e reutilizado
- [ ] Mensagens construídas com `MessageBuilder + MultiPart::alternative_plain_html()`
- [ ] Autenticação via `Credentials` e credenciais sensíveis com `secrecy::Secret`
- [ ] Teste de conexão realizado no startup (`.test_connection().await`)
- [ ] Tratamento de erros `lettre::error::Error` integrado
- [ ] Pool configurado com `min_idle`, `max_size`, `idle_timeout` apropriados
- [ ] Timeouts definidos explicitamente via `.timeout(Some(Duration::from_secs(X)))`

---

## 8. Referências Rápidas

| Caso de Uso | Função/Método |
|-------------|----------------|
| Criar transport de URL | `AsyncSmtpTransport::from_url("smtps://...")?.build()` |
| Relay manual | `AsyncSmtpTransport::relay("smtp.example.com")?` |
| Testar conexão | `mailer.test_connection().await?` |
| Enviar mensagem | `mailer.send(email).await?` |
| Multipart plain+HTML | `MultiPart::alternative_plain_html(plain, html)` |
| Credenciais | `Credentials::new(user, pass)` |
| Pool config | `PoolConfig::new().min_idle(2).max_size(10)` |
