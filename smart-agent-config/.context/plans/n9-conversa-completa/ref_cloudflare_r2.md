# Documentação Cloudflare R2 para Backend Rust com aws-sdk-s3 v1

## Resumo Executivo

Este relatório consolida a documentação atual (2026) do Cloudflare R2 para cinco usos críticos em um backend Rust que já utiliza `aws-sdk-s3` v1. O R2 é compatível com a API S3, mas possui diferenças significativas em presigned URLs, CORS, multipart uploads e validação de checksums que devem ser consideradas.

---

## 1. URLs Pré-Assinadas de GET para Leitura de Mídia

### Explicação

URLs pré-assinadas de GET permitem que clientes Flutter (desktop e Web) baixem mídia diretamente do bucket R2 sem expor credenciais de acesso. A URL contém uma assinatura criptográfica que autoriza a operação por um tempo limitado.

### Limites de Expiração Aceitos

- **Mínimo**: 1 segundo
- **Máximo**: 7 dias (604.800 segundos)
- **Recomendado para mídia pública**: 1 a 24 horas
- **Recomendado para mídia sensível**: 5 a 60 minutos

**Fonte**: [Presigned URLs · Cloudflare R2 docs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/)

### Configuração com aws-sdk-s3 v1 (Rust)

#### Exemplo: GET Presigned URL

```rust
use std::time::Duration;
use aws_config::BehaviorVersion;
use aws_sdk_s3::presigning::PresigningConfig;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = aws_config::defaults(BehaviorVersion::latest())
        .load()
        .await;

    let s3_client = aws_sdk_s3::Client::new(&config);

    // Gerar URL pré-assinada de GET válida por 1 hora
    let presigned_request = s3_client
        .get_object()
        .bucket("meu-bucket-r2")
        .key("media/tenant-123/video.mp4")
        .presigned(
            PresigningConfig::builder()
                .expires_in(Duration::from_secs(3600)) // 1 hora
                .build()
                .expect("Falha ao configurar presigning")
        )
        .await?;

    // presigned_request.uri() fornece a URL completa
    let download_url = presigned_request.uri();
    println!("Download URL: {}", download_url);

    Ok(())
}
```

#### Exemplo: Integração em um Endpoint HTTP

```rust
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde_json::json;
use std::time::Duration;
use aws_sdk_s3::presigning::PresigningConfig;

pub async fn get_media_download_url(
    State(s3_client): State<aws_sdk_s3::Client>,
    Path((tenant_id, media_key)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let bucket = "meu-bucket-r2";

    // Validar permissão do tenant
    // ... sua lógica de autorização ...

    let presigned = s3_client
        .get_object()
        .bucket(bucket)
        .key(format!("media/{}/{}", tenant_id, media_key))
        .presigned(
            PresigningConfig::builder()
                .expires_in(Duration::from_secs(3600)) // 1 hora
                .build()
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        )
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(json!({
        "download_url": presigned.uri().to_string(),
        "expires_in_seconds": 3600
    })))
}
```

### Comportamento no Flutter Web e Desktop

- **Flutter Desktop**: GET padrão funciona sem problemas; não requer CORS
- **Flutter Web**: Requer CORS configurado no bucket (veja seção 3)
- **Compressão**: R2 responde com `Content-Encoding` se o objeto foi armazenado comprimido
- **Streaming**: Headers `Content-Range` são suportados em R2

### Erros Comuns

| Erro | Causa | Solução |
|------|-------|---------|
| `ExpiredToken` | URL expirou | Regenerar URL com expiração maior |
| `AccessDenied` | Credenciais inválidas no backend | Verificar chave de acesso e permissões R2 |
| `NoSuchKey` | Objeto não existe | Verificar prefixo e nome do arquivo |
| `NoSuchBucket` | Bucket não existe ou nome incorreto | Verificar nome do bucket e endpoint |

### Diagnóstico

```bash
# Testar URL pré-assinada manualmente
curl -I "https://r2-url-presigned.com/media/tenant/file.mp4"

# Verificar headers de resposta
curl -v "https://r2-url-presigned.com/media/tenant/file.mp4" | head -20
```

---

## 2. URLs Pré-Assinadas de PUT para Upload Direto do Cliente

### Explicação

URLs pré-assinadas de PUT permitem que clientes Flutter façam upload direto de mídia para R2 **sem passar pelo backend**. Isso reduz carga no servidor e acelera uploads grandes.

### Vale a Pena? Análise de Prós e Contras

#### Prós
- **Reduz carga do servidor**: Arquivo não passa pelo backend
- **Velocidade**: Upload direto ao R2, sem intermediário
- **Escalabilidade**: Múltiplos uploads simultâneos sem sobrecarregar backend
- **UX melhorada**: Progresso de upload mais responsivo
- **Ideal para**: Mídia grande (vídeos, áudio, documentos)

#### Contras
- **Complexidade CORS**: Requer configuração adicional no bucket
- **Headers assinados**: Content-Type deve ser incluído na assinatura (veja pegadinhas)
- **Validação**: Backend deve validar arquivo após upload (verificar tamanho, tipo)
- **Segurança**: Qualquer pessoa com a URL pode fazer upload até expiração
- **Ideal para evitar**: Upload de muitos arquivos pequenos (overhead > benefício)

#### Recomendação
Use presigned PUT para:
- Uploads de vídeo/áudio (>10MB)
- Documentos (PDFs, planilhas)
- Fotos em alta resolução

Evite para:
- Thumbnails e ícones
- Metadados/JSONs pequenos
- Uploads que requerem validação complexa antes de persistir

### Configuração com aws-sdk-s3 v1

#### Exemplo: PUT Presigned URL

```rust
use std::time::Duration;
use aws_sdk_s3::presigning::PresigningConfig;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = aws_config::defaults(BehaviorVersion::latest())
        .load()
        .await;

    let s3_client = aws_sdk_s3::Client::new(&config);

    // Gerar URL pré-assinada de PUT válida por 15 minutos
    let presigned_request = s3_client
        .put_object()
        .bucket("meu-bucket-r2")
        .key("media/tenant-123/upload-file.mp4")
        .content_type("video/mp4") // Importante: incluir na assinatura
        .presigned(
            PresigningConfig::builder()
                .expires_in(Duration::from_secs(900)) // 15 minutos
                .build()
                .expect("Falha ao configurar presigning")
        )
        .await?;

    // presigned_request.uri() fornece a URL completa
    let upload_url = presigned_request.uri();
    println!("Upload URL: {}", upload_url);

    // IMPORTANTE: headers precisam ser enviados também
    // presigned_request.headers() retorna headers necessários

    Ok(())
}
```

#### Exemplo: Endpoint que gera presigned PUT

```rust
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde_json::json;
use std::time::Duration;
use aws_sdk_s3::presigning::PresigningConfig;

#[derive(serde::Deserialize)]
pub struct GeneratePutUrlRequest {
    pub filename: String,
    pub content_type: String, // ex: "video/mp4"
    pub content_length: u64, // tamanho esperado
}

pub async fn generate_upload_url(
    State(s3_client): State<aws_sdk_s3::Client>,
    Path(tenant_id): Path<String>,
    Json(req): Json<GeneratePutUrlRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Validar tenant e permissões
    // ... sua lógica de autorização ...

    // Limitar tamanho de upload (ex: 5GB max)
    const MAX_UPLOAD_SIZE: u64 = 5 * 1024 * 1024 * 1024; // 5GB
    if req.content_length > MAX_UPLOAD_SIZE {
        return Err(StatusCode::PAYLOAD_TOO_LARGE);
    }

    // Validar content_type
    let allowed_types = vec![
        "video/mp4",
        "video/quicktime",
        "audio/mpeg",
        "audio/wav",
        "application/pdf",
        "image/jpeg",
        "image/png",
    ];
    if !allowed_types.contains(&req.content_type.as_str()) {
        return Err(StatusCode::BAD_REQUEST);
    }

    let object_key = format!(
        "media/{}/{}",
        tenant_id,
        uuid::Uuid::new_v4()
    );

    let presigned = s3_client
        .put_object()
        .bucket("meu-bucket-r2")
        .key(&object_key)
        .content_type(&req.content_type)
        .presigned(
            PresigningConfig::builder()
                .expires_in(Duration::from_secs(900)) // 15 minutos
                .build()
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        )
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Importante: retornar também os headers necessários
    let mut headers = std::collections::HashMap::new();
    for (k, v) in presigned.headers() {
        headers.insert(k.clone(), v.clone());
    }

    Ok(Json(json!({
        "upload_url": presigned.uri().to_string(),
        "object_key": object_key,
        "headers": headers,
        "expires_in_seconds": 900,
        "method": "PUT"
    })))
}
```

#### Exemplo: Flutter Web fazendo PUT

```dart
import 'package:http/http.dart' as http;

Future<void> uploadFileWithPresignedUrl(String presignedUrl, File file, String contentType) async {
  try {
    final response = await http.put(
      Uri.parse(presignedUrl),
      headers: {
        'Content-Type': contentType, // Deve corresponder ao da assinatura
      },
      body: file.readAsBytesSync(),
    ).timeout(
      const Duration(minutes: 15),
      onTimeout: () => throw Exception('Upload timeout'),
    );

    if (response.statusCode == 200) {
      print('Upload bem-sucedido');
    } else if (response.statusCode == 403) {
      print('Erro: URL expirou ou assinatura inválida');
    } else {
      print('Erro ao fazer upload: ${response.statusCode}');
    }
  } catch (e) {
    print('Exceção durante upload: $e');
  }
}
```

### Limites de Tamanho

- **Por upload**: R2 suporta até 5TB por arquivo
- **PUT direto**: Sem limite de tamanho prático em R2
- **Multipart upload**: Recomendado para >100MB (veja seção 5)

### Pegadinhas Críticas com R2 e Presigned PUT

#### ⚠️ Content-Type na Assinatura

**Problema**: Se incluir `Content-Type` na assinatura, o cliente browser DEVE enviar exatamente esse header. Se o browser enviar automático ou diferente, R2 rejeitará com `SignatureDoesNotMatch`.

**Solução**:
```rust
// NÃO inclua content_type se o browser vai enviar automático
let presigned = s3_client
    .put_object()
    .bucket("bucket")
    .key("file.mp4")
    // .content_type("video/mp4")  // ← REMOVER se o browser vai enviar
    .presigned(...)
    .await?;
```

Ou, do lado do Flutter, seja preciso:
```dart
final response = await http.put(
  Uri.parse(presignedUrl),
  headers: {
    'Content-Type': 'video/mp4', // Deve ser exatamente este
  },
  body: fileBytes,
);
```

#### ⚠️ Headers Assinados vs Não-Assinados

Em presigned URLs, apenas headers específicos podem ser modificados:
- ✅ `Content-Type` (se incluído na assinatura)
- ✅ Headers customizados listados em `AllowedHeaders` da CORS
- ❌ `Authorization`, `Host`, etc. (fixos na assinatura)

Se o cliente enviar headers não assinados, R2 rejeitará.

---

## 3. CORS: Configuração para Flutter Web

### Explicação

CORS (Cross-Origin Resource Sharing) permite que o navegador da página web `https://app.example.com` acesse URLs do bucket R2 `https://bucket.r2.example.com`. Sem CORS, o navegador bloqueia a requisição.

### Configuração Obrigatória

#### Campos de Configuração CORS

| Campo | Valor | Descrição |
|-------|-------|-----------|
| `AllowedOrigins` | `https://app.example.com` | Domínio da app (sem caminho, sem `/`) |
| `AllowedMethods` | `GET`, `PUT`, `HEAD`, `POST` | GET para download, PUT para upload |
| `AllowedHeaders` | `Content-Type`, `*` | Headers que o cliente pode enviar |
| `ExposeHeaders` | `ETag`, `x-amz-version-id` | Headers que JavaScript pode ler |
| `MaxAgeSeconds` | `3600` | Cache de preflight requests |

### Exemplo de Configuração JSON

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": [
        "https://app.example.com",
        "https://app-beta.example.com"
      ],
      "AllowedMethods": [
        "GET",
        "PUT",
        "HEAD",
        "POST"
      ],
      "AllowedHeaders": [
        "Content-Type",
        "x-amz-*"
      ],
      "ExposeHeaders": [
        "ETag",
        "x-amz-version-id",
        "x-amz-meta-*"
      ],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

### Configurar via Wrangler (CLI)

R2 **não oferece configuração CORS pelo dashboard** — apenas via API S3.

#### 1. Criar arquivo `cors.json`

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": [
        "https://app.example.com"
      ],
      "AllowedMethods": [
        "GET",
        "PUT",
        "HEAD"
      ],
      "AllowedHeaders": [
        "Content-Type"
      ],
      "ExposeHeaders": [
        "ETag"
      ],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

#### 2. Aplicar via Wrangler

```bash
wrangler r2 bucket cors update meu-bucket-r2 --file cors.json
```

#### 3. Verificar

```bash
wrangler r2 bucket cors get meu-bucket-r2
```

### Configurar via AWS SDK (Rust)

```rust
use aws_sdk_s3::types::{CorsRule, CorsRuleAndOperator};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = aws_config::defaults(BehaviorVersion::latest())
        .load()
        .await;

    let s3_client = aws_sdk_s3::Client::new(&config);

    let cors_rule = CorsRule::builder()
        .allowed_origins("https://app.example.com")
        .allowed_methods(aws_sdk_s3::types::CorsRuleOperation::Get)
        .allowed_methods(aws_sdk_s3::types::CorsRuleOperation::Put)
        .allowed_methods(aws_sdk_s3::types::CorsRuleOperation::Head)
        .allowed_headers("Content-Type")
        .allowed_headers("x-amz-*")
        .expose_headers("ETag")
        .expose_headers("x-amz-version-id")
        .max_age_seconds(3600)
        .build()?;

    s3_client
        .put_bucket_cors()
        .bucket("meu-bucket-r2")
        .cors_configuration(
            aws_sdk_s3::types::CorsConfiguration::builder()
                .cors_rules(cors_rule)
                .build()?
        )
        .send()
        .await?;

    println!("CORS configurado com sucesso");

    Ok(())
}
```

### Pegadinhas Conhecidas com CORS e R2

#### ⚠️ `AllowedOrigins` Deve Ser Exato

```json
// ✅ Correto
"AllowedOrigins": ["https://app.example.com"]

// ❌ Errado (inclui caminho)
"AllowedOrigins": ["https://app.example.com/"]

// ❌ Errado (sem scheme)
"AllowedOrigins": ["app.example.com"]

// ❌ Errado (wildcard simples não funciona em R2)
"AllowedOrigins": ["*"]
```

Solução: Se precisar de múltiplos domínios, liste cada um:
```json
"AllowedOrigins": [
  "https://app.example.com",
  "https://app-beta.example.com",
  "https://localhost:3000"
]
```

#### ⚠️ Range Requests para Streaming de Vídeo/Áudio

Se o cliente fazer requisição com header `Range: bytes=0-1023` (para streaming ou seek de vídeo):

1. Adicione `Range` em `AllowedHeaders`
2. Exponha `Content-Range` em `ExposeHeaders`

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["https://app.example.com"],
      "AllowedMethods": ["GET", "HEAD"],
      "AllowedHeaders": [
        "Content-Type",
        "Range"
      ],
      "ExposeHeaders": [
        "ETag",
        "Content-Length",
        "Content-Range",
        "Content-Type"
      ],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

#### ⚠️ Propagação de Mudanças CORS

Alterações em CORS **podem levar até 30 segundos** para se propagar globalmente no R2. Se mudar política CORS, aguarde e teste novamente.

Se usar domínio customizado (ex: `cdn.example.com` via Cloudflare), **purge o cache** após alterar CORS.

#### ⚠️ Preflight Requests (OPTIONS)

Quando o navegador detecta uma requisição "complexa" (PUT, headers customizados), envia preflight:
```
OPTIONS /media/tenant/file.mp4 HTTP/1.1
Origin: https://app.example.com
```

R2 responde com headers CORS. Se falhar:
- Verificar se `AllowedMethods` inclui `OPTIONS`
- Verificar se `AllowedHeaders` lista todos os headers personalizados

### Diagnóstico de CORS

```bash
# Testar preflight para PUT
curl -v \
  -X OPTIONS \
  -H "Origin: https://app.example.com" \
  -H "Access-Control-Request-Method: PUT" \
  -H "Access-Control-Request-Headers: Content-Type" \
  https://bucket.r2.example.com/media/tenant/file.mp4

# Testar GET com presigned URL
curl -v \
  -H "Origin: https://app.example.com" \
  https://bucket.r2.example.com/media/tenant/file.mp4?X-Amz-Algorithm=...
```

---

## 4. Lifecycle/Retenção: Expiração de Objetos por Prefixo

### Explicação

Lifecycle policies automatizam a expiração (deleção) de objetos após certo tempo. Ideal para dados temporários como uploads em progresso, sessões expiradas, ou mídia antiga.

Para o Smart Core (estrutura `media/{tenant}/...`), regras podem expirar objetos de tenants específicos após 30 dias.

### Configuração Recomendada

#### Exemplo: Deletar uploads temporários em 7 dias

```json
{
  "Rules": [
    {
      "Id": "delete-temp-uploads",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "media/temp/"
      },
      "Expiration": {
        "Days": 7
      }
    },
    {
      "Id": "delete-old-media",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "media/"
      },
      "Expiration": {
        "Days": 30
      }
    },
    {
      "Id": "cleanup-incomplete-multipart",
      "Status": "Enabled",
      "Filter": {},
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
```

### Configurar via AWS SDK (Rust)

```rust
use aws_sdk_s3::types::{LifecycleRule, LifecycleExpiration, Filter, LifecycleRuleAndOperator};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = aws_config::defaults(BehaviorVersion::latest())
        .load()
        .await;

    let s3_client = aws_sdk_s3::Client::new(&config);

    let rule_expire_old_media = LifecycleRule::builder()
        .id("delete-old-media")
        .status(aws_sdk_s3::types::ExpirationStatus::Enabled)
        .filter(
            Filter::builder()
                .prefix("media/")
                .build()?
        )
        .expiration(
            LifecycleExpiration::builder()
                .days(30)
                .build()?
        )
        .build()?;

    let rule_abort_incomplete = LifecycleRule::builder()
        .id("cleanup-incomplete-multipart")
        .status(aws_sdk_s3::types::ExpirationStatus::Enabled)
        .filter(Filter::builder().build()?)
        .abort_incomplete_multipart_upload(
            aws_sdk_s3::types::AbortIncompleteMultipartUpload::builder()
                .days_after_initiation(7)
                .build()?
        )
        .build()?;

    s3_client
        .put_bucket_lifecycle_configuration()
        .bucket("meu-bucket-r2")
        .lifecycle_configuration(
            aws_sdk_s3::types::BucketLifecycleConfiguration::builder()
                .rules(rule_expire_old_media)
                .rules(rule_abort_incomplete)
                .build()?
        )
        .send()
        .await?;

    println!("Lifecycle policies configuradas");

    Ok(())
}
```

### Comportamento Temporal

- **Processamento**: Deletions ocorrem **dentro de 24 horas** após a data de expiração
- **Precedência**: Se um objeto tiver regra de transição E expiração, expiração é aplicada
- **Granularidade**: Dia (não hora); ex: "30 dias" = "a partir do 30º dia"
- **Multipart incompleto**: Abortado automaticamente após 7 dias (configurável)

### Limites

- Máximo de **1.000 regras por bucket**
- Prefixos podem sobrepor (a mais específica vence)
- Não há regras por sufixo, apenas prefixo

### Diagnóstico

```bash
# Listar lifecycle policies atuais
wrangler r2 bucket lifecycle get meu-bucket-r2

# Remover se errado
wrangler r2 bucket lifecycle delete meu-bucket-r2
```

### Exemplo Prático: Separar Cleanup por Tenant

Se estrutura é `media/{tenant-id}/{uuid}`:

```json
{
  "Rules": [
    {
      "Id": "delete-tenant-123-after-60-days",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "media/tenant-123/"
      },
      "Expiration": {
        "Days": 60
      }
    },
    {
      "Id": "delete-tenant-456-after-30-days",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "media/tenant-456/"
      },
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
```

---

## 5. Diferenças R2 vs S3: Impacto em Presigned URLs, CORS e Multipart

### Resumo de Compatibilidade

| Funcionalidade | AWS S3 | Cloudflare R2 | Impacto | Fonte |
|---|---|---|---|---|
| Presigned URLs GET/PUT | ✅ Full | ✅ Full | Mesma sintaxe | [R2 Presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/) |
| CORS (Dashboard) | ✅ Yes | ❌ API only | Requer Wrangler/API | [R2 Docs](https://developers.cloudflare.com/r2/buckets/cors/) |
| Content-Type na assinatura | ✅ Flexível | ⚠️ Rigoroso | R2 rejeita headers não assinados | [R2 Community](https://community.cloudflare.com/t/cors-issue-with-r2-presigned-url/428567) |
| Multipart Upload | ✅ Full | ⚠️ MD5 issue | ETag não é MD5 válido em multipart | [GitHub R2 Issue](https://github.com/s3tools/s3cmd/issues/1273) |
| Content-MD5 header | ✅ Validação | ❌ Ignorado | R2 não valida Content-MD5 | [R2 Compatibility](https://developers.cloudflare.com/r2/api/s3/api/) |
| SSE-C (encriptação lado-cliente) | ✅ Yes | ✅ Yes | Mesmo suporte | |
| Range requests | ✅ Yes | ✅ Yes | Suportado mas requer CORS | |

### Diferenças Críticas Detalhadas

#### 1️⃣ CORS Apenas via API

**S3**: Configure CORS no console AWS ou via `put_bucket_cors()`.

**R2**: Apenas via Wrangler CLI ou S3 API.

```bash
# R2: Wrangler é a forma "amigável"
wrangler r2 bucket cors update bucket-name --file cors.json

# R2: Ou via AWS CLI
aws s3api put-bucket-cors \
  --bucket meu-bucket-r2 \
  --cors-configuration file://cors.json \
  --endpoint-url https://r2.example.com
```

#### 2️⃣ Headers Assinados em Presigned URLs

**S3**: Presigned URLs permitem headers não assinados; S3 verifica apenas query params.

**R2**: Muito rigoroso. Se um header foi assinado, cliente DEVE enviá-lo. Se não foi assinado e cliente o envia, R2 rejeita com `403 SignatureDoesNotMatch`.

**Impacto prático**:

```rust
// ❌ Em R2, isso FALHARÁ se browser enviar Content-Type automático
let presigned = s3_client
    .put_object()
    .bucket("bucket")
    .key("file")
    .content_type("video/mp4")  // Assinado
    .presigned(...)
    .await?;

// ✅ Solução: não assinar, deixar browser enviar
let presigned = s3_client
    .put_object()
    .bucket("bucket")
    .key("file")
    // Sem .content_type() aqui
    .presigned(...)
    .await?;
```

**Fonte**: [Medium - Pre-signed URLs & CORS on Cloudflare R2](https://mikeesto.medium.com/pre-signed-urls-cors-on-cloudflare-r2-c90d43370dc4)

#### 3️⃣ Multipart Upload: ETag e MD5

**S3**: ETag de multipart upload é `MD5(MD5(part1) + MD5(part2) + ... + MD5(partN))`; ferramentas S3 verificam automaticamente.

**R2**: ETag **NÃO é MD5 válido**. Ferramentas como `s3cmd` e `s5cmd` geram warnings ou falhas ao verificar integridade.

**Impacto**:
- AWS SDK para Rust não valida MD5 por padrão
- `s3cmd` requer flag `--no-check-md5` em R2
- Se app fazer validação manual de MD5, **falhará em R2**

**Solução**:
```rust
// Usar aws-sdk-s3 v1; não fazer validação manual de MD5
let response = s3_client
    .put_object()
    .bucket("bucket")
    .key("large-file")
    .body(body)
    .send()
    .await?;

// response.e_tag é válido mas NÃO é MD5 em R2
// Use como identificador único, não para verificação
println!("ETag: {:?}", response.e_tag);
```

#### 4️⃣ Content-MD5 Header

**S3**: Valida `Content-MD5` header se presente.

**R2**: Ignora `Content-MD5`; não faz validação.

**Impacto**: Redundante em R2; não prejudica.

#### 5️⃣ Lifecycle Rules

**S3**: Suporta transições de classe de armazenamento (STANDARD → GLACIER, etc).

**R2**: Suporta transição para "Infrequent Access"; sem GLACIER ou DEEP_ARCHIVE.

**Impacto**:
```json
// ❌ Não funciona em R2
{
  "Transitions": [
    {
      "Days": 90,
      "StorageClass": "GLACIER"
    }
  ]
}

// ✅ Funciona em R2
{
  "Transitions": [
    {
      "Days": 30,
      "StorageClass": "INFREQUENT_ACCESS"
    }
  ],
  "Expiration": {
    "Days": 365
  }
}
```

**Fonte**: [R2 Object Lifecycles](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)

### Checklist de Migração S3 → R2

- [ ] Remover validação manual de MD5 (ou usar ETag como UUID apenas)
- [ ] Testar presigned URLs com navegador; remover content_type se falhar
- [ ] Configurar CORS via Wrangler, não dashboard
- [ ] Adaptar lifecycle rules; remover transições para GLACIER
- [ ] Testar Range requests se usar streaming de vídeo
- [ ] Verificar endpoint URL (`https://[account].r2.amazonaws.com` vs `https://bucket.r2.example.com`)

### Diagnóstico de Compatibilidade

```bash
# Testar PUT presigned com curl (simular browser)
curl -X PUT \
  -H "Content-Type: video/mp4" \
  --data-binary @file.mp4 \
  "https://bucket.r2.example.com/media/file.mp4?X-Amz-Algorithm=..."

# Se 403 SignatureDoesNotMatch: problema com headers assinados em R2

# Listar objetos com ETag
aws s3api list-objects-v2 \
  --bucket meu-bucket-r2 \
  --endpoint-url https://r2.example.com \
  --query 'Contents[].{Key:Key, ETag:ETag}'

# ETag estranho (não é MD5): confirmação que é R2
```

---

## 6. Matriz de Decisão: Quando Usar Qual Abordagem

### Upload Direto (Presigned PUT) vs Backend Relay

```
Tamanho do arquivo
   ↓
   < 1MB
      ↓
      → Backend relay (simples, não vale complexidade CORS/presigned)
   
   1MB - 10MB
      ↓
      → Pode ser presigned PUT ou backend (trade-off)
   
   10MB - 5GB
      ↓
      → Presigned PUT (reduz carga backend, acelera)
   
   > 5GB
      ↓
      → Presigned PUT + multipart upload (obrigatório)
```

### Presigned GET vs Bucket Público

```
Tipo de mídia
   ↓
   Pública (avatares, banners)
      ↓
      → Bucket público (mais rápido, menos overhead)
   
   Privada (documentos, mensagens)
      ↓
      → Presigned GET (tempo limitado, auditável)
   
   Sensível (dados médicos, PII)
      ↓
      → Backend relay (controle total, log, validação)
```

---

## Fontes Citadas

- [Presigned URLs · Cloudflare R2 docs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/)
- [Configure CORS · Cloudflare R2 docs](https://developers.cloudflare.com/r2/buckets/cors/)
- [Object lifecycles · Cloudflare R2 docs](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)
- [S3 API compatibility · Cloudflare R2 docs](https://developers.cloudflare.com/r2/api/s3/api/)
- [Creating presigned URLs using the AWS SDK for Rust](https://docs.aws.amazon.com/sdk-for-rust/latest/dg/presigned-urls.html)
- [Pre-signed URLs & CORS on Cloudflare R2 | Michael Esteban](https://mikeesto.medium.com/pre-signed-urls-cors-on-cloudflare-r2-c90d43370dc4)
- [How to Generate Presigned URLs for R2 When Using Cloudflare Workers](https://ishan.page/blog/cloudflare-r2-workers-presigned/)
- [Cloudflare R2 - MD5 Sums issue · s3cmd GitHub](https://github.com/s3tools/s3cmd/issues/1273)
- [Browser uploads to Cloudflare R2 with AWS SDK | Transloadit](https://transloadit.com/devtips/browser-uploads-to-cloudflare-r2-with-aws-sdk/)
- [Uploading Files to Amazon S3 Using Presigned URLs in Flutter | Arjun R. Medium](https://medium.com/@gemthearjun/uploading-files-to-amazon-s3-using-presigned-urls-in-flutter-a-step-by-step-guide-919d9020117c)
- [GitHub - awslabs/aws-sdk-rust put-object-presigned example](https://github.com/awslabs/aws-sdk-rust/blob/main/examples/s3/src/bin/put-object-presigned.rs)

---

## Apêndice A: Snippets Rust Prontos para Copiar

### Setup Básico

```toml
# Cargo.toml
[dependencies]
aws-config = "1"
aws-sdk-s3 = { version = "1", features = ["http-1x"] }
tokio = { version = "1", features = ["full"] }
```

### Cliente S3 Singleton

```rust
use aws_sdk_s3::Client as S3Client;
use std::sync::Arc;

pub struct AppState {
    pub s3_client: Arc<S3Client>,
}

pub async fn init_app_state() -> Result<AppState, Box<dyn std::error::Error>> {
    let config = aws_config::defaults(aws_config::BehaviorVersion::latest())
        .load()
        .await;
    
    let s3_client = S3Client::new(&config);
    
    Ok(AppState {
        s3_client: Arc::new(s3_client),
    })
}
```

### Função Helper: Gerar Presigned GET

```rust
use std::time::Duration;
use aws_sdk_s3::presigning::PresigningConfig;

pub async fn generate_presigned_get_url(
    client: &aws_sdk_s3::Client,
    bucket: &str,
    key: &str,
    expires_in_secs: u64,
) -> Result<String, Box<dyn std::error::Error>> {
    let presigned = client
        .get_object()
        .bucket(bucket)
        .key(key)
        .presigned(
            PresigningConfig::builder()
                .expires_in(Duration::from_secs(expires_in_secs))
                .build()?
        )
        .await?;

    Ok(presigned.uri().to_string())
}
```

### Função Helper: Gerar Presigned PUT

```rust
pub async fn generate_presigned_put_url(
    client: &aws_sdk_s3::Client,
    bucket: &str,
    key: &str,
    content_type: Option<&str>,
    expires_in_secs: u64,
) -> Result<String, Box<dyn std::error::Error>> {
    let mut builder = client
        .put_object()
        .bucket(bucket)
        .key(key);

    if let Some(ct) = content_type {
        builder = builder.content_type(ct);
    }

    let presigned = builder
        .presigned(
            PresigningConfig::builder()
                .expires_in(Duration::from_secs(expires_in_secs))
                .build()?
        )
        .await?;

    Ok(presigned.uri().to_string())
}
```

### Função Helper: Configurar CORS

```rust
use aws_sdk_s3::types::{CorsRule, ExpirationStatus, Filter};

pub async fn setup_cors(
    client: &aws_sdk_s3::Client,
    bucket: &str,
    origins: Vec<&str>,
) -> Result<(), Box<dyn std::error::Error>> {
    let rule = CorsRule::builder()
        .id("allow-flutter-web")
        .status(ExpirationStatus::Enabled);

    let mut rule_builder = rule;
    for origin in &origins {
        rule_builder = rule_builder.allowed_origins(*origin);
    }

    let rule = rule_builder
        .allowed_methods(aws_sdk_s3::types::CorsRuleOperation::Get)
        .allowed_methods(aws_sdk_s3::types::CorsRuleOperation::Put)
        .allowed_methods(aws_sdk_s3::types::CorsRuleOperation::Head)
        .allowed_headers("Content-Type")
        .allowed_headers("x-amz-*")
        .expose_headers("ETag")
        .expose_headers("x-amz-version-id")
        .max_age_seconds(3600)
        .build()?;

    client
        .put_bucket_cors()
        .bucket(bucket)
        .cors_configuration(
            aws_sdk_s3::types::CorsConfiguration::builder()
                .cors_rules(rule)
                .build()?
        )
        .send()
        .await?;

    Ok(())
}
```

---

## Apêndice B: Variáveis de Ambiente Recomendadas

```bash
# .env
R2_BUCKET_NAME=meu-bucket-r2
R2_ACCOUNT_ID=abc123xyz
R2_ACCESS_KEY_ID=xxxxxxx
R2_SECRET_ACCESS_KEY=xxxxxxx
R2_ENDPOINT_URL=https://abc123xyz.r2.amazonaws.com

# URLs presigned
PRESIGNED_GET_EXPIRY_SECS=3600      # 1 hora
PRESIGNED_PUT_EXPIRY_SECS=900       # 15 minutos

# CORS
FLUTTER_APP_ORIGINS=https://app.example.com,https://app-beta.example.com

# Lifecycle
MEDIA_RETENTION_DAYS=30
TEMP_UPLOAD_RETENTION_DAYS=7
```

---

Fim do Relatório.
