# aws-sdk-s3

- **Versão recomendada:** `1` (resolveu para `1.135.0` em jun/2026)
- **Status:** ✅ ATUALIZADA
- **Última verificação:** 2026-06-06 (context7 `/awslabs/aws-sdk-rust` + uso real)
- **Propósito no projeto:** cliente S3-compatible da crate `infrastructure_storage`
  (exclusiva do app `data_storage`). Backend é o **Cloudflare R2** (S3-compatible)
  em dev e em produção, via configuração por ambiente (`S3_*`).

## Por que aws-sdk-s3 (e não aws-config)

Usamos o cliente com **configuração manual** (`aws_sdk_s3::Config::builder`), sem a
dependência pesada `aws-config`. Credenciais explícitas + `endpoint_url` +
`force_path_style(true)` falam com o R2 (100% compatível com a API S3).

## Matriz de compatibilidade

| Crate | Versão | Observação |
|---|---|---|
| `aws-sdk-s3` | 1.135.0 | Cliente, presigning, `primitives::ByteStream` |
| crypto provider | `aws-lc-rs` | Default; no Windows compila via build (precisa toolchain C/NASM) |
| `tokio` | 1.x (full) | Runtime async |

## Guia de uso rápido (padrões do projeto)

### Cliente com endpoint customizado (MinIO/R2)

```rust
use aws_sdk_s3::config::{BehaviorVersion, Credentials, Region};
use aws_sdk_s3::{Client, Config};

let creds = Credentials::new(access_key, secret_key, None, None, "static");
let conf = Config::builder()
    .behavior_version(BehaviorVersion::latest())
    .region(Region::new(region))        // R2: "auto"
    .endpoint_url(endpoint)             // R2: https://<account_id>.r2.cloudflarestorage.com
    .credentials_provider(creds)
    .force_path_style(true)            // compatível com o R2
    .build();
let client = Client::from_conf(conf);
```

> `BehaviorVersion::latest()` evita precisar da feature `behavior-version-latest`.

### Upload / Download (ByteStream)

```rust
use aws_sdk_s3::primitives::ByteStream;

client.put_object().bucket(&b).key(&k)
    .body(ByteStream::from(dados.to_vec())).send().await?;

let saida = client.get_object().bucket(&b).key(&k).send().await?;
let bytes = saida.body.collect().await?.into_bytes().to_vec();
```

### Detecção de "não encontrado" no GetObject

```rust
.map_err(|e| {
    let svc = e.into_service_error();
    if svc.is_no_such_key() { StorageError::NotFound }
    else { StorageError::S3(svc.to_string()) }
})?;
```

### URL pré-assinada (presigned GET)

```rust
use aws_sdk_s3::presigning::PresigningConfig;
use std::time::Duration;

let cfg = PresigningConfig::expires_in(Duration::from_secs(ttl))?;
let req = client.get_object().bucket(&b).key(&k).presigned(cfg).await?;
let url = req.uri().to_string(); // contém X-Amz-Signature (SigV4)
```

### Verificação do bucket (não cria)

```rust
// O bucket do R2 é provisionado no painel; apenas confirmamos o acesso.
client.head_bucket().bucket(&b).send().await
    .map_err(|e| StorageError::ConfigError(format!("bucket inacessível: {e}")))?;
```

## Notas de produção (R2)

- O bucket do R2 é provisionado **no painel da Cloudflare**; o token de acesso
  normalmente não tem permissão de `create_bucket`. Por isso `garantir_bucket` faz
  **apenas `head_bucket`** (verify-only) e devolve erro de configuração claro se o
  bucket não existir/estiver inacessível.
- `S3_REGION=auto`, `S3_FORCE_PATH_STYLE=true`. Endpoint:
  `https://<account_id>.r2.cloudflarestorage.com`.
- Testes de integração de storage são **opt-in** (rodam só com `S3_*` no `.env`),
  para não escrever no bucket real em execuções rotineiras de `cargo test`.

## Histórico de atualizações

- **2026-06-06:** Criado. Adoção do `aws-sdk-s3` 1.x na crate `infrastructure_storage`
  (substituição do stub filesystem), com config manual para Cloudflare R2 (dev e
  prod), presign real, detecção de NotFound e `garantir_bucket` verify-only.
