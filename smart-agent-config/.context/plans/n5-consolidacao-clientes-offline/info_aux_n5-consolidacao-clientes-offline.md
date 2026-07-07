# Documentação Auxiliar — Fase N5: Consolidação de Clientes + Offline

> Gerado em: 2026-07-06
> Plano canônico: `.context/plans/n5-consolidacao-clientes-offline.md`
> Plano completo: `.context/plans/n5-consolidacao-clientes-offline/plano_completo_n5-consolidacao-clientes-offline.md`
> Origem do plano-base: `doc_dev/planejamento/20-fase-N5-consolidacao-clientes-offline.md`

## Libs (todas USAR LOCAL — central `doc_dev/libs/`)

| Lib | Stack | Versão | Verificação | Uso na N5 |
|---|---|---|---|---|
| flutter_rust_bridge | flutter | 2.0.0 | 2026-05-31 | binding FFI Dart ↔ `local_engine` (F8) — **risco-chave**: revalidar versão atual na fase P do ciclo (doc tem 13 meses de projeto pela frente) |
| sqlite3 | flutter/rust | 2.1.0 (rusqlite/sqlx-sqlite no lado Rust) | 2026-05-31 | índice local + cache de leitura offline |
| path_provider | flutter | 2.1.2 | 2026-05-31 | diretórios de cache de mídia/dados por plataforma |
| web_socket_channel | flutter | 2.4.1 | 2026-05-31 | (se aplicável) canal realtime na web |
| get_it | flutter | 9.2.1 | 2026-06-14 | troca `RemoteOnly` → `LocalEngineFFI` por injeção (LSP — sem tocar telas) |
| melos | flutter | 7.8.2 | 2026-06-14 | versionamento dos packages estáveis (`api_client`, `domain_models`, `design_system_module`) |
| tokio / sqlx | rust | 1.38 / 0.9 | 2026-05/06 | `local_engine` (lib dual-target `cdylib`/`staticlib`) |
| sha2 | rust | 0.10.x | 2026-06-02 | hash de mídia para cache por conteúdo |
| reqwest | rust | 0.12.4 | 2026-05-31 | download único da mídia via URL pré-assinada |

## Serviços Externos

### Cloudflare R2 — CORS no bucket (N5.3, mídia na web)
Fonte: [developers.cloudflare.com/r2/buckets/cors](https://developers.cloudflare.com/r2/buckets/cors/), coletado em 2026-07-06.

- Configuração: dashboard (Settings → CORS Policy), `npx wrangler r2 bucket cors set <BUCKET> --file cors.json`, ou API S3 `PutBucketCors` (aws-sdk-s3).
- **Presigned URLs exigem CORS mesmo assim**: a autenticação vem da assinatura, mas o navegador ainda aplica CORS — o CORS do bucket vale para GET/PUT/DELETE pré-assinados.
- Schema:

```json
[{
  "AllowedOrigins": ["https://app.exemplo.com"],
  "AllowedMethods": ["GET", "HEAD"],
  "AllowedHeaders": ["range"],
  "ExposeHeaders": ["ETag", "Content-Type", "Content-Length"],
  "MaxAgeSeconds": 3600
}]
```

- Gotchas: `AllowedOrigins` é `scheme://host[:port]` **sem path/barra final**; só requisições com header `Origin` recebem headers CORS; headers customizados precisam constar em `AllowedHeaders` (incluir `range` para áudio/vídeo com seek); propagação ≤ 30s; `MaxAgeSeconds` máx. 86400 (browsers limitam a ~2h).
- Versionar o `cors.json` no repositório (`infra/` ou `docker/`) e aplicar por script — config de bucket é código.

### Deploy Web (referência)
O admin **já roda** em `/v2/admin` via Caddy (plano arquivado `deploy-admin-web`) — F10 reusa o mesmo padrão (build web + Caddy same-origin com gRPC-Web) para o app operacional/tenant. Ver `.context/plans/archive/deploy-admin-web/`.

## Grupo C — Observabilidade e Auditoria (por etapa)

| Etapa | Logs/trace | Auditoria | Sanitização |
|---|---|---|---|
| N5.1 consolidação (F7) | logs de UI sem PII; estados de erro padronizados (`AppErrorView`) | sem evento (client-side) | tokens só em `flutter_secure_storage` |
| N5.2 FFI/offline (F8) | erros de sync/FFI estruturados (tentativa/estado, sem conteúdo) | ações offline são auditadas **no servidor quando sincronizam** (com o ator real) | cache local sem segredo; mídia por hash sem metadado sensível em claro |
| N5.3 paridade web (F10) | logs de carregamento de mídia (status, sem URL assinada completa — a assinatura é credencial temporária) | sem evento | presigned URL não vai para log |

## Notas Gerais
- **Princípio inviolável 4:** `local_engine` não carrega lógica multi-tenant sensível nem de webhook.
- **Prova do port (LSP):** se a troca `RemoteOnly` → `LocalEngineFFI` exigir mudar tela, o `DataSource` estava vazando — corrigir o port, não a tela.
- Sync offline: last-write-wins + versionamento; idempotência por id; auditoria server-side no sync.
- N5 só entra após N1–N4 estáveis em produção.
