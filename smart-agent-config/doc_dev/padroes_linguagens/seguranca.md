# Diretrizes de Segurança (Implementação e Deploy)

> **Status:** Documento normativo transversal — obrigatório para todas as stacks.
> **Idioma:** Português (documentação). Código e identificadores em inglês.
> **Escopo:** `server/` (Rust), `ia_engine/` (Python), `clients/` (Flutter),
> `evolution/` (Evolution Go) e infraestrutura/deploy.
> **Origem:** Deriva de [00-planejamento-inicial.md](../planejamento/00-planejamento-inicial.md)
> (arquitetura, decisões D1–D6) e
> [01-estrutura-do-projeto.md](../planejamento/01-estrutura-do-projeto.md)
> (regras de acoplamento e contratos).

O sistema processa **dados pessoais sensíveis** de terceiros: conversas reais de
WhatsApp de clientes finais (texto, áudio, imagem, vídeo, documento), números de
telefone, perfis e credenciais de integração de cada tenant. Vazamento, acesso
cruzado entre tenants ou exposição de segredos têm impacto legal (LGPD),
contratual e reputacional direto. **Segurança não é etapa final (F9): é
requisito de cada PR, desde a F0.**

---

## Sumário

1. [Princípios invioláveis](#1-princípios-invioláveis)
2. [Classificação de dados](#2-classificação-de-dados)
3. [Isolamento multi-tenant](#3-isolamento-multi-tenant)
4. [Gestão de segredos e credenciais](#4-gestão-de-segredos-e-credenciais)
5. [Criptografia em trânsito e em repouso](#5-criptografia-em-trânsito-e-em-repouso)
6. [Autenticação e autorização](#6-autenticação-e-autorização)
7. [Validação de entrada e fronteiras](#7-validação-de-entrada-e-fronteiras)
8. [Segurança da camada de IA](#8-segurança-da-camada-de-ia)
9. [Segurança de mídia e cache local](#9-segurança-de-mídia-e-cache-local)
10. [Logging, observabilidade e privacidade](#10-logging-observabilidade-e-privacidade)
11. [Segurança por stack](#11-segurança-por-stack)
12. [Segurança de deploy e infraestrutura](#12-segurança-de-deploy-e-infraestrutura)
13. [LGPD e ciclo de vida do dado](#13-lgpd-e-ciclo-de-vida-do-dado)
14. [Resposta a incidentes](#14-resposta-a-incidentes)
15. [Checklist de segurança por PR](#15-checklist-de-segurança-por-pr)

---

## 1. Princípios invioláveis

Estes princípios são **regra dura** e devem ser revalidados a cada PR. Violação
bloqueia o merge.

| # | Princípio | O que significa na prática |
|---|-----------|----------------------------|
| **S1** | **Defesa em profundidade** | Nenhuma proteção é única. `tenant_id` na aplicação **e** RLS no banco; validação no gateway **e** no domínio; TLS na borda **e** autenticação por serviço. |
| **S2** | **Isolamento total por tenant** | Um tenant nunca acessa dado de outro — em banco, Redis, storage, cache local ou logs. O cruzamento é a falha mais grave possível. |
| **S3** | **Segredo nunca em claro** | Credenciais, tokens e API keys nunca em código, log, mensagem de erro, commit ou banco em texto puro. Sempre em `.env` (git-ignored) ou cifrados em repouso. |
| **S4** | **Menor privilégio (least privilege)** | Cada serviço, usuário de banco, token e container recebe apenas a permissão estritamente necessária. Nada de credencial "admin para tudo". |
| **S5** | **Seguro por padrão (secure by default)** | O comportamento padrão é o mais restritivo: nega acesso, exige contexto de tenant, rejeita payload malformado. Liberar é decisão explícita. |
| **S6** | **Conteúdo de mensagem é confidencial** | O texto/mídia de conversas de clientes é tratado como dado sensível: não vai para log, não vai em telemetria, não vai a terceiro sem necessidade funcional explícita. |
| **S7** | **Falha fechada (fail closed)** | Em erro de autenticação, contexto de tenant ausente ou validação que falha, o sistema **nega** — nunca prossegue "na dúvida". |
| **S8** | **Auditável** | Toda ação sensível (login, acesso a conversa, mudança de credencial, exportação de dados) gera trilha de auditoria com `tenant_id`, ator e timestamp. |

> **Regra de ouro:** se uma mudança enfraquece S1–S8 "temporariamente para
> destravar", ela **não é mergeável**. Abra issue e resolva a causa.

---

## 2. Classificação de dados

Toda informação manipulada cai em uma destas classes. A classe define o
tratamento obrigatório.

| Classe | Exemplos | Tratamento obrigatório |
|--------|----------|------------------------|
| **CRÍTICO — Segredo** | Master key de cifragem, API keys de LLM (OpenAI/Groq), token/apikey de instância Evolution, global API key do Evolution, senha de banco, JWT signing key | Cifrado em repouso (AEAD) ou só em `.env`/secret manager. **Nunca** em log, código, banco em claro, payload de erro. Acesso auditado. |
| **SENSÍVEL — PII / conteúdo** | Conteúdo de mensagens (texto, transcrição, `media_analysis`), binário de mídia, número de telefone do contato, `profile_name`, `push_name` | Cifrado em trânsito (TLS). Isolado por tenant. **Não** logar conteúdo. Retenção definida. Sujeito a LGPD (titular tem direitos). |
| **INTERNO** | `tenant_id`, `message_id`, `ticket` status, etapa de Kanban, metadados de SLA | Isolado por tenant. Pode aparecer em log estruturado (são identificadores, não conteúdo). |
| **PÚBLICO** | Versão do schema de eventos, nomes de features, documentação | Sem restrição. |

**Regras de manuseio:**
- Número de telefone é **PII**: em logs use forma mascarada (`+55119****1234`),
  nunca o número completo.
- `media_analysis`/`media_summary` (transcrição/descrição da IA) é **conteúdo
  sensível** — derivado da conversa do cliente. Trate como a própria mensagem.
- Ao serializar erros para o cliente, **nunca** inclua conteúdo de mensagem nem
  fragmento de segredo. Use mensagem genérica + código de erro + correlation id.

---

## 3. Isolamento multi-tenant

O isolamento é a **garantia de segurança número um** do sistema (decisão D4). A
arquitetura usa banco único com `tenant_id` + RLS — portanto cada barreira
precisa ser implementada com rigor.

### 3.1 Duas barreiras obrigatórias (sempre as duas)

1. **Filtro de aplicação:** toda query carrega `tenant_id` explícito no `WHERE`.
2. **Row-Level Security (RLS):** o PostgreSQL recusa leitura/escrita sem
   `app.current_tenant` setado no contexto da sessão/transação.

Nunca confie em apenas uma. RLS protege contra bug de aplicação; o filtro de
aplicação protege contra policy RLS esquecida em uma tabela nova.

### 3.2 Contexto de tenant por conexão

Toda conexão/transação ao banco que toca dado de domínio **deve** setar o
contexto antes de qualquer query:

```rust
/// Define o tenant atual no contexto da transação para ativar a RLS.
/// Deve ser chamado no início de TODA transação que acessa dados de domínio.
async fn set_tenant_context(tx: &mut Transaction<'_, Postgres>, tenant_id: Uuid) -> Result<(), DbError> {
    // SET LOCAL garante que o escopo é a transação — reverte no commit/rollback.
    sqlx::query("SET LOCAL app.current_tenant = $1")
        .bind(tenant_id.to_string())
        .execute(&mut **tx)
        .await?;
    Ok(())
}
```

- Use **`SET LOCAL`** (escopo de transação), nunca `SET` global — em pool de
  conexões, `SET` vaza o contexto para a próxima requisição (vazamento entre
  tenants).
- A policy padrão de cada tabela de domínio:
  `USING (tenant_id = current_setting('app.current_tenant')::uuid)`.
- Tabela de domínio sem RLS habilitada **não passa em review**.

### 3.3 Isolamento nas demais camadas

| Camada | Regra de isolamento |
|--------|---------------------|
| **Redis** | Namespace por tenant em toda chave: `tenant:{tenant_id}:...`. Streams, cache, presença e pub/sub. Nunca uma chave global com dados de tenant. |
| **Event bus** | Todo evento usa `TenantEnvelope<T>` — sem `tenant_id` no envelope, **não publica**. O consumidor valida o `tenant_id` antes de processar. |
| **Storage de mídia** | Prefixo/bucket por tenant: `media/{tenant_id}/...`. Política de acesso do bucket nega cross-prefix. |
| **Cache local (FFI)** | O `local_engine` **não** mistura tenants. Se o desktop suportar múltiplos logins, o SQLite e o cache de mídia são segregados por tenant. **Nada multi-tenant sensível ou de webhook entra no `local_engine`** (regra de acoplamento). |
| **Logs/tracing** | Todo span carrega `tenant_id` como atributo, mas nunca conteúdo de mensagem. |

### 3.4 Teste de vazamento é obrigatório

Conforme a estratégia de testes do projeto, **testes de RLS usam banco real, não
mocks**. Toda tabela de domínio nova exige:
- Um teste que prova que o tenant A **não enxerga** dado do tenant B.
- Um teste que prova que query **sem contexto** de tenant é rejeitada.

```rust
/// Valida que a RLS impede acesso a dados de outro tenant.
#[tokio::test]
async fn test_should_deny_cross_tenant_access() {
    let pool = setup_test_db().await;
    let mut tx = pool.begin().await.expect("begin tx");

    set_tenant_context(&mut tx, TENANT_A_ID).await.expect("set context");
    insert_message_for_tenant(&mut tx, TENANT_B_ID).await; // via path admin

    let messages = fetch_messages(&mut tx).await;
    assert!(messages.is_empty(), "VAZAMENTO: tenant A viu dados do tenant B");

    tx.rollback().await.expect("rollback");
}
```

---

## 4. Gestão de segredos e credenciais

### 4.1 Onde cada segredo vive

| Segredo | Repouso | Acesso |
|---------|---------|--------|
| Senha do PostgreSQL, Redis e credenciais R2 (`S3_*`) | `.env` (dev) / secret manager (prod) | Variável de ambiente no processo |
| JWT signing key, master encryption key | `.env` / secret manager | Variável de ambiente; nunca em banco |
| API keys de LLM por tenant (`tenant_config.api_keys`) | **Banco, cifrado (AEAD)** | Decifrado em memória só no momento do uso |
| Token/apikey de instância Evolution | **Banco, cifrado (AEAD)** | Decifrado em memória só no envio outbound |
| Global API key do Evolution | `.env` / secret manager | Apenas o `control_plane` usa (admin de instâncias) |

### 4.2 Regras absolutas

- **Nunca** comitar segredo. `.env` é git-ignored; o repositório versiona apenas
  `.env.example` com chaves vazias/placeholder.
- **Nunca** hardcodar credencial em código (Rust, Python ou Dart). Em Rust, o
  segredo entra por env/config; em Python, via `pydantic-settings`/
  `python-decouple` lendo `.env`.
- **Nunca** logar segredo, nem parcialmente. Não logue "token começa com sk-...".
- **Nunca** retornar segredo em resposta de API ou mensagem de erro.
- Segredo em memória deve ter vida curta. Em Rust, prefira tipos que zeram a
  memória ao serem dropados (ex.: `secrecy::Secret<String>` / `zeroize`) para
  master key e tokens decifrados.

### 4.3 Cifragem em repouso de credenciais (AEAD)

Credenciais por tenant ficam cifradas no banco (decisão herdada da v1, que usa
Fernet via `encrypt_value`/`decrypt_value`). Na v2, padronize **AEAD**
(AES-256-GCM ou ChaCha20-Poly1305) com master key fora do banco:

```rust
/// Cifra uma credencial de tenant para armazenamento em repouso.
/// A master key vem do ambiente (nunca do banco). Cada valor usa um nonce único.
pub fn encrypt_credential(plaintext: &str, master_key: &MasterKey) -> Result<EncryptedBlob, CryptoError> {
    let nonce = generate_random_nonce(); // 96 bits, único por operação
    let ciphertext = aead_encrypt(master_key.expose(), &nonce, plaintext.as_bytes())?;
    // Persistir nonce + ciphertext juntos; sem o nonce não há como decifrar.
    Ok(EncryptedBlob { nonce, ciphertext })
}
```

- Master key **nunca** no banco junto com o dado cifrado.
- Nonce único por operação (reuso de nonce em GCM quebra a confidencialidade).
- Round-trip cifra/decifra coberto por teste; nunca grave credencial em claro,
  nem "temporariamente".
- Planeje **rotação de chave** (versionar a master key: `key_id` no blob) desde o
  início — trocar chave não pode exigir reescrever o schema.

---

## 5. Criptografia em trânsito e em repouso

### 5.1 Em trânsito (TLS sempre)

- **Borda → cliente:** proxy reverso (Nginx/Caddy) termina **TLS 1.2+** (preferir
  1.3). HSTS habilitado. `proxy_buffering off` para WebSocket sem quebrar o TLS.
- **Webhook Evolution → messaging_gateway:** HTTPS obrigatório.
- **worker → ia_engine (gRPC/HTTP):** mesmo dentro da VM, prefira TLS ou canal
  isolado (loopback/rede interna fechada). Nunca exponha o `ia_engine` à
  internet.
- **Serviços → PostgreSQL/Redis:** conexão com TLS quando atravessar
  fronteira de host; em VM única, restringir por firewall/bind em loopback.
- WebSocket: `wss://` em produção, nunca `ws://`.

### 5.2 Em repouso

- **Credenciais por tenant:** AEAD (§4.3).
- **Banco:** cifragem de disco/volume na VM. Backups cifrados.
- **Mídia transitória (Cloudflare R2):** acesso sempre por HTTPS; credencial com
  escopo mínimo e URLs pré-assinadas de vida curta (§9).
- **Cache local (FFI/Windows):** o disco do atendente guarda conteúdo sensível —
  ver §9.4 para proteção do cache local.

---

## 6. Autenticação e autorização

### 6.1 Autenticação de clientes (Flutter → runtime_api)

- Tokens de acesso de **vida curta** + **refresh token** rotativo. Reaproveitar o
  modelo da v1 (`tenant_user`/`tenant_invite`).
- JWT assinado (ou tokens opacos validados no servidor). Signing key em `.env`/
  secret manager, nunca no código nem no cliente.
- Token sempre carrega/resolve `tenant_id` + papel; o servidor **deriva o
  `tenant_id` do token**, nunca do corpo da requisição enviado pelo cliente.
- Expiração curta; refresh com detecção de reuso (revoga a família ao detectar
  token de refresh reutilizado).

### 6.2 Autorização (RBAC por tenant)

- RBAC herdado da v1: `role` (admin/manager/staff/viewer) +
  `module_permissions` (json) + `flow_permissions` (fluxos liberados).
- Autorização verificada **no servidor**, em toda operação — nunca confie em
  controle de acesso feito só na UI Flutter.
- Acesso negado é o **padrão** (S5): se a permissão não foi concedida
  explicitamente, nega.

### 6.3 Autenticação entre serviços e do Evolution

- **Webhook do Evolution Go:** o `messaging_gateway` **valida origem/assinatura**
  e resolve o `tenant_id` pela instância (`instance`/`apikey`) antes de qualquer
  coisa. Webhook sem assinatura válida é descartado (fail closed).
- **Autenticação dupla do Evolution:** *global API key* (admin: criar/listar/
  deletar instâncias — só no `control_plane`) × *token por instância* (enviar,
  conectar, status). Nunca use a global key para envio outbound.
- **Bancos do Evolution** (`evogo_auth`, `evogo_users`) são separados do banco da
  aplicação e não devem ser acessados pela aplicação.

```rust
/// Valida que o gateway rejeita webhooks com assinatura inválida (fail closed).
#[tokio::test]
async fn test_should_reject_webhook_when_signature_is_invalid() {
    let gateway = WebhookHandler::new(mock_validator(false));
    let result = gateway.handle(fake_payload()).await;
    assert!(result.is_err(), "webhook sem assinatura válida deve ser rejeitado");
}
```

---

## 7. Validação de entrada e fronteiras

Todo dado que cruza uma fronteira (webhook, API, FFI, contrato gRPC) é
**não confiável** até ser validado.

- **Webhook (messaging_gateway):** valide assinatura, tamanho máximo do payload,
  formato e tipos esperados antes de persistir o bruto. O gateway **não executa
  regra de negócio** — mas valida e autentica (princípio arquitetural central).
- **API (runtime_api):** valide todos os campos de comando/consulta. Em Rust,
  tipos fortes + parsing na borda; em Python, `pydantic` valida o payload
  (proibido `Any` em produção).
- **Limites:** tamanho máximo de upload de mídia, comprimento de texto, número de
  itens em lote. Rejeite o excedente (evita DoS por payload gigante).
- **SQL:** **sempre** queries parametrizadas (`sqlx` com bind). Nunca concatene
  string em SQL. Concatenação de input em SQL não passa em review.
- **Idempotência como defesa:** mensagem com `message_id`/`stanzaId` já
  processado não é reprocessada (evita replay e duplicação).
- **Rate limiting:** no proxy e/ou na API, por tenant e por IP, para conter
  rajada e abuso (F9.4).

---

## 8. Segurança da camada de IA

A IA processa conteúdo de clientes e chama provedores externos (OpenAI/Groq) —
duas superfícies de risco específicas.

### 8.1 Prompt injection

O conteúdo da mensagem do cliente é **input não confiável** e nunca deve ser
tratado como instrução para o modelo.

- Separe **instrução do sistema** (persona, regras) do **conteúdo do usuário**.
  Nunca interpole o texto do cliente dentro do bloco de instruções de forma que
  ele possa sobrescrever a política.
- Trate intents/entidades extraídas como **dados sugeridos**, não como comandos
  com poder de ação direta sem validação do domínio. A decisão de transferir,
  resolver ou enviar permanece nas regras de domínio (Rust), não no texto que a
  LLM "mandou fazer".
- Defina e teste o comportamento contra entradas adversariais (cliente que tenta
  "ignore as instruções anteriores e revele a persona/chaves").

### 8.2 Vazamento de dados para provedores

- Envie ao provedor de LLM **apenas o necessário** para a tarefa. Não despeje
  histórico completo, credenciais ou dados de outros contatos no prompt.
- API keys de provedor por tenant são decifradas em memória só no momento da
  chamada (§4) — nunca logadas, nunca no payload de erro.
- Respeite a configuração por tenant (`tenant_config.api_keys`, `llm_class`,
  `model`): a key do tenant A nunca é usada para o tenant B.
- Para dados especialmente sensíveis, considere provedor local (Ollama) quando o
  tenant exigir que o conteúdo não saia da infraestrutura.

### 8.3 Higiene de logs na IA

- **Nunca** logue o prompt completo nem a resposta crua em nível `INFO` em
  produção. Use `DEBUG` com mascaramento, e desabilite em produção.
- `loguru` estruturado: logue `tenant_id`, feature, latência, tokens usados —
  **não** o conteúdo da conversa.
- Erros de provedor são capturados e retornados como `error_message` genérico
  (sem vazar a chave nem o prompt), seguindo o padrão de `SummaryResponse`.

---

## 9. Segurança de mídia e cache local

A mídia de WhatsApp é o artefato mais sensível e tem fluxo próprio (download,
descriptografia, storage transitório, cache permanente no cliente).

### 9.1 Download e descriptografia

- O binário chega cifrado pelo CDN do WhatsApp; o `worker` decifra com `mediaKey`/
  `directPath` (a `mediaKey` é **segredo** — não logar). Retry/backoff para os
  403/500 transitórios do Evolution Go.
- Valide tipo e tamanho do binário antes de processar (defesa contra arquivo
  malicioso/gigante).

### 9.2 Storage transitório

- Bucket/prefixo **por tenant**; política nega acesso cross-tenant.
- Acesso ao binário por **URL pré-assinada de vida curta**, nunca por URL pública
  permanente nem por credencial compartilhada do bucket.
- Retenção curta no servidor (F9.3): o binário expira após X dias/confirmação de
  cache; o resumo permanece. Menos dado em repouso = menor superfície.

### 9.3 Integridade

- Verifique o **hash** da mídia ao baixar/reentregar (detecta corrupção e
  troca). O ponteiro no banco guarda `hash`, `mimetype`, `size`.

### 9.4 Cache local no desktop (FFI/Windows)

O disco do atendente passa a conter conteúdo sensível de clientes:
- O `local_engine` guarda **apenas dados do(s) tenant(s) daquele atendente**, e
  segregados por tenant. Nunca dado de webhook bruto nem de múltiplos tenants
  misturados.
- Recomenda-se cifrar o cache local em repouso (SQLite + arquivos de mídia) com
  chave derivada da sessão do usuário, para que o disco isolado não exponha
  conversas.
- Ao logout/troca de tenant, o cache do tenant anterior deve ser inacessível
  (limpar ou tornar indecifrável).
- O cache é **performance, não fonte da verdade** — pode ser descartado sem perda
  (a verdade está no servidor).

---

## 10. Logging, observabilidade e privacidade

Logs são uma fonte clássica de vazamento. Regras firmes:

- **Proibido logar conteúdo de mensagem**, transcrição, descrição de mídia,
  prompt ou resposta da IA em produção.
- **Proibido logar segredo** (qualquer credencial, token, key, `mediaKey`),
  mesmo parcial.
- **PII mascarada:** telefone como `+55119****1234`; nunca o número completo nem o
  `profile_name` em texto livre de log.
- **O que logar:** `tenant_id`, `message_id`, tipo de evento, decisão de domínio,
  latência, status — identificadores e métricas, não conteúdo.
- Em Rust use `tracing` estruturado; em Python use `loguru` (nunca `print()`).
  Span sempre com `tenant_id` quando presente.
- **Erros para o cliente:** mensagem genérica + código + correlation id. O
  detalhe técnico fica no log interno, sem conteúdo sensível.
- **Trilha de auditoria** (S8): registre quem acessou/exportou/alterou dado
  sensível, com `tenant_id`, ator, ação e timestamp — separada do log
  operacional e com retenção própria.

---

## 11. Segurança por stack

### 11.1 Rust (`server/`)

- **Sem `unsafe`** em produção (já é regra), salvo a FFI do `local_engine` com
  `// SAFETY:`. `unsafe` é superfície de memória — mantenha zero.
- **Sem `unwrap`/`expect`/`panic`** em código de produção (já é regra clippy
  `deny`): um panic em handler é um vetor de DoS. Propague com `Result`.
- Queries sempre parametrizadas (`sqlx`).
- `cargo audit` (ou `cargo deny`) no CI para vulnerabilidades conhecidas em
  dependências; `Cargo.lock` versionado.
- Segredos via tipos que evitam vazamento acidental em `Debug`/log (`secrecy`/
  `zeroize` para master key e tokens decifrados).

### 11.2 Python (`ia_engine/`)

- **Sem `Any`** em produção (já é regra); valide payloads com `pydantic`.
- Segredos via `pydantic-settings`/`python-decouple` lendo `.env` — nunca no
  código.
- Trate exceções de provedor sem vazar prompt/chave (padrão `SummaryResponse`).
- `uv.lock` versionado; rode varredura de dependências (ex.: `pip-audit`) no CI.
- Nunca `print()` (já é regra `T20`/`ruff`) — vazaria conteúdo no stdout.

### 11.3 Flutter (`clients/`)

- **Cliente fino:** nenhuma regra de autorização confiável vive na UI — o
  servidor é a autoridade. A UI apenas reflete permissões.
- **Sem segredo no app:** não embuta API keys nem signing keys no binário/web —
  são extraíveis. O cliente só guarda o token de sessão.
- Armazenamento seguro do token: storage seguro da plataforma (não em texto puro
  em `SharedPreferences`).
- `flutter_web`: cuidado com XSS e armazenamento no browser; nunca persistir
  conteúdo sensível além do necessário; `wss://`/`https://` sempre.
- `avoid_print: true` (já é regra) — evita vazar dado no console.

### 11.4 Evolution Go (`evolution/`)

- `DATABASE_SAVE_MESSAGES=false` (config de referência) reduz dado em repouso no
  Evolution — manter.
- Bancos `evogo_auth`/`evogo_users` isolados; credenciais via env, não comitadas.
- Webhook configurado para apontar só ao `messaging_gateway` por HTTPS.
- Global API key restrita ao `control_plane`; tokens de instância por tenant.

---

## 12. Segurança de deploy e infraestrutura

Deploy inicial em **Hostinger KVM2** (uma VM) — endurecer o host é parte do
trabalho.

### 12.1 Hardening do host

- Firewall: exponha **apenas** 443 (e 80 redirecionando para 443) à internet.
  PostgreSQL, Redis, `ia_engine` e binários internos **não** ficam
  expostos — bind em loopback/rede interna.
- SSH com chave (sem senha), porta restrita, root login desabilitado.
- Atualizações de SO automáticas para patches de segurança.
- Cada serviço roda com usuário de menor privilégio; containers não rodam como
  root.

### 12.2 Segredos no deploy e CI/CD

- Segredos via secret manager do provedor ou variáveis de ambiente injetadas no
  deploy — **nunca** no repositório, nunca em imagem Docker, nunca em log de
  pipeline.
- Pipeline mascara segredos na saída; artefatos de build não contêm `.env`.
- Imagens Docker: base mínima, sem ferramentas desnecessárias, escaneadas para
  CVEs antes do deploy.

### 12.3 Proxy reverso

- TLS 1.2+ (preferir 1.3), HSTS, ciphers fortes. Renovação automática de
  certificado.
- `proxy_buffering off` para WebSocket (sem quebrar TLS).
- Rate limiting e limite de tamanho de corpo no proxy.

### 12.4 Backups e recuperação

- Backups do PostgreSQL **cifrados**, testados (restauração validada
  periodicamente), com retenção definida e acesso restrito.
- Backup nunca em bucket público; chave de cifragem separada do backup.

---

## 13. LGPD e ciclo de vida do dado

O sistema processa dados pessoais de **clientes finais dos tenants**. O tenant é
controlador; a plataforma é operadora. Implicações que o código precisa suportar:

- **Minimização:** colete/armazene só o necessário. Resumo + ponteiro de mídia no
  servidor; binário com retenção curta (já é a arquitetura — reforça LGPD).
- **Retenção e expiração:** política de TTL para mídia (F9.3) e para dados de
  conversa conforme contrato com o tenant. Dado sem propósito ativo é candidato a
  expurgo.
- **Direito de eliminação:** prever caminho para apagar dados de um contato/
  conversa a pedido do titular (via tenant) — incluindo cache, storage e
  backups na medida do exequível. O isolamento por tenant facilita isso.
- **Portabilidade/acesso:** prever exportação dos dados de um titular de forma
  estruturada (sujeita a RBAC e auditoria).
- **Rastreabilidade:** trilha de auditoria (S8) sustenta a prestação de contas
  exigida pela LGPD.
- **Sub-operadores:** provedores de LLM (OpenAI/Groq) recebem conteúdo — isso
  deve estar documentado e coberto contratualmente; oferecer alternativa local
  (Ollama) quando o tenant exigir.

> Decisões de retenção e base legal são acordadas com cada tenant, mas o
> **código deve oferecer os mecanismos** (expurgo, exportação, isolamento) desde
> o início.

---

## 14. Resposta a incidentes

- **Detecção:** alertas para anomalias — picos de erro de autenticação, falha de
  contexto RLS, acesso cross-tenant negado em volume, uso anormal de quota.
- **Contenção:** capacidade de revogar tokens (rotação de signing key), desabilitar
  instância Evolution comprometida e rotacionar credenciais cifradas por tenant
  sem downtime de schema (§4.3, `key_id`).
- **Rotação de segredos:** procedimento documentado para trocar master key, JWT
  signing key, credenciais de banco e API keys, com versionamento.
- **Comunicação:** vazamento de dado pessoal aciona obrigação de notificação
  (LGPD) — ter o processo definido, não improvisado.
- **Post-mortem:** todo incidente gera análise de causa raiz e ação corretiva
  rastreável (vira teste/regra de review quando aplicável).

---

## 15. Checklist de segurança por PR

Complementa o checklist transversal de
[02-fases-desenvolvimento.md](../planejamento/02-fases-desenvolvimento.md). Toda
mudança que toca dado, fronteira ou credencial deve passar por:

- [ ] **Isolamento:** `tenant_id` em toda query nova **e** policy RLS coberta por
      teste de vazamento (tenant A não vê B; sem contexto é rejeitado).
- [ ] **Contexto:** `SET LOCAL app.current_tenant` em toda transação de domínio
      (nunca `SET` global em pool).
- [ ] **Segredos:** nenhum segredo em código/log/erro/commit; credenciais por
      tenant cifradas em repouso (AEAD); `.env` git-ignored.
- [ ] **Criptografia:** TLS nas fronteiras; `wss://` em realtime; mídia por URL
      pré-assinada de vida curta.
- [ ] **Auth:** `tenant_id` derivado do token (não do corpo); RBAC verificado no
      servidor; fail closed em auth/validação.
- [ ] **Validação:** input de fronteira validado (pydantic/tipos fortes); SQL
      parametrizado; limites de tamanho; idempotência preservada.
- [ ] **IA:** conteúdo do cliente tratado como não confiável (anti prompt
      injection); só o necessário enviado ao provedor; key do tenant correta.
- [ ] **Logs:** sem conteúdo de mensagem, sem PII em claro, sem segredo; telefone
      mascarado; span com `tenant_id`.
- [ ] **Mídia/cache:** storage e cache local segregados por tenant; `mediaKey`
      não logada; cache local não expõe conteúdo após logout.
- [ ] **Erros ao cliente:** genéricos + correlation id, sem vazar conteúdo nem
      segredo.
- [ ] **Dependências:** sem CVE conhecida nova (`cargo audit`/`pip-audit`); locks
      versionados.

> **Bloqueio de merge:** qualquer item de isolamento (S2), segredo (S3) ou fail
> closed (S7) reprovado **impede o merge** até correção da causa raiz.

---

*Documento normativo de segurança. Revisado a cada fase concluída e sempre que
uma nova superfície de dado sensível for introduzida.*
