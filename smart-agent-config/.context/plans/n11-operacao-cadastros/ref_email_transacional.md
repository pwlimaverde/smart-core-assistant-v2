# Levantamento Completo: E-mail Transacional em Rust para Smart Core Assistant v2

**Data:** Agosto 2026  
**Contexto:** Backend Rust self-hosted (VPS Hostinger, Docker), volume baixo/médio, um único domínio verificado

---

## 1. SMTP Direto via Lettre

### Visão Geral
**Lettre** é a biblioteca Rust nativa para SMTP. Oferece controle total, sem custos de terceiros (apenas custo de servidor SMTP).

### Portas e Protocolos

| Porta | Protocolo | Quando usar | Segurança |
|-------|-----------|-------------|-----------|
| **587** | STARTTLS | **Padrão recomendado** (RFC 5321) | Conexão inicia em texto plano, upgrade para TLS sob demanda |
| **465** | Implicit TLS | Alternativa moderna (RFC 8314 revalidou em 2020) | TLS desde o primeiro byte |
| 25 | Plain SMTP | Legacy, entrada em mail servers | Inseguro, não usar para clientes |
| 2525 | SMTP Alternativo | Quando 587/465 bloqueados | TLS disponível, similar a 587 |

**Recomendação:** Porta 587 com STARTTLS como padrão; implementar suporte a 465 como fallback. Em 2026, ambas são igualmente seguras quando bem configuradas.

### Autenticação

- **Método:** LOGIN ou PLAIN (sobre TLS)
- **Credenciais:** Usuário + Senha ou OAuth 2.0 (conforme provedor)
- **Obrigatório:** Domain verificado no servidor SMTP

### Requisitos Técnicos

- Instalação: `lettre = "0.10"` (requer Rust 1.74+)
- Suporte: Async (`lettre::AsyncTransport`) e síncrono
- Transports: SMTP padrão, Sendmail, canal em memória (testes)

### Provedores SMTP (Recomendados para Produção)

#### Gmail/Google Workspace
- **Requisito crítico:** Senha de app específica (não suporta login com usuário+senha desde maio 2022)
- **Portas:** 587 (STARTTLS) ou 465 (Implicit TLS)
- **Endpoint:** `smtp.gmail.com`
- **Custo:** Gratuito (até limites de conta)
- **Limitação:** ~300 emails/dia para Gmail grátis; sem limite para Workspace (pago)

#### Mailtrap (para testes)
- **Endpoint:** `live.smtp.mailtrap.io`
- **Ports:** 587 ou 465
- **Free tier:** 4.000 emails/mês permanente
- **Uso:** Ideal para desenvolvimento e testes; não produção real

#### Servidor SMTP próprio
- **Exemplo:** Postfix em máquina Linux
- **Custo:** $0 (você gerencia)
- **Complexidade:** Alta; requer configuração de SPF/DKIM/DMARC próprias
- **Não recomendado** para este cenário (overhead operacional alto)

### Exemplo de Código (Lettre + STARTTLS)

```rust
use lettre::{
    transport::smtp::{authentication::Credentials, SmtpTransport},
    Message, Transport,
};

fn send_email_smtp() -> Result<(), Box<dyn std::error::Error>> {
    // Criar mensagem
    let email = Message::builder()
        .from("noreply@seudominio.com".parse()?)
        .to("usuario@example.com".parse()?)
        .subject("Boas-vindas ao Smart Core Assistant")
        .html(
            r#"
            <h1>Bem-vindo!</h1>
            <p>Sua conta foi criada com sucesso.</p>
            <a href="https://seudominio.com/activate?token=ABC123">Ativar Conta</a>
            "#,
        )?
        .build()?;

    // Configurar transport SMTP
    let creds = Credentials::new(
        "seu_email@gmail.com".to_string(),
        "sua_senha_app".to_string(), // Usar App Password, não senha normal
    );

    let mailer = SmtpTransport::relay("smtp.gmail.com")?
        .credentials(creds)
        .port(587)
        .timeout(Some(std::time::Duration::from_secs(5)))
        .build();

    // Enviar
    mailer.send(&email)?;
    println!("E-mail enviado com sucesso!");

    Ok(())
}

// Versão async com Tokio
use lettre::transport::smtp::SmtpTransport;
use lettre::Transport;

#[tokio::main]
async fn send_email_async() -> Result<(), Box<dyn std::error::Error>> {
    let creds = Credentials::new(
        "seu_email@gmail.com".to_string(),
        "sua_senha_app".to_string(),
    );

    let mailer = SmtpTransport::relay("smtp.gmail.com")?
        .credentials(creds)
        .build();

    let email = Message::builder()
        .from("noreply@seudominio.com".parse()?)
        .to("usuario@example.com".parse()?)
        .subject("Recuperação de Senha")
        .html("<a href='https://seudominio.com/reset?token=XYZ789'>Redefinir Senha</a>")?
        .build()?;

    mailer.send(&email)?;
    Ok(())
}
```

### Prós e Contras

**Prós:**
- Zero custo externo (se usar Gmail/Workspace)
- Controle total da mensagem
- Sem dependência de serviço terceirizado
- Suporte nativo de anexos, templates HTML

**Contras:**
- Sem webhooks de entrega/bounce nativos
- Sem analytics de aberturas/clicks
- Reputação vinculada ao servidor SMTP (risco maior com Gmail)
- Requer gerenciamento manual de credenciais

---

## 2. APIs HTTP Transacionais

### Tabela Comparativa de Preços (Agosto 2026)

| Provedor | Free Tier | Primeiro Pago | Volume $0.10 | Melhor em |
|----------|-----------|---------------|--------------|-----------|
| **Resend** | 3.000/mês | — | ~ 50K/mês | DX; React Email; Novo; Moderno |
| **SendGrid** | 100/dia (60 dias) | $19.95/mês | ~ 100K/mês | Histórico; Integrações; Escalabilidade |
| **Amazon SES** | $200 créditos (6 meses) | $0.10/1K | ~ 10/mês | **Custo a escala (mais barato em volume alto)** |
| **Brevo** | 300/dia ∞ | $9/mês | ~ 40K/mês | Free tier; Marketing + Transacional |
| **Postmark** | 100/mês ∞ | $15/mês | ~ 10K/mês | Confiabilidade; Entrega rápida |

**Nota sobre SES (Agosto 2026):** Free tier específico para novos clientes **descontinuado em 21 de julho de 2026**. Contas criadas após essa data recebem $200 em créditos gerais AWS (aplicável a SES e outros serviços).

### Recomendação por Volume

- **< 1K/mês:** Qualquer um (até gratuito)
- **1K–10K/mês:** Resend, Brevo ou Postmark (free + pequeno pago)
- **10K–100K/mês:** Brevo ou Amazon SES (melhor custo)
- **> 100K/mês:** Amazon SES (definitivamente o mais barato)

---

## 3. Análise Detalhada dos Provedores

### 3.1 Resend

**Posicionamento:** "Email API for Developers" — desenvolvedor-first, moderno

#### Preço
- **Free:** 3.000 transactionais/mês (permanente)
- **Pro:** $19.95/mês para 5.000 + $0.01 por envio adicional
- **Dados (ago/2026):** A mais cara em alto volume, mas melhor DX

#### Endpoint de Envio
```
POST https://api.resend.com/emails
Content-Type: application/json
Authorization: Bearer re_xxxxxxxxx
```

#### Autenticação
- **Método:** Bearer Token no header `Authorization`
- **API Key:** Gerada no dashboard Resend

#### JSON Body (Exemplo)
```json
{
  "from": "onboarding@resend.dev",
  "to": "delivered@resend.dev",
  "subject": "Bem-vindo ao Smart Core",
  "html": "<strong>Sua conta foi ativada!</strong>",
  "reply_to": "suporte@seudominio.com"
}
```

#### Rust SDK
- **Oficial:** `resend_rs` — cliente nativo para Rust
- **Instalação:** `resend = "0.5"`
- **Exemplo:**
```rust
use resend_rs::types::CreateEmailBaseOptions;
use resend_rs::Resend;

#[tokio::main]
async fn main() {
    let resend = Resend::new("re_xxxxxxxxx");
    let email = CreateEmailBaseOptions::new(
        "noreply@seudominio.com",
        vec!["usuario@example.com"],
        "Ativar sua conta"
    ).with_html("<a href='...'>Ativar</a>");
    
    let result = resend.emails.send(email).await;
    println!("{:?}", result);
}
```

#### Domínio Verificado
- Obrigatório: SIM
- Setup: DNS (TXT record para DKIM/SPF)
- Tempo: ~15 minutos

#### Webhooks
- **Eventos:** email_sent, email_delivered, email_bounced, email_complained, email_open, email_click
- **Endpoint:** POST a seu servidor com JSON event
- **Retry:** Automático (exponential backoff)

#### Suporte SMTP
- **Não oferece SMTP** — apenas API HTTP

---

### 3.2 SendGrid (via Twilio)

**Posicionamento:** Histórico consolidado; usado em produção por grandes empresas

#### Preço (Agosto 2026)
- **Free:** 100 emails/dia por 60 dias (depois requer plano pago)
- **Starter:** $19.95/mês para 20.000/mês
- **Dados (ago/2026):** Free tier removido; SendGrid agora é enterprise-focused

#### Endpoint de Envio
```
POST https://api.sendgrid.com/v3/mail/send
Content-Type: application/json
Authorization: Bearer SG.xxxxxxxxx
```

#### Autenticação
- **Método:** Bearer Token
- **Header:** `Authorization: Bearer YOUR_SENDGRID_API_KEY`

#### JSON Body (Exemplo)
```json
{
  "personalizations": [
    {
      "to": [{"email": "usuario@example.com"}],
      "subject": "Convite para Smart Core"
    }
  ],
  "from": {"email": "noreply@seudominio.com", "name": "Smart Core"},
  "content": [
    {
      "type": "text/html",
      "value": "<h1>Bem-vindo!</h1>"
    }
  ]
}
```

#### Rust SDK
- **Oficial:** `sendgrid` crate
- **Instalação:** `sendgrid = "0.16"`
- **Alternativa:** Usar `reqwest` direto (menos dependências)

#### Domínio Verificado
- Obrigatório: SIM
- Setup: SPF + DKIM via DNS
- Tempo: 24-48 horas (DKIM)

#### Webhooks
- **Eventos:** Delivered, Bounce, Open, Click, Dropped, Unsubscribe, etc.
- **Retry:** 5 tentativas com backoff

#### Suporte SMTP
- **Sim:** porta 587 ou 465
- **Credenciais:** `apikey` como usuário, API Key como senha
- **Endpoint:** `smtp.sendgrid.net`

---

### 3.3 Amazon SES

**Posicionamento:** Infraestrutura AWS; o mais barato em alto volume

#### Preço (Agosto 2026)
- **Free:** $200 em créditos AWS (6 meses); **SES-específico descontinuado em 21/07/2026**
- **Pós-free:** $0.10 por 1.000 emails
- **Dados (ago/2026):** Exemplo: 100K/mês = ~$10

#### Endpoint de Envio
```
POST https://email.us-east-1.amazonaws.com/
(região variável; ex.: eu-west-1 para Europa)
Content-Type: application/x-amz-json-1.1
```

#### Autenticação
- **Método:** AWS Signature V4 (assinatura; requer AWS SDK)
- **Alternativa:** Usar IAM role em EC2 (mais seguro em VPS)
- **API Key/Secret:** Armazenar em variáveis de ambiente ou secrets manager

#### JSON Body (Exemplo via SDK)
```rust
// Via AWS SDK para Rust
use aws_sdk_sesv2::types::{EmailContent, Body, Content};

let client = aws_sdk_sesv2::Client::new(&config);
client
    .send_email()
    .from_email_address("noreply@seudominio.com")
    .destination(Destination::builder().to_addresses("usuario@example.com").build())
    .content(
        EmailContent::builder()
            .simple(
                Message::builder()
                    .subject(Content::builder().data("Bem-vindo").build())
                    .body(Body::builder()
                        .html(Content::builder().data("<h1>Ativação</h1>").build())
                        .build())
                    .build()
            )
            .build()
    )
    .send()
    .await?;
```

#### Domínio Verificado
- Obrigatório: SIM
- Setup: DNS TXT record (verificação de domínio)
- Tempo: Imediato (após validação)
- **Sandbox mode:** Por padrão, novo, requer whitelist de destinatários
- **Production access:** Solicitar via AWS Support (geralmente 24h)

#### Webhooks
- **Eventos:** Send, Delivery, Open, Click, Bounce, Complaint, Delivery Delay, Subscription
- **Endpoint:** SNS (Simple Notification Service) — pode redirecionar para HTTP

#### Suporte SMTP
- **Sim:** porta 587 ou 465
- **Credenciais:** Geradas via IAM (usuário + senha específicos para SMTP)
- **Endpoint:** `email-smtp.REGION.amazonaws.com` (ex.: `email-smtp.us-east-1.amazonaws.com`)

---

### 3.4 Brevo (Sendinblue renomeado)

**Posicionamento:** Melhor free tier; tudo em um (transacional + marketing)

#### Preço (Agosto 2026)
- **Free:** 300 emails/dia (sem limite de dias; permanente)
- **Starter:** $9/mês para 5.000/mês
- **Pro:** $19/mês para 20.000/mês
- **Dados (ago/2026):** Melhor relação free + pago inicial

#### Endpoint de Envio
```
POST https://api.brevo.com/v3/smtp/email
Content-Type: application/json
api-key: xkeysib-xxxxxxxxx
```

#### Autenticação
- **Método:** API Key no header `api-key`
- **Header:** `api-key: xkeysib-XXXXXXX`

#### JSON Body (Exemplo)
```json
{
  "sender": {
    "name": "Smart Core",
    "email": "noreply@seudominio.com"
  },
  "to": [
    {
      "email": "usuario@example.com",
      "name": "João Silva"
    }
  ],
  "subject": "Convite para ativar sua conta",
  "htmlContent": "<h1>Bem-vindo!</h1><a href='https://seudominio.com/activate?token=ABC123'>Ativar</a>",
  "params": {
    "activationLink": "https://seudominio.com/activate?token=ABC123"
  }
}
```

#### Rust SDK
- **Oficial:** Não há SDK Rust nativo
- **Recomendado:** `reqwest` + `serde_json`
- **Exemplo:**
```rust
use reqwest::Client;
use serde_json::json;

#[tokio::main]
async fn send_email_brevo() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let response = client
        .post("https://api.brevo.com/v3/smtp/email")
        .header("api-key", "xkeysib-xxxxxxxxx")
        .header("Content-Type", "application/json")
        .json(&json!({
            "sender": {
                "email": "noreply@seudominio.com",
                "name": "Smart Core"
            },
            "to": [{
                "email": "usuario@example.com"
            }],
            "subject": "Bem-vindo!",
            "htmlContent": "<h1>Sua conta foi criada</h1>"
        }))
        .send()
        .await?;
    
    if response.status().is_success() {
        println!("Email enviado!");
    }
    Ok(())
}
```

#### Domínio Verificado
- Obrigatório: SIM
- Setup: DNS TXT (SPF, DKIM)
- Tempo: ~15 minutos

#### Webhooks
- **Eventos:** email_sent, email_delivered, email_bounced, email_unsubscribed, email_clicked
- **Setup:** Via dashboard; webhook HTTP POST

#### Suporte SMTP
- **Sim:** porta 587 ou 465
- **Credenciais:** Usuário (qualquer string) + Senha (gerar no dashboard)
- **Endpoint:** `smtp-relay.brevo.com`

---

### 3.5 Postmark

**Posicionamento:** Premium-affordable; foco em confiabilidade e entrega rápida

#### Preço (Agosto 2026)
- **Free:** 100 emails/mês (permanente, sem expiração)
- **Basic:** $15/mês para 10.000/mês
- **Pro:** $16.50/mês para 10.000/mês (melhor retenção de dados)
- **Dados (ago/2026):** Pequeno pago mais barato que SendGrid

#### Endpoint de Envio
```
POST https://api.postmarkapp.com/email
Content-Type: application/json
X-Postmark-Server-Token: xxxxxxx
```

#### Autenticação
- **Método:** Server Token no header `X-Postmark-Server-Token`
- **Header:** `X-Postmark-Server-Token: your_server_token_here`

#### JSON Body (Exemplo)
```json
{
  "From": "noreply@seudominio.com",
  "To": "usuario@example.com",
  "Subject": "Ativar sua conta",
  "HtmlBody": "<h1>Bem-vindo ao Smart Core!</h1><p>Clique abaixo para ativar sua conta:</p><a href='https://seudominio.com/activate?token=ABC123'>Ativar Conta</a>",
  "TextBody": "Bem-vindo ao Smart Core! Ative sua conta: https://seudominio.com/activate?token=ABC123",
  "MessageStream": "outbound",
  "TrackOpens": true,
  "TrackLinks": "HtmlAndText"
}
```

#### Rust SDK
- **Oficial:** Não há SDK Rust nativo
- **Recomendado:** `reqwest` + `serde_json` ou `postmark-rs` (community)
- **Exemplo:**
```rust
use reqwest::Client;
use serde_json::json;

#[tokio::main]
async fn send_email_postmark() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let response = client
        .post("https://api.postmarkapp.com/email")
        .header("X-Postmark-Server-Token", "YOUR_SERVER_TOKEN")
        .json(&json!({
            "From": "noreply@seudominio.com",
            "To": "usuario@example.com",
            "Subject": "Recuperar Senha",
            "HtmlBody": "<a href='https://seudominio.com/reset?token=XYZ'>Redefinir Senha</a>"
        }))
        .send()
        .await?;
    
    println!("Status: {}", response.status());
    Ok(())
}
```

#### Domínio Verificado
- Obrigatório: SIM (Sender Signature)
- Setup: DKIM + SPF via DNS
- Tempo: 24-48 horas (DKIM)

#### Webhooks
- **Eventos:** Delivery, Open, Click, Bounce, Unsubscribe, etc.
- **Setup:** Via dashboard; webhook HTTP POST
- **Retry:** 5 tentativas com backoff

#### Suporte SMTP
- **Sim:** porta 587 ou 465
- **Credenciais:** Postmark API token como usuário; senha qualquer
- **Endpoint:** `smtp.postmarkapp.com`

#### Limitações Técnicas
- **Max size:** 10 MB por email
- **Max recipients:** 50 combinados (To + Cc + Bcc)

---

## 4. Entregabilidade: SPF, DKIM, DMARC

### Contexto (Agosto 2026)

Em 2026, **SPF e DKIM são obrigatórios** pela Google, Yahoo e Microsoft. Não são mais "melhores práticas" — são entrada mínima para sua caixa de entrada no Gmail, Outlook e Yahoo.

### SPF (Sender Policy Framework)

**O que é:** Autorização DNS que diz "esses hosts podem enviar email por meu domínio"

**Setup:**
1. Acesse seu DNS (sua registradora ou Hostinger)
2. Crie um registro TXT no domínio raiz (ex.: `seudominio.com`)

**Exemplo (para Brevo):**
```
seudominio.com TXT "v=spf1 include:smtp-relay.brevo.com ~all"
```

**Exemplo (para Postmark):**
```
seudominio.com TXT "v=spf1 include:postmarkapp.com ~all"
```

**Propagação:** ~15–30 minutos

**Importante:**
- Só pode haver UM registro SPF por domínio
- Se usar múltiplos provedores, combinar em um único registro:
  ```
  v=spf1 include:smtp-relay.brevo.com include:postmarkapp.com ~all
  ```

### DKIM (DomainKeys Identified Mail)

**O que é:** Assinatura criptográfica que prova que você enviou e o email não foi alterado em trânsito

**Setup:**
1. Provedor (Brevo, Postmark, etc.) gera par de chaves
2. Você adiciona a chave pública ao DNS como registro TXT
3. Provedor assina emails automaticamente com a chave privada

**Exemplo de registro DKIM (Postmark):**
```
postmark._domainkey.seudominio.com TXT "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3D..."
```

**Propagação:** 24–48 horas (às vezes até 72h)

**Crítico:** Geralmente é necessário um registro DKIM separado por provedor (ex.: se usar Brevo e SendGrid, dois registros)

### DMARC (Domain-based Message Authentication, Reporting and Conformance)

**O que é:** Política que diz "se SPF/DKIM falhar, o que fazer?" (aceitar, quarentena ou rejeitar)

**Setup:**
1. Crie um registro TXT em `_dmarc.seudominio.com`

**Exemplo (política permissiva, recomendada para começar):**
```
_dmarc.seudominio.com TXT "v=DMARC1; p=none; rua=mailto:relatorios@seudominio.com"
```

**Explicação:**
- `p=none`: Não rejeita (monitora apenas)
- `rua=mailto:...`: Enviar relatórios agregados para este email

**Após 1-2 semanas de monitoramento, mudar para:**
```
_dmarc.seudominio.com TXT "v=DMARC1; p=quarantine; rua=mailto:relatorios@seudominio.com"
```

**Ou, em produção:**
```
_dmarc.seudominio.com TXT "v=DMARC1; p=reject; rua=mailto:relatorios@seudominio.com; fo=1"
```

### Checklist de Configuração

- [ ] **SPF:** Registro TXT no domínio raiz (`seudominio.com`)
- [ ] **DKIM:** Registros TXT em `provedor._domainkey.seudominio.com` (um por provider)
- [ ] **DMARC:** Registro TXT em `_dmarc.seudominio.com`
- [ ] **Reverse DNS:** Opcional, mas recomendado (configurar no VPS Hostinger — contatar suporte)
- [ ] **Verificar:** Ferramentas como MXToolbox.com ou mail-tester.com antes de ir a produção

### Tempo Total de Setup

- SPF: 15–30 min
- DKIM: 24–48h
- DMARC: Imediato (depois aumentar `p` após 1-2 semanas)
- **Total recomendado:** Começar na segunda-feira, ir a produção no quarta-feira

---

## 5. Exemplos Funcionais de Código Rust

### 5.1 Resend API com reqwest (Alternativa sem SDK)

```rust
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Debug, Serialize)]
struct EmailRequest {
    from: String,
    to: Vec<String>,
    subject: String,
    html: String,
}

#[derive(Debug, Deserialize)]
struct EmailResponse {
    id: String,
}

#[tokio::main]
async fn send_email_resend_reqwest() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let api_key = std::env::var("RESEND_API_KEY")?;

    let email_request = EmailRequest {
        from: "noreply@seudominio.com".to_string(),
        to: vec!["usuario@example.com".to_string()],
        subject: "Bem-vindo ao Smart Core Assistant".to_string(),
        html: r#"
            <h1>Bem-vindo!</h1>
            <p>Sua conta foi criada com sucesso.</p>
            <a href="https://seudominio.com/activate?token=ABC123" style="background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block;">
                Ativar Conta
            </a>
        "#.to_string(),
    };

    let response = client
        .post("https://api.resend.com/emails")
        .bearer_auth(&api_key)
        .json(&email_request)
        .send()
        .await?;

    if response.status().is_success() {
        let data: EmailResponse = response.json().await?;
        println!("Email enviado com ID: {}", data.id);
    } else {
        println!("Erro: {}", response.status());
        println!("Body: {}", response.text().await?);
    }

    Ok(())
}
```

### 5.2 Postmark API com reqwest

```rust
use reqwest::Client;
use serde_json::json;

#[tokio::main]
async fn send_email_postmark() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let server_token = std::env::var("POSTMARK_SERVER_TOKEN")?;

    let response = client
        .post("https://api.postmarkapp.com/email")
        .header("X-Postmark-Server-Token", &server_token)
        .json(&json!({
            "From": "noreply@seudominio.com",
            "To": "usuario@example.com",
            "Subject": "Confirme seu e-mail",
            "HtmlBody": r#"
                <h1>Confirme seu E-mail</h1>
                <p>Clique no link abaixo para confirmar seu e-mail:</p>
                <a href="https://seudominio.com/confirm?token=XYZ789">Confirmar E-mail</a>
            "#,
            "TextBody": "Confirme seu e-mail: https://seudominio.com/confirm?token=XYZ789",
            "MessageStream": "outbound",
            "TrackOpens": true,
            "TrackLinks": "HtmlAndText"
        }))
        .send()
        .await?;

    match response.status().as_u16() {
        200 => println!("Email enfileirado com sucesso!"),
        422 => println!("Erro de validação: {}", response.text().await?),
        _ => println!("Erro desconhecido: {}", response.status()),
    }

    Ok(())
}
```

### 5.3 Brevo API com reqwest

```rust
use reqwest::Client;
use serde_json::json;

#[tokio::main]
async fn send_email_brevo() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let api_key = std::env::var("BREVO_API_KEY")?;

    let response = client
        .post("https://api.brevo.com/v3/smtp/email")
        .header("api-key", &api_key)
        .json(&json!({
            "sender": {
                "name": "Smart Core Assistant",
                "email": "noreply@seudominio.com"
            },
            "to": [{
                "email": "usuario@example.com",
                "name": "João da Silva"
            }],
            "subject": "Recuperar Senha - Smart Core",
            "htmlContent": r#"
                <h1>Resetar Sua Senha</h1>
                <p>Você solicitou uma recuperação de senha. Clique no link abaixo para resetar:</p>
                <a href="https://seudominio.com/reset-password?token=ABC123XYZ789" style="background: #28a745; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px;">
                    Resetar Senha
                </a>
                <p><small>Este link expira em 1 hora.</small></p>
            "#
        }))
        .send()
        .await?;

    if response.status() == 201 {
        println!("Email enviado com sucesso!");
    } else {
        println!("Erro {}: {}", response.status(), response.text().await?);
    }

    Ok(())
}
```

### 5.4 Amazon SES com AWS SDK (Complexo, mas poderoso)

```rust
use aws_config::meta::region::RegionProviderChain;
use aws_sdk_sesv2::{
    types::{Body, Content, Destination, EmailContent, Message},
    Client,
};

#[tokio::main]
async fn send_email_ses() -> Result<(), Box<dyn std::error::Error>> {
    // Carregar config AWS (usa IAM role ou variáveis de ambiente)
    let region_provider = RegionProviderChain::default_provider().or_else("us-east-1");
    let config = aws_config::defaults(aws_config::BehaviorVersion::latest())
        .region(region_provider)
        .load()
        .await;
    let client = Client::new(&config);

    // Construir email
    let destination = Destination::builder()
        .to_addresses("usuario@example.com")
        .build();

    let subject = Content::builder()
        .data("Bem-vindo ao Smart Core Assistant")
        .build();

    let html_body = Content::builder()
        .data(
            r#"
            <h1>Bem-vindo!</h1>
            <p>Sua conta está pronta para usar.</p>
            <a href="https://seudominio.com/activate?token=ABC123">Ativar</a>
            "#,
        )
        .build();

    let text_body = Content::builder()
        .data("Bem-vindo! Ative sua conta: https://seudominio.com/activate?token=ABC123")
        .build();

    let body = Body::builder()
        .html(html_body)
        .text(text_body)
        .build();

    let message = Message::builder()
        .subject(subject)
        .body(body)
        .build();

    let email_content = EmailContent::builder()
        .simple(message)
        .build();

    // Enviar
    let result = client
        .send_email()
        .from_email_address("noreply@seudominio.com")
        .destination(destination)
        .content(email_content)
        .send()
        .await?;

    println!("Email enviado! ID: {}", result.message_id());

    Ok(())
}
```

### 5.5 Lettre SMTP (Versão Completa Async)

```rust
use lettre::{
    transport::smtp::{authentication::Credentials, SmtpTransport},
    Message, Transport,
};

#[tokio::main]
async fn send_email_lettre_async() -> Result<(), Box<dyn std::error::Error>> {
    let email = Message::builder()
        .from("noreply@seudominio.com".parse()?)
        .to("usuario@example.com".parse()?)
        .subject("Ativar sua conta no Smart Core")
        .multipart(
            lettre::message::MultiPart::alternative()
                .singlepart(
                    lettre::message::SinglePart::plain(
                        "Ative sua conta: https://seudominio.com/activate?token=ABC123",
                    ),
                )
                .singlepart(
                    lettre::message::SinglePart::html(
                        r#"
                        <h1>Smart Core Assistant</h1>
                        <p>Bem-vindo! Sua conta foi criada.</p>
                        <a href="https://seudominio.com/activate?token=ABC123" style="background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block;">
                            Ativar Conta
                        </a>
                        "#,
                    ),
                ),
        )?
        .build()?;

    // Gmail com App Password (recomendado)
    let creds = Credentials::new(
        "seu_email@gmail.com".to_string(),
        "sua_senha_app_gmail".to_string(),
    );

    let mailer = SmtpTransport::relay("smtp.gmail.com")?
        .credentials(creds)
        .port(587) // Padrão: STARTTLS
        .timeout(Some(std::time::Duration::from_secs(10)))
        .build();

    // Envio síncrono
    mailer.send(&email)?;
    println!("Email enviado com sucesso via Gmail!");

    Ok(())
}

// Alternativa: Brevo SMTP
#[tokio::main]
async fn send_email_lettre_brevo() -> Result<(), Box<dyn std::error::Error>> {
    let email = Message::builder()
        .from("noreply@seudominio.com".parse()?)
        .to("usuario@example.com".parse()?)
        .subject("Redefinir senha")
        .html(
            r#"<a href="https://seudominio.com/reset?token=XYZ789">Clique aqui para redefinir sua senha</a>"#,
        )?
        .build()?;

    let creds = Credentials::new(
        "qualquer_usuario".to_string(),
        "sua_senha_brevo_smtp".to_string(),
    );

    let mailer = SmtpTransport::relay("smtp-relay.brevo.com")?
        .credentials(creds)
        .port(587)
        .build();

    mailer.send(&email)?;
    println!("Email enviado via Brevo SMTP!");

    Ok(())
}
```

---

## 6. Recomendação Final

### Para o Smart Core Assistant v2 (Self-hosted, volume baixo/médio, um domínio)

**Primeira Escolha: Brevo (API HTTP)**
- **Razão:** Melhor balanço entre custo, funcionalidade e simplicidade
  - Free tier de 300/dia (permanente) cobre demanda baixa sem custo
  - Primeiro plano pago só a $9/mês (mais barato que SendGrid/Postmark)
  - API simples, sem SDK nativo necessário (reqwest + serde_json)
  - Webhooks para rastreamento de entrega/bounces
  - SMTP como fallback disponível
  - Suporte a múltiplos templates e batch send
- **Setup:** 15 minutos (API key + DNS DKIM/SPF + verificar domínio)
- **Escalabilidade:** Bom até 200K/mês; depois comparar com SES

**Segunda Escolha: Postmark (API HTTP)**
- **Razão:** Se confiabilidade e suporte forem críticos
  - Free tier de 100/mês (permanente)
  - Primeira opção entre SaaS para entrega de alta confiabilidade
  - Dashboard intuitivo; webhooks robustos
  - API JSON clara; fácil com reqwest
- **Setup:** 20 minutos (similar a Brevo)
- **Desvantagem:** $15/mês inicial é mais caro que Brevo

**Alternativa para Infraestrutura AWS: Amazon SES**
- **Razão:** Se infraestrutura já é AWS
  - $0.10 por 1K emails (super barato em volume)
  - Integração nativa com IAM (segurança enterprise)
  - Sandbox mode para testes; production access em 24h
- **Desvantagem:** Complexidade inicial; AWS SDK é pesado
- **Setup:** 30 minutos; exige conhecimento AWS
- **Recomendado quando:** > 50K/mês ou budget é constraint principal

**Evitar: SMTP Direto (Lettre + Gmail)**
- **Razão:** Não para produção em 2026
  - Reputação do Gmail pode sofrer; Google limita envios
  - Sem analytics de entrega/bounce
  - Suporte Gmail para app-specific passwords é bom, mas não escala bem
  - Melhor apenas para testes ou backups internos
- **Exceção:** Se usar Gmail Workspace corporativo com domínio próprio (então considerar SendGrid)

---

## 7. Tabela de Decisão Rápida

| Critério | Brevo | Postmark | SES | Resend | SendGrid |
|----------|-------|----------|-----|--------|----------|
| **Free tier** | 300/dia ∞ | 100/mês ∞ | $200 6m | 3K/mês ∞ | 100/dia 60d |
| **Primeiro pago** | $9/mês | $15/mês | $0.10/1K | $19.95/mês | $19.95/mês |
| **SDK Rust nativo** | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Facilidade (reqwest)** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **SMTP disponível** | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Webhooks** | ✅ | ✅ | ✅ (SNS) | ✅ | ✅ |
| **Escalabilidade** | Até 200K/mês | Até 100K/mês | Sem limite | Até 100K/mês | Sem limite |
| **Melhor em** | Custo+Free | Confiabilidade | Custo total | DX/Dev | Histórico |

---

## Fontes e Datas

- Preços capturados em **Agosto 2026** via WebSearch
- Documentações oficiais consultadas em **Agosto 2026**
- RFC 8314 (SMTP Submission): https://tools.ietf.org/html/rfc8314
- Lettre 0.10 (junho 2026): https://github.com/lettre/lettre
- Amazon SES Free Tier Discontinuado: Julho 21, 2026 (AWS Blog)
- SPF/DKIM/DMARC 2026 Requirements: Google, Yahoo, Microsoft (2024)

---

## Próximos Passos Recomendados

1. **Escolher Brevo** como primária
2. **Criar arquivo `.env.example`:**
   ```
   BREVO_API_KEY=xkeysib-xxxxxxx
   EMAIL_FROM=noreply@seudominio.com
   EMAIL_FROM_NAME=Smart Core Assistant
   ```
3. **Setup DNS (Hostinger painel):**
   - SPF: `v=spf1 include:smtp-relay.brevo.com ~all`
   - DKIM: Gerar no dashboard Brevo, adicionar TXT
   - DMARC: `v=DMARC1; p=none; rua=mailto:alerts@seudominio.com`
4. **Implementar module Rust:**
   - `lib/email_service/` com traits para abstração
   - Implementar Brevo; deixar Postmark como alternativa
   - Adicionar retry logic + logging
5. **Testar com mail-tester.com antes de produção**
6. **Monitorar relatórios DMARC na primeira semana**
