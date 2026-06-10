# 08 — Infraestrutura de Storage (`infrastructure_storage` & `data_storage`)

> **Status:** ✅ **Implementado (backend R2 real).** O microsserviço `apps/data_storage`
> roda (servidor RPC `PutFile`/`GetFile`/`PresignFile`/`DeleteFile` + consumer de purga
> no bus) e a crate `infrastructure_storage` usa o cliente **`aws-sdk-s3`** real contra
> o **Cloudflare R2** (config manual via vars `S3_*`, presign real, `StorageError`
> próprio, layout `media/{tenant}/{instance}/{type}/{hash}` em `keys.rs`).
> **Decisão atualizada (2026-06-06):** R2 é o backend em **dev E produção — sem MinIO**;
> `garantir_bucket` é *verify-only* (`head_bucket`; bucket provisionado no painel do R2).
> R2 é acessado por HTTPS direto — não há túnel para storage.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular. Estabelecimento do microsserviço de armazenamento no workspace.

---

## 1. Objetivo

A crate `infrastructure_storage` serve como uma **biblioteca interna de persistência** exclusiva do aplicativo `apps/data_storage`. Nenhum outro microsserviço ou biblioteca do Cargo workspace importa o cliente S3 ou instancia conexões diretas de storage. Todo o acesso ao armazenamento de objetos compatível com a API S3 (Cloudflare R2 em dev e produção) ocorre via chamadas RPC/IPC ao microsserviço `data_storage` rodando localmente (UDS/FlatBuffers).

A mídia é **transitória no servidor** (doc 00 §9): o binário decifrado vive no storage por uma janela curta; o que é permanente é o **ponteiro** + `resumo_midia` + `analise_midia` no Postgres, e o cache permanente fica no disco do atendente (via `local_engine`, F8). Esta crate provê o put/get/presign/delete que sustenta esse modelo através da fronteira de processos.

### Estratégia de provedor (S3-compatible em todo lugar)

A crate é **agnóstica de provedor**: fala o protocolo S3 e seleciona o backend só por configuração de ambiente. Decisão atual:

| Ambiente | Provedor | Por quê |
|---|---|---|
| **Desenvolvimento** | **Cloudflare R2** (free tier) | Mesmo backend da produção (paridade total); HTTPS direto, sem serviço local nem túnel; decisão de 2026-06-06 eliminou o MinIO |
| **Produção (agora)** | **Cloudflare R2** (free tier) | 10 GB grátis/mês, 1M escritas + 10M leituras Classe A/B grátis, **egress R$ 0,00**, entrega via CDN; **tira mídia da VM Hostinger** (libera CPU/RAM/disco) |
| **Produção (escala futura)** | AWS S3 / MinIO self-host / outro | Mesmo código — só troca endpoint/credenciais (`S3_*`) |

Como R2 é **100% compatível com a API S3**, o mesmo cliente `aws-sdk-s3` (decisão S2) atende todos os cenários sem mudança de código. Isso preserva a portabilidade pedida (compatibilidade S3 para escalar) enquanto roda **de graça** no R2 agora.

> **Impacto na infra:** o serviço `minio` do `data.yml` ficou **sem uso** (R2 assume em dev e prod) e pode ser removido do compose, liberando os ~256 MB reservados na KVM2 — a detalhar no plano de DevOps (ver [10-plano-cicd-devops.md](./10-plano-cicd-devops.md)).

---

## 2.0 Estado atual — o que está realmente implementado

- **`infrastructure_storage`** (R2 real via `aws-sdk-s3`, config manual sem `aws-config`):
  - `connection.rs` — `S3Config::from_env()` (vars `S3_ENDPOINT`/`S3_REGION`/`S3_ACCESS_KEY_ID`/`S3_SECRET_ACCESS_KEY`/`S3_BUCKET`), `criar_cliente`, `garantir_bucket` (*verify-only* via `head_bucket`), `health`;
  - `lib.rs` — `StorageClient` com `put`/`get`/`presign` (presigned GET real)/`delete`;
  - `keys.rs` — `MediaType` + `chave_midia` (layout `media/{tenant}/{instance}/{type}/{hash}`);
  - `errors.rs` — `StorageError` próprio mapeado para `ErrorCode`.
- **`apps/data_storage`** — servidor RPC com rotas `PutFile`/`GetFile`/`PresignFile`/`DeleteFile`
  (sobre o `Envelope` protobuf) + consumer do bus que processa `media.purge`.
  Erros mapeados para `AppError::Storage` → `ErrorEnvelope`.
- **Testes:** integração em `crates/infrastructure_storage/tests/objetos/` — **opt-in**:
  rodam apenas com as vars `S3_*` no `.env`, para não escrever no bucket real em todo `cargo test`.
  (Não usar `tests/storage/` como nome — o `.gitignore` ignora `storage/`.)

---

## 2. Escopo (design — implementado, ver §2.0)

- Conexão/cliente S3 **agnóstico de provedor** (R2/S3) lendo variáveis genéricas `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_BUCKET` + healthcheck.
- Microserviço `apps/data_storage` atuando como servidor RPC (FlatBuffers sobre Unix Domain Sockets) para intermediar chamadas de storage para o workspace.
- Verificação do bucket no boot (`garantir_bucket`, *verify-only* — o bucket é provisionado no painel do R2).
- Namespacing obrigatório por tenant na chave do objeto: `media/{tenant_id}/{instance_id}/{media_type}/{hash}`.
- Upload/Download por **streaming** (não carregar binário inteiro em memória): `enviar_objeto`, `obter_objeto`.
- **URLs pré-assinadas** (presigned GET, TTL curto) para o cliente baixar mídia sem passar pelo backend (`gerar_url_assinada`).
- Metadados do objeto (mimetype, tamanho, hash) e `head` por hash (`existe_objeto`).
- Remoção (`remover_objeto`) — usada pela purga agendada do worker.
- Erro único `StorageError` (via `thiserror`), integrado no `AppError` da crate `error_core`.

---

## 3. Arquitetura e decisões

| # | Decisão | Escolha | Racional |
|---|---------|---------|----------|
| S1 | Crate única de storage | A crate `infrastructure_storage` é biblioteca interna exclusiva de `apps/data_storage` | Nenhum outro módulo possui credenciais ou cria clientes S3 diretamente, eliminando vazamento de credenciais |
| S1b | Serviço de Dados `data_storage` | Exposto via RPC IPC (FlatBuffers/UDS) | Centraliza o tráfego de IO do S3 localmente e expõe operações tipadas (upload, download, URL assinada, exclusão) |
| S2 | Cliente Rust | **`aws-sdk-s3`** (config manual, sem `aws-config`) | Maduro, suporta presigning + streaming (`ByteStream`) + multipart; compatível com MinIO **e Cloudflare R2** via `endpoint_url` + `force_path_style(true)`. Credenciais explícitas evitam a dependência pesada `aws-config`. |
| S2b | Provedor por ambiente | **Cloudflare R2 free em dev e prod** (revisado em 2026-06-06; MinIO descartado); código agnóstico via vars `S3_*` | R2 é 100% S3-compatível e grátis até 10 GB (egress R$ 0,00 + CDN); tira a mídia da VM; paridade dev/prod total. |
| S3 | Layout multi-tenant da chave | `media/{tenant_id}/{instance_id}/{media_type}/{hash}` | Isolamento por tenant (doc 00 §6) + organização por instância e tipo |
| S4 | Endereçamento por conteúdo | Chave inclui o **hash** do binário | Idempotência de upload + casa com a verificação de cache por hash |
| S5 | Entrega ao cliente | **URL pré-assinada** (presigned GET) | Cliente baixa direto do R2; backend não vira gargalo de banda |
| S6 | Erro | `StorageError` único (`thiserror`) | Padrão do workspace |
| S7 | Sem `unwrap()/expect()` em produção | uso de `?`/`Result` | Padrão do workspace |

---

## 4. Estrutura de módulos (`src/`) — implementada

| Módulo | Responsabilidade | API principal |
|---|---|---|
| `connection.rs` | Config, cliente e health | `S3Config::from_env()`, `criar_cliente()`, `criar_cliente_com_config(...)`, `garantir_bucket(client, bucket)` (*verify-only*), `health(client, bucket)` |
| `errors.rs` | Erro único | `StorageError` (+ mapeamento p/ `ErrorCode`) |
| `keys.rs` | Namespacing/layout | `chave_midia(tenant_id, instance_id, media_type, hash, ext)`; enum `MediaType` |
| `lib.rs` | `StorageClient` | `put`, `get`, `presign` (presigned GET real), `delete`, `garantir_bucket`, `health` |

---

## 5. Modelo de objetos e layout multi-tenant

O layout das chaves no Cloudflare R2 é estruturado de forma previsível para viabilizar regras de expiração (lifecycle) nativas e isolamento por inquilino.

```
media/{tenant_id}/{instance_id}/{media_type}/{hash}[.{ext}]
```

| Segmento | O que é | Para que serve |
|---|---|---|
| `media/` | raiz da categoria | Regra global de expiração de cache (TTL ≤ 30 dias) aplicada ao prefixo |
| `{tenant_id}` | UUID do tenant | Isolamento lógico (verificação de posse antes do download) |
| `{instance_id}` | UUID da instância WhatsApp | Facilita purga em massa caso o canal seja deletado |
| `{media_type}` | `audio` \| `image` \| `video` \| `document` \| `sticker` \| `thumb` | Organização por tipo MIME |
| `{hash}` | SHA-256 do binário | Idempotência e verificação de integridade |

---

## 6. Fluxos detalhados

### 6.1 Upload (worker)
1. Worker descriptografa a mídia recebida da Evolution.
2. Faz uma chamada RPC para `data_storage` com a payload binária.
3. `data_storage` calcula o hash e verifica a existência do objeto no S3.
4. Caso ausente, envia por stream para o R2.
5. Retorna o `MediaPointer` estruturado para que o worker o persista no Postgres (através de `data_postgres`).

### 6.2 Download / Visualização
- O cliente requisita visualização. O backend (`runtime_api`) chama o `data_storage` via RPC para gerar uma URL pré-assinada de leitura (TTL curto).
- O Flutter baixa o binário diretamente do bucket através da CDN.

---

## 7. Configuração e ambiente

As variáveis `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` e `S3_BUCKET` são lidas exclusivamente pelo processo `data_storage` e expostas via arquivo `.env`.

---

## 8. Testes e Validação

- Testes unitários inline em `apps/data_storage` cobrem o fluxo
  `PutFile`→`GetFile`→`PresignFile` e a purga assíncrona via bus.
- Testes de integração em `crates/infrastructure_storage/tests/objetos/` validam
  upload/download/presign/delete contra o **bucket R2 real** — **opt-in**: rodam apenas
  com as vars `S3_*` presentes no `.env`, para não escrever no bucket a cada `cargo test`.

---

## 9. Próximo passo

A infraestrutura de storage está fechada (R2 real ponta-a-ponta via RPC). Os consumos
reais chegam com as próximas fases: `worker` salvando mídias (F4) e `runtime_api`
gerando URLs pré-assinadas para o Flutter (F6) — ambos exclusivamente via IPC ao
`data_storage`.


