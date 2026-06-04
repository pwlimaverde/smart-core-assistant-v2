# 07 — Crate de Contratos (`contracts`)

> **Status:** Planejamento (a implementar). Fundação transversal — base de todas
> as camadas; precede o domínio.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Lacuna identificada na revisão da base. Corresponde à **Etapa 0.6**
> de [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md) e ao crate
> `contracts` de [00-planejamento-inicial.md §5](./00-planejamento-inicial.md) /
> [01-estrutura-do-projeto.md §4-§5](./01-estrutura-do-projeto.md). É a casa
> definitiva do `TenantEnvelope`, hoje provisoriamente em `infrastructure_redis`.

---

## 1. Objetivo

Concentrar em uma única crate **sem I/O** (`server/crates/contracts`) **todos os
tipos da fronteira entre serviços/camadas**: DTOs, eventos internos do barramento,
o envelope multi-tenant (`TenantEnvelope<T>`) e os tipos gerados a partir dos
`.proto`. É a dependência comum de `domain_*`, `application`, `infrastructure_*`
e dos `apps/*` — garantindo um **único** lugar para o contrato e evitando
divergência de schema entre produtor e consumidor.

> Regra de acoplamento (doc 01 §4): "Contratos em `server/crates/contracts/`".
> Todos os DTOs, eventos e envelopes da comunicação inter-serviço vivem aqui,
> incluindo o `TenantEnvelope<T>`.

> **⚠️ Reconciliação com o estado atual:** a crate `contracts` está sendo
> **bootstrapada pelo módulo de autenticação** (plano canônico
> `user-auth-module`, em andamento), que a cria já com `proto/auth.proto` +
> `tonic-build`. Este documento descreve o **escopo completo/definitivo** da
> crate (envelope, eventos do bus, DTOs); parte já nasce com o auth, o restante
> (migração do `TenantEnvelope`, eventos, `MediaPointer`) é adicionado em
> seguida. Os dois planos não conflitam — coordenam a mesma crate.

## 2. Escopo

**Implementado nesta entrega (fundação):**
- `TenantEnvelope<T>` **migrado** de `infrastructure_redis` para cá (ver §5);
  `infrastructure_redis` passa a depender de `contracts`.
- Enum de **eventos internos do bus**, com nomes desacoplados do Evolution:
  `MessageReceived`, `MessageUpdate`, `ConnectionUpdate`, `QrcodeUpdated`,
  `ContactsUpsert` (doc 02 Etapa 0.6/3.4).
- DTOs base compartilhados (ex.: `MediaPointer { storage_key, mimetype, size,
  hash, media_type }` — usado pelo `infrastructure_storage` e pela `message`;
  `media_type` ∈ audio/image/video/document/sticker/thumb, ver
  [08-infraestrutura-storage.md §5](./08-infraestrutura-storage.md)).
- **Versão de schema** dos eventos (`SCHEMA_VERSION` + campo de versão no
  envelope) para evolução compatível.
- Sem dependência de nenhuma `infrastructure_*` nem de runtime (puro
  serde/tipos).

**Fora desta entrega (entra junto da feature que o exige):**
- Geração dos stubs gRPC dos `.proto` (`auth.proto`, runtime API) via
  `tonic-build` no `build.rs` — entra com F6/auth (doc 09 §6.2).
- DTOs específicos de domínio (ticket/kanban/conversa) — entram com cada
  `domain_*` correspondente, mas **moram aqui** quando cruzam a fronteira.
- O `.proto` da IA fica em `domain_ai` + `ia_engine/proto` (doc 01 §5), **não**
  aqui — `contracts` cobre a fronteira **cliente↔servidor** e **eventos do bus**.

## 3. Arquitetura e decisões

| # | Decisão | Escolha | Racional |
|---|---------|---------|----------|
| C1 | Crate sem I/O | `contracts` não importa `infrastructure_*` nem `tokio`/`sqlx`/`redis` | Tipos puros; qualquer camada pode depender sem acoplar runtime |
| C2 | Sentido da dependência | `infrastructure_redis`/`storage`/`postgres` → `contracts` (e nunca o inverso) | Evita ciclo; o envelope e os DTOs são a base |
| C3 | Casa do `TenantEnvelope` | Migra de `infrastructure_redis` para `contracts` | Já previsto na nota do código atual (`envelope.rs`); o bus passa a usar o tipo de `contracts` |
| C4 | Nomes de evento | Internos, desacoplados do Evolution | Domínio não depende do formato do gateway (doc 00 §11) |
| C5 | `event_id` | UUID v7 (ordenável/idempotente) | Mantém o que já existe no envelope atual |
| C6 | Versionamento | `SCHEMA_VERSION` + versão no envelope | Evolução compatível de eventos persistidos no stream |
| C7 | Fonte de tipos gRPC | `.proto` gera os tipos (quando F6 chegar) | `.proto` como fonte única (doc 02/03) |

## 4. Estrutura de módulos (`src/`)

| Módulo | Responsabilidade | Conteúdo |
|---|---|---|
| `envelope.rs` | Envelope multi-tenant | `TenantEnvelope<T>` + `::novo(...)` (migrado) + versão |
| `events.rs` | Eventos internos do bus | enum/`structs` `MessageReceived`, `MessageUpdate`, `ConnectionUpdate`, ... |
| `dtos.rs` | DTOs compartilhados | `MediaPointer`, identificadores, paginação, etc. |
| `version.rs` | Versão de schema | `SCHEMA_VERSION` |
| `proto/` (futuro) | `.proto` cliente↔servidor | `auth.proto`, runtime API (gerados via `build.rs`) |
| `lib.rs` | Reexports + doc | — |

## 5. Migração do `TenantEnvelope` (refator controlado)

Hoje `TenantEnvelope<T>` vive em
[`infrastructure_redis/src/envelope.rs`](../../../server/crates/infrastructure_redis/src/envelope.rs)
e é usado por `event_bus.rs`. Passos:

1. Criar `contracts` com `TenantEnvelope<T>` (cópia fiel + campo de versão).
2. `infrastructure_redis/Cargo.toml`: adicionar `contracts.workspace = true`.
3. Em `infrastructure_redis`, remover `envelope.rs` e reexportar/usar
   `contracts::TenantEnvelope` em `event_bus.rs` e no `lib.rs` (manter o
   reexport público para não quebrar chamadores).
4. Rodar a suíte do `infrastructure_redis` (event bus: publicar→consumir→
   confirmar + replay) para garantir round-trip idêntico.

> Impacto baixo e contido: nenhum comportamento muda; só o tipo troca de casa.
> Fazer **antes** de novos consumidores do bus surgirem (F3.4/F4).

## 6. Configuração e ambiente

- **Workspace:** adicionar `crates/contracts` aos `members` do
  `server/Cargo.toml` e `contracts = { path = "crates/contracts" }` em
  `[workspace.dependencies]`.
- **Dependências da crate:** `serde`, `serde_json`, `uuid` (v7), `chrono`
  (todas já no workspace). Sem `tokio`/`sqlx`/`redis`.
- **Futuro (F6):** `prost`/`tonic` + `tonic-build` (build-dep) quando os
  `.proto` entrarem.

## 7. Testes

- Round-trip serde de `TenantEnvelope<T>` e de cada evento (serializa→
  desserializa→igual) — atende o DoD da Etapa 0.6.
- Compatibilidade de versão: desserializar um payload de `SCHEMA_VERSION`
  anterior não quebra (quando houver v2).
- Comandos: `cargo test -p contracts`,
  `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`.

## 8. Próximo passo

`contracts` é pré-requisito de praticamente tudo a seguir: o `MediaPointer` é
usado por [08-infraestrutura-storage.md](./08-infraestrutura-storage.md); os
eventos do bus são usados pelo `messaging_gateway` (F3.4) e pelo `worker` (F4);
os `.proto` cliente↔servidor entram com a auth/runtime API (F6, doc 09).
Implementar **logo após** (ou junto de) a migração do envelope, antes de novos
produtores/consumidores do bus.

---

*Plano da fundação de contratos. Sujeito a refinamento na canonização via
`plan-restructuring`.*
