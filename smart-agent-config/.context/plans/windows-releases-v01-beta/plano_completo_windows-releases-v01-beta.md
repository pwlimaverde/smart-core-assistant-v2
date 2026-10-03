# Plano completo — windows-releases-v01-beta

> Canônico leve: [`../windows-releases-v01-beta.md`](../windows-releases-v01-beta.md).
> Referências técnicas: [`info_aux_windows-releases-v01-beta.md`](./info_aux_windows-releases-v01-beta.md).
> Revisão feita em 2026-10-03, direto no servidor `srv1321059`, contra a branch `dev` (`fd2135d7`).

---

## 0. Revisão de arquitetura (o que foi confirmado e o que não foi)

| Pergunta | Resposta | Evidência |
|---|---|---|
| O control_plane serve HTTP? | **Sim, mas só o authorization server OAuth do MCP** (porta 8095, `auth.` e `auth.dev.`). Todo o resto é RPC interno via `transport`. | `server/apps/control_plane/src/main.rs` (`montar_oauth`), `oauth/mod.rs::rotas`, `docker/edge/Caddyfile` linhas 177–232 |
| Um endpoint novo no control_plane fica acessível ao admin? | **Não diretamente.** O admin `/v2/admin` é Flutter web servido na porta 8081 e fala gRPC-Web com o `runtime_api` (50051). O caminho certo é `runtime_api` (AdminService) → `transport` → control_plane. | `Caddyfile` linhas 101–157; padrão `TestEvolutionConnection` em `runtime_api/src/grpc_web.rs` |
| Como se valida a permissão? | Claim `is_superuser` do JWT, via `exigir_superuser_do_metadata`, que já audita `auth_access_denied`. Escopos finos via `rbac::autorizado`. Não é OAuth/roles do MCP. | `runtime_api/src/grpc_web.rs:817` |
| O releases_server hospeda `.nupkg`/`.exe`? | **Ainda não.** Os handlers são stub, o código não compila e o crate está fora do workspace. Nada escuta em 8086. | `server/apps/releases_server/src/main.rs`, `server/Cargo.toml` |
| A separação dev (beta) x prod (v1.0.0+) é clara? | **Só no papel.** O workflow empacota com `--channel win`, o feed publicado diz `"channel":"beta"` num formato próprio, e os dois workflows disparam na mesma tag. | `.github/workflows/build-windows-installer.yml`, `/opt/smartcore/releases/releases.win.json` |
| O Velopack é o cliente que checa `releases.win.json`? | **Sim para o canal padrão `win`.** No canal `beta` ele lê `releases.beta.json`. O formato é `{"Assets":[{PackageId, Version, Type, FileName, SHA1, SHA256, Size}]}`, gerado pelo `vpk pack`, e não deve ser escrito à mão. | Docs Velopack (context7 `/velopack/velopack.docs`: channels, distributing/overview) |
| O app tenant já integra o Velopack? | **Não.** `main_branded.dart` importa `velopack_flutter`, mas o pacote não está no `pubspec.yaml` e o entrypoint real é `main_dev.dart`/`main_prod.dart`. | `clients/apps/smart-core-tenant/` |
| O link é público sem proteção? | **Hoje ele nem responde** (sem bloco no Caddy, o TLS falha). O risco é latente: ao adicionar o bloco, o `ServeDir` expõe `.env` com o token de upload. | `curl` em 2026-10-03; G5/G14 |

---

## 1. PLANNING (P) — Requisitos, segurança e contrato

### 1.1 Requisitos funcionais

| ID | Requisito |
|---|---|
| RF1 | Superusuário logado no admin DEV vê a tela "Instalador Windows" com a versão beta vigente, data, tamanho, SHA-256 e release notes. |
| RF2 | Ao clicar em "Baixar", o admin obtém um link válido por 5 minutos e o navegador baixa o Setup.exe direto do releases_server. |
| RF3 | Um usuário sem `is_superuser` recebe `PERMISSION_DENIED`; a tela não aparece no menu. |
| RF4 | O app instalado verifica atualizações no canal `beta` e aplica na próxima reinicialização. |
| RF5 | O CI publica uma versão nova (Setup.exe + `.nupkg` full/delta + `releases.beta.json`) com upload autenticado; a troca do feed é atômica. |
| RF6 | O operador consegue reverter o feed para a versão anterior com um comando, sem apagar pacotes. |

### 1.2 Requisitos de segurança

| ID | Requisito |
|---|---|
| RS1 | O Setup.exe só sai com um ticket HMAC válido: assinatura, `exp`, `version` e `file` precisam conferir com a URL. |
| RS2 | Nenhum arquivo fora da allowlist (`*.nupkg`, `*-Setup.exe`, `releases.*.json`, `RELEASES*`) é servido; nada de `ServeDir` na raiz. |
| RS3 | Path traversal impossível: `version` casa com `^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$`, `file` com regex fixa, e o caminho final é canonicalizado e confere o prefixo. |
| RS4 | Token de upload comparado com `subtle::ConstantTimeEq` sobre o SHA-256 dos dois lados (assim o tamanho não vaza). |
| RS5 | Os segredos (`RELEASES_UPLOAD_TOKEN`, `RELEASES_DOWNLOAD_SECRET`) vivem em `SecretString`, em arquivo 600, e nunca aparecem em log, `Debug` ou resposta. |
| RS6 | Upload com `DefaultBodyLimit` explícito (sugestão: 300 MB), streaming para arquivo temporário, conferência do SHA-256 antes do `rename`. |
| RS7 | Rate limit: emissão de ticket ≤ 10/min por usuário; download ≤ 30/min por IP; upload ≤ 5/min. |
| RS8 | O segredo do ticket é o mesmo nos dois lados (control_plane assina, releases_server valida) e é rotacionável com janela de dois segredos (`kid`). |

### 1.3 Contratos

**Proto (`server/crates/contracts/schemas/queries/admin.proto`, `service AdminService`):**

```proto
rpc GetWindowsDownloadLink(GetWindowsDownloadLinkRequest) returns (GetWindowsDownloadLinkResponse);

message GetWindowsDownloadLinkRequest {
  string channel = 1;   // "beta" nesta entrega; "stable" é recusado até v1.0.0
  string version = 2;   // vazio = a mais recente do canal
}
message GetWindowsDownloadLinkResponse {
  string url = 1;            // https://releases.../download/{v}/{file}?t=...
  string version = 2;
  string file_name = 3;
  int64  size_bytes = 4;
  string sha256 = 5;
  string release_notes_md = 6;
  int64  expires_at_ms = 7;
}
```

**RPC interno (`control_plane`, método `IssueReleaseDownloadTicket`):** o payload JSON
`{channel, version}` responde os mesmos campos acima. O `Envelope` carrega
`auth_user_id`, `auth_is_superuser` e `traceparent`, como os demais RPCs admin.

**Ticket:** `base64url(claims_json) + "." + base64url(HMAC_SHA256(secret[kid], claims_json))`

```json
{ "v": 1, "kid": "k1", "jti": "<uuid v7>", "sub": 42,
  "ver": "0.1.0-beta.1", "file": "SmartCoreTenant-win-Setup.exe",
  "ch": "beta", "iat": 1759500000, "exp": 1759500300 }
```

### 1.4 Subtarefas e critérios de sucesso

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| P1 | Registrar D1–D6 (canônico) | Cada decisão com dono e justificativa |
| P2 | Fechar o proto e o RPC interno | Revisado pelo backend-specialist |
| P3 | Formato do ticket + rotação (`kid`) | Revisado pelo security-auditor |
| P4 | Catálogo de eventos (§6) + métricas (§7) | Nomes conforme `infra/PLANO_OBSERVABILIDADE.md` (sem prefixo duplicado) |
| P5 | Spike: `velopack_flutter` compila no Flutter ≥ 3.44 e roda `VelopackApp.build().run()` | Build Windows local do dev (nunca no servidor) |

### 1.5 Observabilidade/auditoria da fase P
- [ ] Catálogo de eventos aprovado e copiado para `.context/docs/security.md`
- [ ] Nomes de métricas aprovados (prefixo `smartcore_` uma única vez)
- [ ] Campos proibidos em log listados (ticket, tokens, JWT)

### 1.6 Riscos
| Risco | Mitigação |
|---|---|
| `velopack_flutter` sem suporte ao Flutter 3.44 | Spike P5 antes da fase E; plano B: FFI própria para o crate `velopack` (Rust), que o workspace já sabe compilar |
| Escopo crescer para landing/stable | Fora deste plano; fica no `servidor-releases-windows` |

---

## 2. REVIEW (R) — Code review, security audit, performance

### 2.1 Code review do que existe (achados G1–G16 do canônico)

| # | Ação | Destino |
|---|---|---|
| R1 | Confirmar G1–G4, G7, G8 como bloqueadores da fase E | E1, E6 |
| R2 | Confirmar G5 (ServeDir expõe `.env`) como crítico; **chmod 600 no `.env` e rotação do `RELEASES_UPLOAD_TOKEN` já**, independentemente do plano | Operação imediata |
| R3 | Decidir D1 (NSIS x Velopack) com base em G13 | E5 |
| R4 | Unificar os workflows (G10) | E5 |
| R5 | Avaliar se o releases_server entra no `deploy-dev.yml` (build GHCR como os demais apps) em vez de Dockerfile próprio com `rust:1.84` | E6 |

### 2.2 Security audit (desenho)
- [ ] Ticket: HMAC sobre os bytes exatos dos claims, comparação constante, `exp` com tolerância ≤ 30 s
- [ ] Sem open redirect: o `runtime_api` só devolve URL cujo host é `RELEASES_PUBLIC_BASE_URL`
- [ ] Cabeçalhos do download: `Content-Disposition: attachment`, `X-Content-Type-Options: nosniff`, `Cache-Control: private, no-store` para o Setup.exe
- [ ] O ticket vai na query string, então o log de acesso do Caddy precisa filtrar `t` (`log { format filter { request>uri query { delete t } } }`) e o `TraceLayer` não pode registrar a URI crua
- [ ] Upload só pela rede interna ou atrás de allowlist de IP do runner? O runner é self-hosted nesta máquina: preferir `127.0.0.1:8086` direto e **não** expor `/upload` no Caddy
- [ ] CORS: o download é navegação de topo, não precisa de CORS; remover `CorsLayer`

### 2.3 Performance (2 vCPU / 7,8 GB)
- Arquivos servidos com `tokio::fs::File` + `ReaderStream` (sem carregar na memória); orçamento < 30 MB RSS no releases_server
- Sem compressão em `.nupkg`/`.exe` (já são comprimidos); manter só para `.json`
- Build: **só no CI** (GitHub Actions). Proibido `cargo build` no servidor (CLAUDE.md)

### 2.4 Observabilidade/auditoria da fase R
- [ ] Revisão confirma que todo handler tem `#[instrument(skip(...))]` sem segredos
- [ ] Revisão confirma propagação do `traceparent` runtime_api → control_plane (Envelope) e control_plane → URL? Não: o traceparent **não** vai na URL; a correlação download ↔ emissão é feita pelo `jti`

### 2.5 Critério de saída
`security_review` assinado pelo security-auditor + `approval` do architect, com D1–D6 fechadas.

---

## 3. EXECUTION (E) — Implementação

### E1 — releases_server (Rust, `server/apps/releases_server`)

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| E1.1 | Incluir no `[workspace].members`; usar `workspace = true` nas dependências (axum, tokio, serde, tracing, secrecy, sha2, subtle) | `cargo check -p releases_server` verde no CI |
| E1.2 | Trocar o `tracing_subscriber` local por `observability::init_telemetry("releases_server", ...)` + `instalar_hook_de_panic` + `aguardar_sinal_de_parada` | Spans no Tempo, logs no Loki |
| E1.3 | Rotas Axum 0.8: `GET /download/{version}/{file}`, `GET /feed/{channel}/{file}`, `POST /upload`, `GET /health`, `GET /metrics` | Sem `:param`; o teste de subida não entra em pânico |
| E1.4 | Download do Setup.exe exige `?t=`; `.nupkg`/feed seguem D2 | V3–V6 |
| E1.5 | Upload multipart com streaming para `tmp/`, SHA-256 incremental, conferência contra o campo `sha256`, `rename` atômico; o feed é trocado por último (`releases.beta.json.tmp` → `rename`) | V7, V8 |
| E1.6 | Remover `ServeDir` da raiz; allowlist de nomes; canonicalização do caminho | V5 |
| E1.7 | Subcomando `releases_server rollback --channel beta --to <versao>` (mantém histórico em `feeds/beta/<versao>.json`) | V9 |
| E1.8 | Rate limit (`tower_governor`, ver info_aux) por IP real (`X-Forwarded-For` só do Caddy) | V10 |
| E1.9 | Testes reais com `tower::ServiceExt::oneshot` substituindo os `assert!(true)` | Cobertura dos handlers |

### E2 — control_plane (Rust, código novo)

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| E2.1 | Módulo `src/releases/mod.rs`: `ManifestoReleases` lê `/data/releases/feeds/beta/releases.beta.json` (bind mount `:ro`) e localiza o Setup.exe e o tamanho da versão | Teste de unidade com feed de exemplo |
| E2.2 | `src/releases/ticket.rs`: `emitir(claims, &Segredos) -> String`, com `hmac::Hmac<Sha256>` e segredos `SecretString` por `kid` | Teste: adulterar 1 byte → validação falha |
| E2.3 | Rota `.route("IssueReleaseDownloadTicket", ...)`: exige `env.auth_is_superuser == true` (defesa em profundidade) e canal `beta` | V2 |
| E2.4 | Auditoria `release_download_link_issued` via `transport::bus::publicar_evento_seguranca` (mesmo `AuditLogPayload`) | V11 |
| E2.5 | Recusa fechada se `RELEASES_DOWNLOAD_SECRET` estiver ausente: o handler responde erro `releases.nao_configurado` e o processo segue | Teste de configuração |
| E2.6 | Métrica `smartcore_releases_ticket_issued_total{channel,outcome}` | Visível no Prometheus |

O código de verificação do ticket fica num crate compartilhado pequeno
(`crates/release_ticket`), ou no `application`, para o control_plane e o
releases_server usarem a **mesma** implementação. Decidir em R.

### E3 — runtime_api (borda gRPC-Web)

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| E3.1 | Mensagens e `rpc GetWindowsDownloadLink` no `admin.proto` | Codegen no CI |
| E3.2 | Handler: `exigir_superuser_do_metadata` → `Envelope{method:"IssueReleaseDownloadTicket", auth_is_superuser:true, traceparent}` → `self.control.call(..., 10s)` | Padrão idêntico ao `TestEvolutionConnection` |
| E3.3 | Validação do host da URL devolvida (`RELEASES_PUBLIC_BASE_URL`) | Teste unitário |
| E3.4 | Mapeamento de erros: canal inválido → `INVALID_ARGUMENT`; não configurado → `FAILED_PRECONDITION`; control_plane fora → `UNAVAILABLE` | Chaves i18n `errors.releases.*` |

### E4 — Admin Flutter (`clients/apps/smart-core-admin`, `admin_module`)

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| E4.1 | Item de menu "Instalador Windows" visível só para superusuário | Teste de widget |
| E4.2 | Página com versão, data, tamanho, SHA-256 copiável e release notes (markdown) | Usa o branding `#0066CC` existente |
| E4.3 | Botão "Baixar" chama `GetWindowsDownloadLink` e abre a URL (`url_launcher`/`web.window.open`), **sem cachear** o link | O link expira em 5 min |
| E4.4 | Aviso de beta + aviso do SmartScreen (D5) | Texto revisado |

A compilação Flutter acontece **na máquina do dev ou no CI**, nunca neste servidor.

### E5 — CI / empacotamento (`.github/workflows`)

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| E5.1 | Unificar em um único `release-windows.yml` (apagar o outro); gatilho `win-v*` | Uma execução por tag |
| E5.2 | Canal derivado da tag: `-beta.N` → `--channel beta`; sem sufixo → `stable` (bloqueado até v1.0.0) | Log do job mostra o canal |
| E5.3 | Flutter alinhado ao `pubspec` (≥ 3.44); `velopack_flutter` adicionado ao pubspec; `main_branded.dart` reconciliado com `main_dev.dart` | `flutter build windows` verde |
| E5.4 | `vpk download http --url <feed>` antes do `vpk pack` (para gerar delta) | Delta presente a partir da 2ª versão |
| E5.5 | Upload de **todos** os artefatos (`*-full.nupkg`, `*-delta.nupkg`, `*-Setup.exe`, `releases.beta.json`, `RELEASES-beta`) com `sha256` por arquivo, o feed por último | V7 |
| E5.6 | Remover `--signParams` enquanto não houver certificado (D5) | O job não falha |
| E5.7 | D1: remover o NSIS do caminho do app; branding via `vpk pack --icon infra/windows/assets/... --splashImage ...` | Um único Setup.exe |
| E5.8 | Imagem do releases_server construída no `deploy-dev.yml` junto com as outras (GHCR) | `docker compose pull` funciona |

### E6 — Infra (Caddy, compose, segredos)

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| E6.1 | `docker/releases/compose.yml`: um único bind mount `/opt/smartcore/releases/data:/data/releases`, `env_file` 600, rede `otel`; remover `version:` | `docker compose config` sem erro |
| E6.2 | Mover `.env`, `server_mock.py`, `__pycache__`, `server.log` e o placeholder para fora do diretório servido | `ls` mostra só `feeds/` e `packages/` |
| E6.3 | Bloco `releases.smartcoreassistant.com.br` no Caddyfile: `reverse_proxy host.docker.internal:8086`, `@upload path /upload` → `respond 404`, filtro do `t` no log, HSTS/nosniff | `caddy validate` antes do reload (o Caddy roteia o v1 também) |
| E6.4 | `RELEASES_DOWNLOAD_SECRET` em `/opt/smartcore/dev/env/dev.env` (control_plane) e no env do releases_server; manifesto montado `:ro` no control_plane | `docker compose config` mostra a variável no serviço |
| E6.5 | Refletir cada mudança em `docker/` no repo e commitar (senão o próximo deploy sobrescreve) | Commit na `dev` |

### Observabilidade/auditoria da fase E
- [ ] `release_download_link_issued` publicado com `context = {channel, version, file, jti, exp}`, `user_id` e `trace_id`
- [ ] Spans: `runtime_api.GetWindowsDownloadLink` → `control_plane.IssueReleaseDownloadTicket` sob o mesmo trace
- [ ] releases_server loga `jti`, `version`, `file`, `outcome`, `bytes`, e **nunca** o `t`
- [ ] `/metrics` exposto e adicionado ao `prometheus.yml` (`up -d --force-recreate prometheus`)
- [ ] `release_published` / `release_upload_rejected` no upload

### Riscos da fase E
| Risco | Mitigação |
|---|---|
| Recarga do Caddy derruba v1/v2 | `caddy validate` + reload (não restart); janela fora do horário comercial |
| Build do Rust no servidor por engano | Somente CI; documentado no runbook |
| O `velopack_flutter` muda a inicialização do app | Chamar `VelopackApp.build().run()` antes do `runApp`, só em `Platform.isWindows` |
| Segredo divergente entre control_plane e releases_server | `kid` no ticket + checagem de partida que loga o `kid` ativo (nunca o valor) |

---

## 4. VALIDATION (V) — Testes, auditoria, rate limit

| ID | Teste | Esperado |
|---|---|---|
| V1 | Superusuário pede o link | 200, URL com `t`, `expires_at` ≈ agora + 5 min |
| V2 | Usuário comum pede o link | `PERMISSION_DENIED` + `auth_access_denied` no audit_log |
| V3 | Download com ticket válido | 200, `Content-Length` igual ao do manifesto, SHA-256 confere |
| V4 | Ticket expirado / adulterado / de outra versão | 403 + `release_download_ticket_rejected` + métrica `outcome="rejected"` |
| V5 | `GET /download/../.env`, `/releases/.env`, `%2e%2e` | 404/400, nenhum byte de `.env` |
| V6 | Download sem `t` do Setup.exe | 401 |
| V7 | Upload com token correto e SHA correto | Arquivos no lugar, feed trocado, `release_published` |
| V8 | Upload com SHA divergente / token errado / nome fora do padrão | 4xx, nada gravado, `release_upload_rejected` |
| V9 | `rollback --to 0.1.0-beta.1` | O feed volta; o app não vê a versão revertida |
| V10 | 40 downloads/min do mesmo IP; 15 tickets/min do mesmo usuário | 429 depois do limite, métrica `outcome="rate_limited"` |
| V11 | Correlação: `jti` do audit_log aparece no log do releases_server; trace runtime_api → control_plane no Tempo | Consulta Loki + Tempo anexada |
| V12 | VM Windows: instalar 0.1.0-beta.1, publicar 0.1.0-beta.2, abrir o app | Update baixado e aplicado no reinício |

### Observabilidade/auditoria da fase V
- [ ] `QueryAuditLog` no admin mostra `release_download_link_issued` com usuário e versão
- [ ] Alertas disparados de propósito (V4 em massa, upload falho) chegam ao contato configurado
- [ ] Nenhum log contém `t=`, `Bearer ` ou o valor de um segredo (`grep` no Loki por 1 h)

### Critério de saída
V1–V12 verdes com evidência anexada em `.context/workflow/docs/`.

---

## 5. COMPLETE (C) — Deploy, docs, runbook

| # | Subtarefa | Critério de sucesso |
|---|---|---|
| C1 | Deploy via push na `dev` (CI) e `docker compose pull && up -d` da stack releases | `/health` 200 através do Caddy |
| C2 | Publicar a 0.1.0-beta.1 real pelo CI (substitui o placeholder de 76 bytes) | O Setup.exe instala numa VM |
| C3 | Painel Grafana "Releases Windows": downloads por versão, tickets emitidos x rejeitados, latência de upload, disco | Painel no provisionamento |
| C4 | Alertas: `rejeições > 20/10min`, `upload falhou`, `disco livre < 10%`, `releases_server down` | Regras em `prometheus`/Grafana |
| C5 | Runbook: publicar, reverter, rotacionar `RELEASES_UPLOAD_TOKEN`/`RELEASES_DOWNLOAD_SECRET` (`kid`), revogar todos os tickets (trocar o `kid`) e investigar download suspeito | `docker/releases/README.md` |
| C6 | Remover `INTEGRACAO_DOWNLOAD_ADMIN.md` e corrigir `docker/releases/README.md` | Sem menção a Django para o v2 |
| C7 | Atualizar `.context/docs/security.md` (catálogo) e `architecture.md` (novo serviço) | Diff revisado |

### Observabilidade/auditoria da fase C
- [ ] Dashboard e alertas versionados no repo (`docker/observability/`)
- [ ] Retenção do audit_log cobre o período de beta
- [ ] Handoff com consultas Loki/Tempo prontas para investigar um `jti`

---

## 6. Catálogo de auditoria (security:stream → audit_log)

| `event` | `service` | `level` | `user_id` | `context` |
|---|---|---|---|---|
| `release_download_link_issued` | control_plane | INFO | quem pediu | `{channel, version, file, jti, exp}` |
| `auth_access_denied` | runtime_api | WARN | quem pediu | `{}` (guarda existente) |
| `release_download_ticket_rejected` | releases_server | WARN | `sub` do ticket, se legível | `{reason: expired\|bad_sig\|mismatch\|unknown_kid, jti?}` |
| `release_published` | releases_server | INFO | nulo (CI) | `{channel, version, files:[{name,sha256,size}], git_sha}` |
| `release_upload_rejected` | releases_server | WARN | nulo | `{reason, version?, file?}` |
| `release_rolled_back` | releases_server | WARN | nulo (CLI) | `{channel, from, to}` |

O releases_server precisa de `REDIS_BUS_URL` para publicar no bus. Se D3 mantiver o
serviço sem Redis, os três eventos dele viram log estruturado (Loki) e entram no
audit_log numa segunda etapa. Decidir em R.

## 7. Métricas

| Nome | Tipo | Labels |
|---|---|---|
| `smartcore_releases_ticket_issued_total` | counter | `channel`, `outcome` |
| `smartcore_releases_download_total` | counter | `channel`, `version`, `kind` (setup\|full\|delta\|feed), `outcome` |
| `smartcore_releases_download_bytes_total` | counter | `kind` |
| `smartcore_releases_upload_total` | counter | `outcome` |
| `smartcore_releases_upload_duration_seconds` | histogram | — |
| `smartcore_releases_disk_free_bytes` | gauge | — |

`version` tem cardinalidade baixa (poucas betas). Mesmo assim, limitar às 10 versões
mais recentes.

## 8. Dependências

| Interna | Externa |
|---|---|
| `contracts` (proto admin), `transport`, `observability`, `application::jwt` | Velopack CLI `vpk` + `velopack_flutter` (pub.dev) |
| Stack `smart-core-v2-observability` (Prometheus, Loki, Tempo) | GitHub Actions (runner Windows hospedado + self-hosted para deploy) |
| `smart-core-v2-edge` (Caddy) | DNS `releases.` (já aponta para 76.13.229.210) |
| `infra/PLANO_OBSERVABILIDADE.md` (convenção de nome de métrica) | GHCR |

## 9. Ação imediata, independente do plano

1. `chmod 600 /opt/smartcore/releases/.env` e rotacionar `RELEASES_UPLOAD_TOKEN` (secret do GitHub + `.env`).
2. **Não** adicionar o bloco `releases.` no Caddy antes de E1.6 (fim do `ServeDir` na raiz).
3. Retirar o anúncio do placeholder: o Setup.exe de 76 bytes não é um instalador.
