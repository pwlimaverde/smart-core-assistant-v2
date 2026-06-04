# 08 — Infraestrutura de Storage (`infrastructure_storage`)

> **Status:** Planejamento (a implementar). Base de código, antes do domínio.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> Verbos de API em pt-br, seguindo o estilo de `infrastructure_postgres`/
> `infrastructure_redis` (`criar_*`, `enviar_*`, `obter_*`).
> **Origem:** Lacuna identificada na revisão da base — a ponte de mídia
> (MinIO/S3) ainda não tinha plano. Deriva de
> [00-planejamento-inicial.md §9 e §14](./00-planejamento-inicial.md),
> [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md) e das Etapas
> 5.5 / 8.3 / 9.3 de [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).

---

## 1. Objetivo

Centralizar **todo** o acesso ao armazenamento de objetos **S3-compatible** em
uma única crate (`server/crates/infrastructure_storage`), análoga às pontes
`infrastructure_postgres` e `infrastructure_redis`. É a **única** crate do
workspace que fala com o cliente S3.

A mídia é **transitória no servidor** (doc 00 §9): o binário decifrado vive no
storage por uma janela curta; o que é permanente é o **ponteiro** + `resumo_midia`
+ `analise_midia` no Postgres, e o cache permanente fica no disco do atendente
(via `local_engine`, F8). Esta crate provê o put/get/presign/delete que sustenta
esse modelo.

### Estratégia de provedor (S3-compatible em todo lugar)

A crate é **agnóstica de provedor**: fala o protocolo S3 e seleciona o backend
só por configuração de ambiente. Decisão atual:

| Ambiente | Provedor | Por quê |
|---|---|---|
| **Desenvolvimento** | **MinIO** local (Docker) | Já existe em `docker/compose/data.yml`; offline, sem custo, rápido |
| **Produção (agora)** | **Cloudflare R2** (free tier) | 10 GB grátis/mês, 1M escritas + 10M leituras Classe A/B grátis, **egress R$ 0,00**, entrega via CDN; **tira mídia da VM Hostinger** (libera CPU/RAM/disco) |
| **Produção (escala futura)** | AWS S3 / MinIO self-host / outro | Mesmo código — só troca endpoint/credenciais |

Como R2 é **100% compatível com a API S3**, o mesmo cliente `aws-sdk-s3` (decisão
S2) atende os três cenários sem mudança de código. Isso preserva a portabilidade
pedida (compatibilidade S3 para escalar) enquanto roda **de graça** no R2 agora.
Alinha-se à diretriz já existente em
[modelagem_dados/08_diretrizes_seguranca.md](../modelagem_dados/08_diretrizes_seguranca.md)
("MinIO local em dev, S3/R2 em produção", TTL ≤ 30 dias).

> **Impacto na infra:** em produção, o serviço `minio` do `data.yml` pode ser
> **desativado** (R2 assume), liberando os ~256 MB reservados na KVM2 — a ser
> detalhado no plano de DevOps (ver
> [10-plano-cicd-devops.md](./10-plano-cicd-devops.md)).
> MinIO permanece apenas no ambiente de desenvolvimento.

## 2. Escopo

**Implementado nesta entrega (fundação):**
- Conexão/cliente S3 **agnóstico de provedor** (MinIO/R2/S3) lendo variáveis
  genéricas `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`, `S3_BUCKET` + healthcheck (ver §7).
- Bootstrap idempotente do bucket (`garantir_bucket`).
- Namespacing obrigatório por tenant na chave do objeto:
  `tenant/<tenant_id>/media/<hash>`.
- Upload/Download por **streaming** (não carregar binário inteiro em memória):
  `enviar_objeto`, `obter_objeto`.
- **URLs pré-assinadas** (presigned GET, TTL curto) para o cliente baixar mídia
  sem passar pelo backend (`gerar_url_assinada`).
- Metadados do objeto (mimetype, tamanho, hash) e `head` por hash
  (`existe_objeto`).
- Remoção (`remover_objeto`) — usada pela purga agendada do worker (F4.3b).
- Erro único `StorageError` (via `thiserror`), espelhando `DbError`/`RedisError`.
- Testes de integração contra MinIO real (bucket/prefixo de teste).

**Fora desta entrega (fases futuras — ver §8):** política de retenção/lifecycle
(TTL automático), upload multipart para arquivos grandes, criptografia
server-side (SSE), replicação/off-site, quota de storage por tenant.

## 3. Arquitetura e decisões

| # | Decisão | Escolha | Racional |
|---|---------|---------|----------|
| S1 | Crate única de storage | Nenhuma outra crate importa o cliente S3 diretamente | Mesmo princípio das pontes postgres/redis |
| S2 | Cliente Rust | **`aws-sdk-s3`** (config manual, sem `aws-config`) | Maduro, suporta presigning + streaming (`ByteStream`) + multipart; compatível com MinIO **e Cloudflare R2** via `endpoint_url` + `force_path_style(true)`. Credenciais explícitas evitam a dependência pesada `aws-config` (sem resolução de env/profile/IMDS) |
| S2b | Provedor por ambiente | **MinIO (dev) + Cloudflare R2 free (prod)**; código agnóstico via vars `S3_*` | R2 é 100% S3-compatível e grátis até 10 GB (egress R$ 0,00 + CDN); tira a mídia da VM. Escala futura troca só endpoint/credenciais |
| S3 | Layout multi-tenant da chave | `media/{tenant_id}/{instance_id}/{media_type}/{hash}` | Isolamento por tenant (doc 00 §6) + organização por instância e tipo (ver §5) |
| S4 | Endereçamento por conteúdo | Chave inclui o **hash** do binário | Idempotência de upload + casa com a verificação de cache do `local_engine` por hash (doc 00 §9.2) |
| S5 | Entrega ao cliente | **URL pré-assinada** (presigned GET) | Cliente baixa direto do MinIO; backend não vira gargalo de banda |
| S6 | Erro | `StorageError` único (`thiserror`) | Padrão do workspace |
| S7 | Sem `unwrap()/expect()` em produção | uso de `?`/`Result` | Padrão do workspace |

> **Alternativa registrada (não adotada):** crate `rust-s3` (`s3`) — mais leve em
> dependências; reconsiderar se o tamanho do binário virar problema. O binário é
> compilado no CI (não na VPS), então o peso de build não pressiona a Hostinger.

## 4. Estrutura de módulos (`src/`)

| Módulo | Responsabilidade | API principal |
|---|---|---|
| `connection.rs` | Cliente e health | `criar_cliente()` (lê env), `criar_cliente_com_config(...)`, `garantir_bucket(client, bucket)`, `health(client)` |
| `errors.rs` | Erro único | `StorageError { S3, ConfigError, NotFound, Serde }` |
| `keys.rs` | Namespacing/layout | `chave_midia(tenant_id, instance_id, media_type, hash, ext)`; `chave_treinamento(tenant_id, document_id, hash)`; enum `MediaType` (ver §5) |
| `objects.rs` | CRUD de objetos | `enviar_objeto`, `obter_objeto`, `existe_objeto`, `remover_objeto`, `metadados_objeto` |
| `presign.rs` | URLs assinadas | `gerar_url_assinada(client, key, ttl)` (presigned GET) |
| `lib.rs` | Reexports + doc | — |

## 5. Modelo de objetos e layout multi-tenant

O sistema é multi-tenant; o layout das chaves é **hierárquico e previsível**,
pensado para isolamento, organização e regras de retenção (lifecycle) por
prefixo.

### 5.1 Mídia de mensagens (WhatsApp) — caso principal

```
media/{tenant_id}/{instance_id}/{media_type}/{hash}[.{ext}]
```

| Segmento | O que é | Para que serve |
|---|---|---|
| `media/` | raiz da categoria | **Uma** regra de lifecycle (TTL) cobre toda a mídia de todos os tenants |
| `{tenant_id}` | UUID do tenant | Isolamento lógico + listagem/quota por tenant (alinha ao RLS do Postgres) |
| `{instance_id}` | UUID da `evolution_instance` | Limpeza/auditoria por instância (ex.: apagar tudo ao desconectar/excluir uma instância) |
| `{media_type}` | `audio` \| `image` \| `video` \| `document` \| `sticker` \| `thumb` | Organização + TTL por tipo (ex.: áudio expira antes de documento) |
| `{hash}` | SHA-256 hex do binário | **Idempotência** (mesmo conteúdo não re-sobe) + casa com o cache local do `local_engine` por hash (doc 00 §9.2) |
| `.{ext}` | extensão opcional do mimetype | Nome amigável / `Content-Type` no download; `mimetype` também vai nos metadados do objeto |

> Os `media_type` espelham a normalização do `domain_whatsapp` (doc 00 §7:
> `imageMessage`/`audioMessage`/`videoMessage`/`documentMessage`/
> `stickerMessage`). Texto (`conversation`/`extendedTextMessage`) não gera
> binário.

**Exemplo:**
`media/3f29.../a1b2.../audio/9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08.ogg`

### 5.2 Outras categorias (mesma raiz por categoria)

| Recurso | Chave | Permanência |
|---|---|---|
| Documento de treinamento (RAG) | `training/{tenant_id}/{document_id}/{hash}[.{ext}]` | semi-permanente (vida do documento) |
| (futuro) Branding/assets do tenant | `branding/{tenant_id}/{asset}` | permanente |
| (futuro) Exports/relatórios | `exports/{tenant_id}/{job_id}` | transitória |

> Cada categoria é uma **raiz própria** (`media/`, `training/`, …) para permitir
> regras de lifecycle distintas: `media/` expira (≤ 30 dias), `training/` não.

### 5.3 Ponteiro no Postgres

> O **ponteiro** (`storage_key` completo, `mimetype`, `size`, `hash`,
> `media_type`) é gravado em `message.media_pointer` no Postgres (doc 00 §12) —
> tipo `MediaPointer` da crate `contracts` ([07-crate-contracts.md](./07-crate-contracts.md)).
> O storage guarda só o byte;
> a verdade textual (`resumo_midia`/`analise_midia`) é permanente no banco.

## 6. Fluxos detalhados

### 6.1 Upload (worker, F5.5)
1. Worker decifra o binário (tem `mediaKey`/`directPath` do Evolution).
2. Calcula o `hash` (SHA-256) → monta a chave
   `chave_midia(tenant_id, instance_id, media_type, hash, ext)` (ver §5).
3. `existe_objeto(key)`: se já existe (mesmo hash), não re-envia (idempotente).
4. `enviar_objeto(key, stream, mimetype)` via `ByteStream` (streaming).
5. Grava o **ponteiro** na `message` (Postgres); o binário fica no storage S3
   (MinIO em dev / R2 em produção).

### 6.2 Download pelo cliente (F7/F8/F10)
- **Windows (F8):** `local_engine` checa o cache local por `hash`; se ausente,
  pede ao backend uma `gerar_url_assinada(key, ttl)` e baixa **uma vez** direto
  do storage (em R2, via CDN da Cloudflare); persiste em disco. Próximas
  visualizações não tocam o servidor.
- **Web (F10):** sem cache local — sempre via URL pré-assinada (transitória).

### 6.3 Purga (worker scheduler, F4.3b / F9.3)
- Tarefa agendada chama `remover_objeto(key)` para mídia expirada (após X dias ou
  confirmação de cache). O `resumo`/`analise` permanece no banco para sempre
  (doc 00 §9.2/§9.3).

## 7. Configuração e ambiente

### 7.1 Variáveis genéricas S3 (mesmas chaves para MinIO e R2)

Bucket R2 já provisionado (`media-smart-core-assistant`, conta
`f8a62f80a11daa28993d717489ff83a9`, localização ENAM).

| Variável | Dev (MinIO) | Produção (Cloudflare R2) |
|---|---|---|
| `S3_ENDPOINT` | `http://localhost:9000` (via túnel SSH) | `https://f8a62f80a11daa28993d717489ff83a9.r2.cloudflarestorage.com` |
| `S3_REGION` | `us-east-1` (fictícia) | `auto` (**R2 exige `auto`**) |
| `S3_ACCESS_KEY_ID` | `MINIO_ROOT_USER` | R2 Access Key ID — ✅ em `infra/.env.deploy` (git-ignored) |
| `S3_SECRET_ACCESS_KEY` | `MINIO_ROOT_PASSWORD` | R2 Secret Access Key — ✅ em `infra/.env.deploy` (git-ignored) |
| `S3_BUCKET` | `smartcore-media` | `media-smart-core-assistant` |
| `S3_FORCE_PATH_STYLE` | `true` | `true` |

> **Endpoint sem o bucket:** a tela "API S3" do R2 mostra a URL
> `https://<conta>.r2.cloudflarestorage.com/media-smart-core-assistant` — o
> sufixo `/media-smart-core-assistant` é o **bucket** e **não** entra no
> `S3_ENDPOINT`; ele vai em `S3_BUCKET`. O `S3_ENDPOINT` é só o nível de conta.

> **Migração de nomes:** o `.env.example` atual usa `MINIO_ENDPOINT`/
> `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD`/`MINIO_BUCKET`. Padronizar para os
> `S3_*` acima (mantendo `MINIO_*` apenas no compose do container de dev).

### 7.2 Credenciais R2 — status

1. ✅ Bucket criado: `media-smart-core-assistant` (conta
   `f8a62f80a11daa28993d717489ff83a9`).
2. ✅ Token **restrito** (Object Read & Write) ativo; credenciais S3
   (`S3_ACCESS_KEY_ID`/`S3_SECRET_ACCESS_KEY`) gravadas em `infra/.env.deploy`
   (**git-ignored**). Placeholders ficam nos `.env.example`.
3. ✅ **Acesso validado** ponta-a-ponta por `infra/test-r2.py` com o token
   restrito (head/put/list/get/presigned/delete — todos OK).
   - Rodar: `uv run --no-project --with boto3 python infra/test-r2.py`.
4. 🔑 **Token admin** (amplo, criar/excluir buckets) mantido **apenas para dev**
   (administração do bucket), documentado como OBS comentada no `.env.deploy` —
   **não** entra no `.env.example` nem é usado pela aplicação/produção.

### 7.3 Docker e rede

- **Dev:** serviço `minio` de `docker/compose/data.yml` (portas 9000/9001),
  mapeado por `infra/tunnel.ps1`/`.sh`.
- **Produção:** R2 é externo (Cloudflare) — **sem porta exposta na VM**; o
  serviço `minio` pode ser desativado em produção (ver §1, impacto na infra).

### 7.4 Workspace

Adicionar a `[workspace.dependencies]`:
```toml
aws-sdk-s3        = { version = "1", default-features = false, features = ["rt-tokio"] }
aws-credential-types = "1"
aws-smithy-types  = "1"   # ByteStream
```
Config do cliente montada manualmente: `Credentials::new(access_key, secret, …)`
+ `endpoint_url(S3_ENDPOINT)` + `force_path_style(true)` + `region(S3_REGION)`.
Para R2, `region = "auto"`.

### 7.5 Configuração no lado da Cloudflare (R2)

| Item | Necessário agora? | Ação |
|---|---|---|
| **API Token** (Object Read & Write) | ✅ **Sim** | Único bloqueio para a integração funcionar. Gerar e guardar Access Key/Secret |
| **Manter o bucket privado** | ✅ Sim | **Não** habilitar "URL de desenvolvimento público" nem Custom Domain. O acesso é só via **URLs pré-assinadas** (decisão S5). Bucket público exporia toda a mídia |
| **Regras de ciclo de vida** (TTL) | ⚠️ Recomendado | Adicionar regra de expiração (ex.: **30 dias**, prefixo `tenant/`) para auto-purgar mídia transitória — casa com a diretriz de segurança e a §8/F9.3. Pode ser feito agora pela tela "Regras do ciclo de vida de objetos" |
| **Política de CORS** | 🔜 Só na fase Web (F10) | Quando o `flutter_web` baixar mídia direto via presigned URL no navegador, adicionar CORS permitindo `GET` da origem do app. Desktop (F8) não precisa |
| **Catálogo de dados / Uploads locais** | ❌ Não | Recursos não usados por este projeto |

> **Localização ENAM:** a região não é alterável após a criação; o egress é
> grátis e a entrega passa pela CDN, então a latência de leitura é mitigada.
> Escritas partem da VM Hostinger — sem impacto relevante para mídia transitória.

## 8. Responsabilidades futuras (mapeadas por fase)

| Responsabilidade | Fase | Observação |
|---|---|---|
| Retenção/lifecycle (TTL automático) | F9.3 | Lifecycle rules nativas do **R2/MinIO** (expiração ≤ 30 dias, conforme diretriz de segurança) **ou** purga via worker (sorted-set por ETA) |
| Upload multipart (arquivos grandes) | F5/F8 | vídeos/documentos grandes sem estourar memória |
| Criptografia server-side (SSE) | F9 | mídia sensível em repouso |
| Quota de storage por tenant | F9.2 | cruza com billing/usage |
| Off-site/replicação | F9 | camada extra de backup (doc 10) |

## 9. Testes

- Integração contra MinIO real (bucket/prefixo de teste, ex.: `smartcore-test`),
  com limpeza por execução.
- Cobertura: `garantir_bucket` idempotente; upload→download round-trip (bytes
  iguais); `existe_objeto` (hit/miss); `gerar_url_assinada` resolve e baixa;
  `remover_objeto`; segregação por prefixo de tenant.
- Comandos: `cargo test -p infrastructure_storage`,
  `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`.

## 10. Próximo passo

Com a ponte de storage pronta, a Etapa 5.5 (worker → IA + mídia) passa a gravar
o **ponteiro** + binário transitório, e a F8 (`local_engine`) consome as URLs
pré-assinadas para o cache local. Depende de `contracts`
([07-crate-contracts.md](./07-crate-contracts.md)) para o tipo do ponteiro de
mídia compartilhado.

---

*Plano da ponte de armazenamento. Sujeito a refinamento na canonização via
`plan-restructuring`.*
