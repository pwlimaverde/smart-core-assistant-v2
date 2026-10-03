# Smart Core Releases Server

Servidor Rust (Axum 0.8) que hospeda o feed de atualização automática do app Windows (Flutter) usando **Velopack**.

## Arquitetura

```
Client (Flutter App)
    ↓ GET /api/releases (Velopack check)
    ↓
Releases Server (Axum + Tokio)
    ├─ GET /api/releases           → releases.win.json (feed)
    ├─ GET /download/{v}/{file}    → .nupkg files (instaladores)
    └─ POST /upload (CI/CD)        → publish nova versão
```

## Quickstart

### Criar .env local

```bash
cp .env.example .env
# Edit .env, set RELEASES_UPLOAD_TOKEN (openssl rand -hex 32)
```

### Subir container

```bash
docker compose --env-file .env up -d
```

### Verificar saúde

```bash
curl http://localhost:8086/health
# Response: 200 OK
```

### Publicar versão (CI/CD)

```bash
git tag win-v0.2.0
git push origin win-v0.2.0
# GitHub Actions: builds → publishes to GHCR → uploads to server
```

## Estrutura de Arquivos

```
/opt/smartcore/releases/
├── releases.win.json         # Feed (versão mais recente)
├── releases.win.json.gz      # Versão comprimida (pré-gerada)
├── releases.win.json.br      # Versão brotli (pré-gerada)
├── v0.1.0/
│   ├── app-0.1.0-full.nupkg
│   └── Setup.exe
└── v0.2.0/
    ├── app-0.2.0-full.nupkg
    ├── app-0.2.0-delta.nupkg  # Delta from 0.1.0
    └── Setup.exe
```

## Endpoints

### GET `/api/releases?channel=stable&version=0.1.0`

Retorna JSON com informações de nova versão:

```json
{
  "version": "0.2.0",
  "url": "https://releases.smartcoreassistant.com.br/download/0.2.0/app-0.2.0-delta.nupkg",
  "sha256": "abcd1234...",
  "mandatory": false,
  "release_notes": "Bug fixes and improvements"
}
```

**Campos:**
- `version`: semver (ex: 0.2.0)
- `url`: URL completa do .nupkg (delta se possível, senão full)
- `sha256`: hash SHA-256 do arquivo para validação
- `mandatory`: se true, cliente recusa rodar até atualizar
- `release_notes`: opcional, changelog para usuário

### GET `/download/{version}/{filename}`

Serve arquivo estático:

```bash
curl -O https://releases.smartcoreassistant.com.br/download/0.2.0/app-0.2.0-delta.nupkg
```

**Features:**
- Compressão automática se cliente suporta (gzip/brotli)
- Precompressed `.gz` / `.br` servidas direto se existem
- Content-Type auto-detectado
- Range requests (retomar download)

### POST `/upload` (CI/CD only)

Upload de nova versão do servidor de releases:

```bash
curl -X POST \
  -H "Authorization: Bearer ${RELEASES_UPLOAD_TOKEN}" \
  -F "version=0.2.0" \
  -F "file=@app-0.2.0-full.nupkg" \
  https://releases.smartcoreassistant.com.br/upload
```

**Segurança:**
- Bearer token obrigatório (constant-time comparison)
- Token armazenado em `SecretString` (nunca exposto em memória)
- SHA-256 do arquivo validado e armazenado
- Logs: nunca printam token; apenas primeiros 8 chars do SHA-256

**Response:**

```json
{
  "status": "success",
  "version": "0.2.0",
  "message": "Upload successful"
}
```

### GET `/health`

Healthcheck para liveness/readiness:

```bash
curl http://localhost:8086/health
# 200 OK
```

## Observabilidade

### Logs Estruturados (Tracing)

Configurado via `RUST_LOG`:

```bash
# Info only
RUST_LOG=releases_server=info,tower_http=info

# Debug (verbose)
RUST_LOG=releases_server=debug,tower_http=debug

# No trace logs
RUST_LOG=releases_server=warn
```

**Exemplos:**

```
2026-10-03T12:34:56.123Z  INFO releases_server: Get releases check version=0.1.0
2026-10-03T12:34:56.124Z  INFO releases_server: Release found version=0.2.0
2026-10-03T12:34:57.000Z  INFO releases_server: Upload authorized token_length=64
2026-10-03T12:34:57.500Z  INFO releases_server: Upload completed version=0.2.0
2026-10-03T12:34:58.000Z  INFO releases_server: Download completed version=0.2.0 bytes_sent=52428800
```

**Sanitização:**
- Bearer token: contagem de length no log (`token_length=64`)
- File hash: primeiros 8 caracteres em hex (`sha256_prefix=abcd1234`)
- Client IP: permitido (não PII), usado para rate limiting
- **Nunca**: password, secret key, full token, full hash

### Métricas (Prometheus)

Futuro: adicionar via `metrics` crate:

```
smartcore_releases_downloads_total{version="0.2.0"} 42
smartcore_releases_upload_duration_ms{version="0.2.0"} 1234
smartcore_releases_check_failures_total{reason="not_found"} 3
smartcore_releases_file_hash_mismatches_total 0
```

## Troubleshooting

### Container não sobe

```bash
docker compose logs releases-server
```

Procure por:
- `RELEASES_DIR` não existe → criar `mkdir -p /opt/smartcore/releases`
- `UPLOAD_TOKEN` vazio → set em `.env`
- Port 8086 em uso → mudar em `compose.yml` ports

### Upload falha com 413

Body muito grande (limite default 2 MB em Axum). Na rota de upload, aumentar:

```rust
DefaultBodyLimit::max(256 * 1024 * 1024) // 256 MB
```

### Client não vê nova versão

1. Verificar feed: `curl https://releases.smartcoreassistant.com.br/api/releases`
2. Verificar arquivo: `curl -I https://releases.smartcoreassistant.com.br/download/0.2.0/app-0.2.0-delta.nupkg`
3. Logs do servidor: `docker compose logs -f releases-server | grep "0.2.0"`
4. Client checa a cada 1h — aguarde ou force restart

## Roadmap (Futuro)

- [ ] Integração com `vpk pack` (Velopack) no CI/CD
- [ ] Web UI para gerenciar versões (deletar antigas, rollback)
- [ ] Autenticação OIDC para upload (além de Bearer token)
- [ ] Alertas de falha de upload/download
- [ ] Dashboard Grafana com métricas
- [ ] Suporte a canais (stable, beta, canary)

## Docs Externas

- [Velopack Docs](https://docs.velopack.io)
- [Axum](https://docs.rs/axum)
- [Tower-HTTP](https://docs.rs/tower-http)
