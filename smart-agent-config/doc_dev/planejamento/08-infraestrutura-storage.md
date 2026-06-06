# 08 — Infraestrutura de Storage (`infrastructure_storage` & `data_storage`)

> **Status:** 🚧 **Parcial (stub).** O microsserviço `apps/data_storage` já existe e
> roda (servidor RPC `PutFile`/`GetFile`/`PresignFile` + consumer de purga no bus). A
> crate `infrastructure_storage`, porém, ainda é um **stub baseado em filesystem**
> (`StorageClient` grava em diretório local e devolve URL de presign mockada). A ponte
> S3-compatible (`aws-sdk-s3`) descrita abaixo como **design alvo** ainda **não** está
> implementada.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular. Estabelecimento do microsserviço de armazenamento no workspace.

> ⚠️ **Leia o §2.0 antes do resto.** As seções §1–§8 descrevem o **design alvo**
> (S3/R2/MinIO). O que está de fato implementado hoje é o stub do §2.0.

---

## 1. Objetivo

A crate `infrastructure_storage` serve como uma **biblioteca interna de persistência** exclusiva do aplicativo `apps/data_storage`. Nenhum outro microsserviço ou biblioteca do Cargo workspace importa o cliente S3 ou instancia conexões diretas de storage. Todo o acesso ao armazenamento de objetos compatível com a API S3 (MinIO em dev, Cloudflare R2 em produção) ocorre via chamadas RPC/IPC ao microsserviço `data_storage` rodando localmente (UDS/FlatBuffers).

A mídia é **transitória no servidor** (doc 00 §9): o binário decifrado vive no storage por uma janela curta; o que é permanente é o **ponteiro** + `resumo_midia` + `analise_midia` no Postgres, e o cache permanente fica no disco do atendente (via `local_engine`, F8). Esta crate provê o put/get/presign/delete que sustenta esse modelo através da fronteira de processos.

### Estratégia de provedor (S3-compatible em todo lugar)

A crate é **agnóstica de provedor**: fala o protocolo S3 e seleciona o backend só por configuração de ambiente. Decisão atual:

| Ambiente | Provedor | Por quê |
|---|---|---|
| **Desenvolvimento** | **MinIO** local (Docker) | Já existe em `docker/compose/data.yml`; offline, sem custo, rápido |
| **Produção (agora)** | **Cloudflare R2** (free tier) | 10 GB grátis/mês, 1M escritas + 10M leituras Classe A/B grátis, **egress R$ 0,00**, entrega via CDN; **tira mídia da VM Hostinger** (libera CPU/RAM/disco) |
| **Produção (escala futura)** | AWS S3 / MinIO self-host / outro | Mesmo código — só troca endpoint/credenciais |

Como R2 é **100% compatível com a API S3**, o mesmo cliente `aws-sdk-s3` (decisão S2) atende os três cenários sem mudança de código. Isso preserva a portabilidade pedida (compatibilidade S3 para escalar) enquanto roda **de graça** no R2 agora. Alinha-se à diretriz já existente em [modelagem_dados/08_diretrizes_seguranca.md](../modelagem_dados/08_diretrizes_seguranca.md) ("MinIO local em dev, S3/R2 em produção", TTL ≤ 30 dias).

> **Impacto na infra:** em produção, o serviço `minio` do `data.yml` pode ser **desativado** (R2 assume), liberando os ~256 MB reservados na KVM2 — a ser detalhado no plano de DevOps (ver [10-plano-cicd-devops.md](./10-plano-cicd-devops.md)). MinIO permanece apenas no ambiente de desenvolvimento.

---

## 2.0 Estado atual (stub) — o que está realmente implementado

- **`infrastructure_storage::StorageClient`** — único arquivo `src/lib.rs`. Grava no
  **filesystem local** (`base_path`), criando subdiretório por `tenant_id`. API atual,
  por `tenant_id` + `file_name`:
  - `put(tenant_id, file_name, data) -> String` (URI `storage://{tenant}/{file}`);
  - `get(tenant_id, file_name) -> Vec<u8>`;
  - `presign(tenant_id, file_name, ttl) -> String` — **URL mockada** (`http://localhost:9000/...?token=mock_signed_token`);
  - `delete(tenant_id, file_name)`.
  - Erros via `anyhow` (não há `StorageError` próprio ainda).
- **`apps/data_storage`** — servidor RPC funcional com rotas `PutFile`/`GetFile`/
  `PresignFile` (sobre o `Envelope` protobuf) + consumer do bus que processa
  `media.purge` chamando `StorageClient::delete`. O diretório base vem de
  `SMARTCORE_STORAGE_DIR`. Erros são mapeados para `AppError::Storage` → `ErrorEnvelope`.
- **Testes:** unitários inline em `apps/data_storage` cobrem o fluxo put→get→presign e a
  purga via bus, contra o stub filesystem (sem MinIO/R2).

> **Pendente para fechar a Fase 1 de storage:** trocar o stub pela implementação S3
> descrita nas seções abaixo (cliente `aws-sdk-s3`, layout multi-tenant por hash,
> presign real, MinIO/R2, `StorageError` próprio).

---

## 2. Escopo (design alvo)

**Planejado (ainda não implementado — ver §2.0):**
- Conexão/cliente S3 **agnóstico de provedor** (MinIO/R2/S3) lendo variáveis genéricas `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_BUCKET` + healthcheck.
- Microserviço `apps/data_storage` atuando como servidor RPC (FlatBuffers sobre Unix Domain Sockets) para intermediar chamadas de storage para o workspace. *(parcial: o servidor RPC já existe sobre o stub)*
- Bootstrap idempotente do bucket (`garantir_bucket`).
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
| S2b | Provedor por ambiente | **MinIO (dev) + Cloudflare R2 free (prod)**; código agnóstico via vars `S3_*` | R2 é 100% S3-compatível e grátis até 10 GB (egress R$ 0,00 + CDN); tira a mídia da VM. |
| S3 | Layout multi-tenant da chave | `media/{tenant_id}/{instance_id}/{media_type}/{hash}` | Isolamento por tenant (doc 00 §6) + organização por instância e tipo |
| S4 | Endereçamento por conteúdo | Chave inclui o **hash** do binário | Idempotência de upload + casa com a verificação de cache por hash |
| S5 | Entrega ao cliente | **URL pré-assinada** (presigned GET) | Cliente baixa direto do MinIO/R2; backend não vira gargalo de banda |
| S6 | Erro | `StorageError` único (`thiserror`) | Padrão do workspace |
| S7 | Sem `unwrap()/expect()` em produção | uso de `?`/`Result` | Padrão do workspace |

---

## 4. Estrutura de módulos (`src/`) — **alvo** (hoje é só `lib.rs`; ver §2.0)

| Módulo | Responsabilidade | API principal |
|---|---|---|
| `connection.rs` | Cliente e health | `criar_cliente()` (lê env), `criar_cliente_com_config(...)`, `garantir_bucket(client, bucket)`, `health(client)` |
| `errors.rs` | Erro único | `StorageError { S3, ConfigError, NotFound, Serde }` |
| `keys.rs` | Namespacing/layout | `chave_midia(tenant_id, instance_id, media_type, hash, ext)`; enum `MediaType` |
| `objects.rs` | CRUD de objetos | `enviar_objeto`, `obter_objeto`, `existe_objeto`, `remover_objeto`, `metadados_objeto` |
| `presign.rs` | URLs assinadas | `gerar_url_assinada(client, key, ttl)` (presigned GET) |
| `lib.rs` | Reexports + doc | — |

---

## 5. Modelo de objetos e layout multi-tenant

O layout das chaves no Cloudflare R2/MinIO é estruturado de forma previsível para viabilizar regras de expiração (lifecycle) nativas e isolamento por inquilino.

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
4. Caso ausente, envia por stream para o R2/MinIO.
5. Retorna o `MediaPointer` estruturado para que o worker o persista no Postgres (através de `data_postgres`).

### 6.2 Download / Visualização
- O cliente requisita visualização. O backend (`runtime_api`) chama o `data_storage` via RPC para gerar uma URL pré-assinada de leitura (TTL curto).
- O Flutter baixa o binário diretamente do bucket através da CDN.

---

## 7. Configuração e ambiente

As variáveis `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` e `S3_BUCKET` são lidas exclusivamente pelo processo `data_storage` e expostas via arquivo `.env`.

---

## 8. Testes e Validação

**Hoje (stub):** testes unitários inline em `apps/data_storage` cobrem o fluxo
`PutFile`→`GetFile`→`PresignFile` e a purga assíncrona via bus, contra o stub filesystem.

**Alvo (quando a ponte S3 entrar):**
- Testes de integração na crate `infrastructure_storage` validando upload/download/presign contra um container MinIO local.
- Garantia de que chamadas RPC do `data_storage` se comportam conforme o contrato.

---

## 9. Próximo passo

O microsserviço `data_storage` e o esqueleto RPC estão integrados ao workspace Cargo,
mas operam sobre o **stub filesystem** (§2.0). O próximo passo é implementar a ponte
S3-compatible (`aws-sdk-s3`, layout multi-tenant por hash, presign real, MinIO/R2) para
que o `worker` e a `runtime_api` salvem mídias e gerem URLs pré-assinadas reais via IPC.


