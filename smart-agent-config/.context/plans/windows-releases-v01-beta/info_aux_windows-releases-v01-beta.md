# Informações auxiliares — windows-releases-v01-beta

## 1. Mapa de serviços envolvidos

| Serviço | Papel nesta entrega | Arquivos-chave | Porta |
|---|---|---|---|
| `runtime_api` | Borda gRPC-Web do admin: guarda `is_superuser`, chama o control_plane, devolve a URL | `server/apps/runtime_api/src/grpc_web.rs` (`exigir_superuser_do_metadata`, padrão `TestEvolutionConnection`), `audit.rs` | 50051 |
| `control_plane` | Emite o ticket assinado, lê o manifesto e audita | `server/apps/control_plane/src/main.rs` (`Server::from_env("CONTROL_PLANE").route(...)`) | RPC interno; HTTP 8095 só para OAuth MCP |
| `releases_server` | Serve feed/pacotes, valida ticket, recebe upload do CI | `server/apps/releases_server/src/main.rs`, `docker/releases/` | 8086 (127.0.0.1) |
| `data_postgres` | Consome o `security:stream` e consolida em `audit_log` | — | interno |
| Admin Flutter | Tela "Instalador Windows" | `clients/apps/smart-core-admin` → `admin_module` | 8081 via Caddy `/v2/admin` |
| App tenant | Cliente Velopack (auto-update) | `clients/apps/smart-core-tenant/lib/main_*.dart`, `pubspec.yaml` | — |
| Caddy (edge) | TLS e roteamento `releases.` | `docker/edge/Caddyfile` | 80/443 |

## 2. Bibliotecas Rust

| Crate | Uso | Observação |
|---|---|---|
| `axum 0.8` | Rotas do releases_server | Parâmetro de rota é `{nome}`; `:nome` entra em pânico na 0.8. `DefaultBodyLimit::max(..)` para o upload. Multipart com a feature `multipart` |
| `tower-http 0.6` | `TraceLayer`, `CompressionLayer` (só JSON), `SetRequestIdLayer` | Não usar `ServeDir` na raiz do diretório de releases |
| `tokio` / `tokio-util` | `File` + `ReaderStream` para servir sem bufferizar | `Body::from_stream` |
| `hmac 0.12` + `sha2 0.10` | Assinatura do ticket | `Mac::verify_slice` já compara em tempo constante |
| `subtle` (workspace) | Comparação do token de upload | Comparar `sha256(a)` com `sha256(b)` para não vazar o tamanho |
| `secrecy` (workspace) | `SecretString` para os segredos | Exige `use secrecy::ExposeSecret` (G2) |
| `base64` (workspace) | `URL_SAFE_NO_PAD` no ticket | — |
| `tower_governor` | Rate limit por IP | Conferir a versão compatível com axum 0.8/tower 0.5 na fase R; extrator de IP via `X-Forwarded-For` confiando só no Caddy |
| `observability` (interno) | `init_telemetry`, `instalar_hook_de_panic`, `aguardar_sinal_de_parada`, `AuditLogPayload` | Substitui o `tracing_subscriber` local |
| `transport` (interno) | `publicar_evento_seguranca`, `Server`, `MuxClient` | Mesmo bus `security:stream` |

Docs locais: `doc_dev/libs/rust/{axum,tower-http,tokio,serde,tracing}.md`.

## 3. Velopack — fatos confirmados (context7 `/velopack/velopack.docs`)

- Todo release pertence a um canal. Sem `--channel`, o canal é o nome do SO (`win`).
- Cada canal gera `releases.{canal}.json` e, por compatibilidade, `RELEASES-{canal}`.
- Formato do feed: `{"Assets":[{"PackageId","Version","Type":"Full|Delta","FileName","SHA1","SHA256","Size"}]}`. **Não escrever à mão**: o feed tem que refletir exatamente os arquivos publicados.
- O `UpdateManager` consulta `{baseUrl}/releases.{canal}.json` e baixa os `.nupkg` relativos à mesma base.
- O `vpk pack` gera o próprio `{PackId}-win-Setup.exe`, e é esse instalador que deixa o `Update.exe` no lugar certo. Um Setup NSIS não substitui isso (G13, D1).
- Delta exige o pacote anterior disponível na hora do `pack` (`vpk download http --url ...`).
- Versão SemVer2 com pré-release (`0.1.0-beta.1`) é suportada; prefira `-beta.N` a `-beta` puro, para ordenar as betas.

## 4. Layout de disco proposto

```
/opt/smartcore/releases/
├── env/releases.env            (600, fora do volume servido)
└── data/                       → montado em /data/releases
    ├── packages/
    │   └── 0.1.0-beta.1/
    │       ├── SmartCoreTenant-0.1.0-beta.1-full.nupkg
    │       └── SmartCoreTenant-win-Setup.exe
    └── feeds/
        └── beta/
            ├── releases.beta.json          (vigente; troca por rename)
            ├── RELEASES-beta
            └── history/0.1.0-beta.1.json   (para rollback)
```

O control_plane monta `data/feeds` como `:ro` para ler o manifesto.

## 5. Variáveis de ambiente novas

| Variável | Serviço | Conteúdo |
|---|---|---|
| `RELEASES_DOWNLOAD_SECRET` | control_plane, releases_server | 32 bytes aleatórios (hex); com `RELEASES_DOWNLOAD_KID` |
| `RELEASES_DOWNLOAD_SECRET_PREV` | releases_server | Segredo anterior durante a rotação (opcional) |
| `RELEASES_PUBLIC_BASE_URL` | control_plane, runtime_api | `https://releases.smartcoreassistant.com.br` |
| `RELEASES_MANIFEST_DIR` | control_plane | `/data/releases/feeds` |
| `RELEASES_UPLOAD_TOKEN` | releases_server, secret do GitHub | Já existe; **rotacionar** (G5/G6) |
| `REDIS_BUS_URL` | releases_server | Só se D3 decidir auditar pelo bus |

## 6. Decisões (registro)

| ID | Decisão | Recomendação | Motivo |
|---|---|---|---|
| D1 | NSIS x Setup do Velopack | Velopack | Um único instalador compatível com o auto-update; o branding vai via `--icon`/`--splashImage` |
| D2 | Proteção do feed beta e dos `.nupkg` | Públicos com rate limit | O app exige login no runtime_api; o Velopack não carrega o JWT do usuário no `UpdateManager` sem um downloader customizado |
| D3 | Ticket de uso único | Reutilizável no TTL (5 min) | Uso único exige estado (Redis) no releases_server; retomada de download quebraria |
| D4 | Quem assina | control_plane | Back office e auditoria já estão lá; o runtime_api fica só como borda |
| D5 | Assinatura Authenticode | Fora da beta | Sem certificado; documentar o aviso do SmartScreen |
| D6 | Tags | `win-vX.Y.Z-beta.N` (beta) e `win-vX.Y.Z` (stable) | Não colide com `v*` do deploy-prod |

## 7. Agentes dotcontext sugeridos por fase

| Fase | Agentes |
|---|---|
| P | architect-specialist, security-auditor |
| R | code-reviewer, security-auditor, performance-optimizer |
| E | backend-specialist (E1–E3), frontend-specialist (E4), devops-specialist (E5–E6) |
| V | test-writer, security-auditor |
| C | devops-specialist, documentation-writer |

## 8. Fora de escopo
- Landing page pública e canal `stable` (plano `servidor-releases-windows` / `n12-cutover-producao`)
- Qualquer alteração no v1 Django (`smartcoreassistant_*`)
- Assinatura de código e Microsoft Store
