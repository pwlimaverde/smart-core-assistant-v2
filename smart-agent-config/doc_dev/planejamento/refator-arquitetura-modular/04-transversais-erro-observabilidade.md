# 04 — Padrão Agnóstico de Erro e Observabilidade

> **Status:** Planejamento (a revisar). **Responde à preocupação do dono** sobre
> erro/observabilidade serem **convenções padronizadas e agnósticas à tecnologia**.
> **Idioma:** pt-br na documentação; identificadores em inglês.
> **Pré-leitura:** [03-acesso-dados-orientado-eventos.md](./03-acesso-dados-orientado-eventos.md).

---

## 1. O princípio (RA5)

Erro e observabilidade **não são serviços** — são **convenções**. Uma convenção é:

- um **formato padronizado** (schema), igual para todas as tecnologias (Rust, Python, Dart);
- uma **biblioteca** que cada módulo compila para falar/entender esse formato;
- **nada de processo no meio** — o que cruza o fio é só **dado** (envelope de erro,
  contexto de trace).

> **Agnóstico à tecnologia = o padrão vive no *schema*, não na linguagem.** Um erro da
> IA (Python) e um erro do `data_postgres` (Rust) viram o **mesmo `ErrorEnvelope`** com o
> **mesmo `ErrorCode`**. Quem lê não precisa saber de onde veio.

---

## 2. O padrão de erro (schema único, 3 idiomas)

### 2.1 Taxonomia canônica (`ErrorCode`)
Definida **uma vez** no schema do contrato e **gerada** para os três idiomas (doc 02 §1),
evitando divergência manual:

```fbs
// contracts/schemas/errors.fbs  (comentários em pt-br)
namespace smartcore.contracts;

enum ErrorCategory : byte {
  VALIDATION,    // entrada inválida (campo, formato)
  AUTH,          // credencial/sessão (login, token)
  PERMISSION,    // autorizado mas sem escopo
  CONFLICT,      // estado/unicidade (email já existe)
  NOT_FOUND,
  RATE_LIMIT,    // excesso de tentativas
  DEPENDENCY,    // falha de dependência externa (LLM, storage)
  TIMEOUT,
  INTERNAL       // bug/inesperado
}

enum Severity : byte { INFO, WARNING, ERROR, CRITICAL }

table ErrorEnvelope {
  code:         string;     // canônico, ex.: "AUTH_INVALID_CREDENTIALS", "AI_TIMEOUT"
  category:     ErrorCategory;
  severity:     Severity;
  message:      string;     // técnica, p/ log/dev (sem dado sensível)
  user_message: string;     // CHAVE i18n, ex.: "errors.auth.invalid_credentials" — cliente resolve no idioma
  user_message_fallback: string; // texto seguro p/ consumidores sem catálogo i18n (log/serviço)
  retryable:    bool;       // o chamador pode tentar de novo?
  trace_id:     string;     // costura com a observabilidade (§4)
  source_svc:   string;     // origem, ex.: "ia_engine@vm-gpu"
  details:      [KeyValue]; // contexto extra não sensível (campo, limite, etc.)
  occurred_at:  long;       // epoch millis
}
```

> **Reconciliação com o implementado:** o `error_core` **já tem** `ErrorCode`/`ErrorCategory`/
> `Severity`/`AppError` + `public_message()` e a regra de **não remover/renomear sem
> deprecação** (`code.rs`). Esta tabela **estende** a existente (hoje: Auth, Storage,
> Database, Cache, Validation, Internal) — acrescenta `PERMISSION`/`RATE_LIMIT`/`TIMEOUT`/
> `DEPENDENCY`/`NOT_FOUND`/`CONFLICT`, os campos `user_message*`/`retryable`/`source_svc`/
> `trace_id` e o `ErrorEnvelope` serializável. Não é greenfield: o schema canônico nasce
> da taxonomia já em uso.

### 2.2 Biblioteca por tecnologia (mesma tabela)
| Tecnologia | Biblioteca | Papel |
|---|---|---|
| Rust | crate `error_core` | erro nativo (`AppError`, `DbError`, …) ⇄ `ErrorEnvelope` |
| Python (`ia_engine`) | `errors.py` (gerado) | exceção Python ⇄ `ErrorEnvelope` |
| Dart (Flutter) | `errors.dart` (gerado) | `ErrorEnvelope` → mensagem/ação na UI |

Cada uma sabe **mapear o erro nativo dela para o código canônico** e **reconstruir** a
partir do código. O **significado do código é a convenção** (compilada nos dois lados);
o fio carrega só os campos.

---

## 3. As três saídas de um erro (rotas independentes)

Um erro normalizado pode disparar **até três destinos**, decididos por
`category`/`severity` — não por quem o produziu:

```
                     ┌─► (1) LOG          → observabilidade (sempre)   → coletor OTLP / LGTM
ErrorEnvelope ───────┼─► (2) AUDITORIA    → Redis Streams (segurança) → consolida no data_postgres
                     └─► (3) PROPAGAÇÃO   → resposta ao chamador/UI (user_message)
```

| Saída | Quando dispara | Onde mora | Vida |
|---|---|---|---|
| **(1) Log** | **sempre** | observabilidade (JSON estruturado) → OTLP/LGTM | operacional, retenção curta |
| **(2) Auditoria** | `category ∈ {AUTH, PERMISSION, RATE_LIMIT}` ou mutação de dado sensível | **Redis Streams (segurança)** → consumidor consolida em **batch** na tabela de auditoria do `data_postgres` | durável, consultável, compliance; absorve rajada sem atrasar a ação |
| **(3) Propagação** | quando há um chamador esperando resposta | `ErrorEnvelope` (com `user_message`) no protocolo de origem | efêmero |

> **Distinção que o dono pediu para clarear:** *log* é para operação/debug; *auditoria* é
> registro durável de eventos sensíveis (login falho, acesso negado); *propagação* é o
> que a UI recebe para tratar. São **três sinks**, um mesmo `ErrorEnvelope` os alimenta.

### 3.1 Tabela de roteamento (exemplos)
| `code` | category | severity | Log | Auditoria | UI (`user_message`) |
|---|---|---|---|---|---|
| `AUTH_INVALID_CREDENTIALS` | AUTH | INFO | ✓ | ✓ (login falho) | "E-mail ou senha inválidos" |
| `PERMISSION_DENIED` | PERMISSION | WARNING | ✓ | ✓ (acesso negado) | "Sem permissão para esta ação" |
| `AI_TIMEOUT` | TIMEOUT | WARNING | ✓ | ✗ | (degrada; opcional "IA indisponível") |
| `VALIDATION_PASSWORD_WEAK` | VALIDATION | INFO | ✓ | ✗ | "Senha não atende aos requisitos" |
| `DB_CONFLICT_EMAIL` | CONFLICT | INFO | ✓ | ✗ | "E-mail já cadastrado" |
| `INTERNAL` | INTERNAL | ERROR | ✓ | ✗ | "Erro interno, tente novamente" (sem detalhe) |

> Os textos da coluna "UI" são **ilustrativos**: no fio viaja a **chave i18n** (ex.:
> `errors.auth.invalid_credentials`) + `user_message_fallback`; o cliente resolve o texto
> final no idioma do usuário.

---

## 4. O padrão de observabilidade (log + trace agnósticos)

### 4.1 Schema de log estruturado (mesma forma em todo serviço)
Toda tecnologia emite log **JSON** com **os mesmos campos** — é a convenção:

```json
{
  "ts": "2026-06-05T12:34:56.789Z",
  "level": "warning",
  "service": "ia_engine",
  "code": "AI_TIMEOUT",
  "category": "TIMEOUT",
  "message": "LLM provider timeout after 8s",
  "trace_id": "0af7651916cd43dd8448eb211c80319c",
  "span_id": "b7ad6b7169203331",
  "tenant_id": "uuid-do-tenant"
}
```

| Idioma | Como emite a mesma forma |
|---|---|
| Rust | `tracing` + camada JSON (crate `observability`) |
| Python | `logging`/`structlog` configurado com os mesmos campos |
| Dart | logger com o mesmo esquema (quando útil no cliente) |

### 4.2 Trace distribuído (o `traceparent` no envelope)
O `traceparent` (W3C Trace Context) viaja **dentro do Envelope** (doc 02 §2). Cada salto
abre um span filho; **todos** os serviços exportam para o **coletor OTLP central** (stack
LGTM). Resultado: um erro carrega o `trace_id` que **liga o log, a auditoria e o span**
da mesma operação — mesmo entre VMs.

```
ui (span A) ─traceparent=T─► runtime_api (span B) ─T─► worker (span C) ─T─► ia_engine (span D)
   todos com trace_id=T → coletor OTLP → 1 trace; o ErrorEnvelope.trace_id = T amarra tudo
```

> Por isso observabilidade **não precisa ser serviço**: quem "junta" é o **coletor OTLP**
> (infra de telemetria, já planejada no doc 05), não um módulo de domínio. Cada serviço só
> **emite** com a convenção e **propaga** o `traceparent`.

---

## 5. Ciclo de vida do erro (agnóstico, ponta a ponta)

```
[1] ORIGEM (qualquer tech)        → erro nativo (exceção Python / Result Rust / …)
        │
[2] NORMALIZAÇÃO (na borda do      → erro nativo → ErrorEnvelope (code canônico, trace_id)
    módulo + garantida no servidor)
        │
[3] ROTEAMENTO (decisão por        ├─► LOG (observabilidade)        [sempre]
    category/severity)             ├─► AUDITORIA (evento→data_postgres) [se sensível]
        │                          └─► PROPAGAÇÃO (resposta na origem) [se há chamador]
[4] TRATAMENTO (UI/serviço)        → mapeia code → ação (mostra user_message, re-auth, retry)
```

- **[2] Normalização "no servidor":** módulos **devem** emitir já canônico, mas o servidor
  (worker/runtime_api) tem uma **camada de normalização defensiva** — se um erro chegar
  cru (ex.: stack do Python), ele é convertido em `ErrorEnvelope` antes de logar/propagar.
  É o "processado pelo servidor, onde será normalizado" que o dono descreveu.

---

## 6. Exemplo A — erro da IA (do dono)

> *"O módulo de IA lança um erro; esse erro precisa ser processado pelo servidor, onde
> será normalizado, lançado no log gerenciado pela observabilidade, e a UI/serviço
> precisa tratar."*

```
ia_engine (Python)                worker (Rust)                       runtime_api → UI
   │ timeout no LLM                   │                                   │
   │ raise → errors.py:               │                                   │
   │   ErrorEnvelope{                 │                                   │
   │     code:"AI_TIMEOUT",           │                                   │
   │     category:TIMEOUT,            │                                   │
   │     retryable:true,              │                                   │
   │     trace_id:T, severity:WARNING}│                                   │
   │  ── resposta (FlatBuffers) ────► │ [2] normaliza (já canônico)       │
   │                                  │ [3a] LOG (observability, warn, T) │
   │                                  │ retryable → retry/backoff         │
   │                                  │   exauriu? → degrada (fallback)   │
   │                                  │   OU propaga AI_UNAVAILABLE ─────► │ [3c] resposta
   │                                  │                                   │  ErrorEnvelope
   │                                  │                                   │  └─ UI: "IA
   │                                  │                                   │     indisponível,
   │                                  │                                   │     tente depois"
```

- **Normalização:** o `ia_engine` já emite `AI_TIMEOUT` canônico; o worker confirma
  (camada defensiva) — nada de stack Python vazando.
- **Log:** observabilidade registra com `trace_id=T`, ligando ao span da IA.
- **Tratamento:** worker decide (retry → degradação → propagação). A UI recebe um
  `user_message` seguro e reage. Auditoria **não** dispara (TIMEOUT não é sensível).

---

## 7. Exemplo B — senha errada (do dono)

> *"Usuário coloca a senha errada; esse erro precisa ser propagado na auditoria, e a UI
> precisa receber a informação para mostrar ao usuário."*

```
UI ─login(email,senha)─► runtime_api / application ─(RPC direto, síncrono)─► data_postgres
                               │                                              │ verifica senha
                               │  ◄──────── ErrorEnvelope{ ───────────────────┘ (Argon2) → falha
                               │     code:"AUTH_INVALID_CREDENTIALS",
                               │     category:AUTH, severity:INFO,
                               │     user_message:"E-mail ou senha inválidos",
                               │     retryable:false, trace_id:T }
                               │
                  [3a] LOG (observability, info/security, T)
                  [3b] AUDITORIA → XADD "login_failed"{ip_hash, ts, trace_id} no Redis Streams (segurança)
                          └─► consumidor consolida em batch na tabela de auditoria (data_postgres)
                  + incrementa rate-limit (data_redis)
                               │
                  [3c] PROPAGAÇÃO ──► UI: mostra "E-mail ou senha inválidos"
```

- **Auditoria:** `category=AUTH` ⇒ dispara o sink (2) — `login_failed` vai por **Redis
  Streams de segurança** (`XADD`, fire-and-forget, absorve a rajada de um brute-force) e um
  consumidor **consolida em batch** na tabela de auditoria do `data_postgres` (durável,
  consultável). Não atrasa a resposta do login.
- **Propagação:** a UI recebe `user_message` **genérico** ("E-mail ou senha inválidos") —
  **de propósito**, para não permitir enumeração de usuários (segurança, doc 09 §3.2/3.5).
  O `message` técnico (que diferencia "usuário não existe" de "senha errada") fica **só no
  log/auditoria**, nunca na UI.
- **Tratamento na UI:** mapeia `AUTH_INVALID_CREDENTIALS` → exibe o aviso no formulário.

> Repare: o **mesmo `ErrorEnvelope`** alimentou os três sinks com **projeções
> diferentes** — log técnico, auditoria durável, mensagem segura. É essa separação que
> mantém o padrão organizado e agnóstico.

---

## 8. Tabela-resumo: serviço × convenção

| Componente | Classe | Vira processo? | Atravessa VM via |
|---|---|---|---|
| apps (`worker`, `runtime_api`, …), `ia_engine`, `data_*` | serviço | sim | endpoint (e codec) configurável |
| **`error_core`** | **convenção** | **não** | `ErrorEnvelope` (dado) + lib nos dois lados |
| **`observability`** | **convenção** | **não** | `traceparent` (dado) + coletor OTLP central |
| **`contracts` / `transport`** | **convenção** | **não** | mensagens (dado) + lib compilada |
| **auditoria** | **dado** (não é módulo) | — | evento → tabela no `data_postgres` |

---

## 9. Decisões em aberto (para a revisão)

1. ✅ **RESOLVIDO — `ErrorCode`/`ErrorCategory` gerados do schema canônico** (`.fbs`) para
   os 3 idiomas, pelo mesmo pipeline do contrato (doc 02 §1). Fonte única, sem drift.
2. ✅ **RESOLVIDO — Auditoria por Redis Streams → consolida.** Eventos de segurança/auth
   vão por **Redis Streams** (`XADD`, fire-and-forget) e um consumidor **consolida em
   batch** na tabela de auditoria do `data_postgres`. Auditoria de mudança de estado de
   negócio viaja no **outbox** junto da própria escrita.
3. ✅ **RESOLVIDO — `user_message` é chave i18n + fallback.** O campo carrega a **chave**
   (ex.: `errors.auth.invalid_credentials`) que o cliente resolve no idioma; o
   `user_message_fallback` guarda um texto seguro para consumidores sem catálogo.
4. ✅ **RESOLVIDO — Coletor OTLP cedo** (já na fase de 1 VM) para validar a propagação de
   trace distribuído desde o início.

---

## 10. Próximo documento

Como sair do estado atual (crates in-process) para este alvo, com refator faseado:
[05-refator-estado-atual.md](./05-refator-estado-atual.md).

---

*Padrão agnóstico de erro e observabilidade. Sujeito a refinamento.*
