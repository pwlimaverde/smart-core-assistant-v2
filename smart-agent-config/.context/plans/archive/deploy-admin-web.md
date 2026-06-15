---
status: archived
generated: 2026-06-15
prevc_scale: MEDIUM
artifacts:
  plano_completo: "./deploy-admin-web/plano_completo_deploy-admin-web.md"
  info_aux: "./deploy-admin-web/info_aux_deploy-admin-web.md"
phases:
  - id: "phase-p"
    name: "Planning — escopo, domínios, build location, endpoint"
    prevc: "P"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — same-origin/CORS, Caddy subpath, portas por ambiente"
    prevc: "R"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — app, Caddyfile, server-setup, .env, CI, deploy dev/prod, docs"
    prevc: "E"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — CI verde, dev/prod acessíveis, same-origin, rollback, segurança"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — final-review, docs e arquivamento"
    prevc: "C"
    agent: "code-reviewer"
    status: "completed"
---

# Deploy do admin Flutter Web no CI/CD sob `/v2/admin` (dev + prod)

> Incluir o build e o deploy do bundle Flutter Web (`smart-core-admin`) no CI/CD, servindo o
> admin em **`/v2/admin`** no **mesmo domínio** do gRPC-Web de cada ambiente (same-origin):
> prod `smartcoreassistant.com.br`, dev `dev.smartcoreassistant.com.br`. Build no **runner
> self-hosted** (Flutter SDK no `gh-runner`); endpoint via **`--dart-define`**; Caddy serve os
> estáticos sob o subpath + `reverse_proxy` do gRPC-Web por content-type.

## Artefatos detalhados (fonte da verdade)

- **Plano completo (verdade técnica, fases e código):** [plano_completo_deploy-admin-web.md](./deploy-admin-web/plano_completo_deploy-admin-web.md)
- **Documentação auxiliar (Caddy, Flutter/CI, libs):** [info_aux_deploy-admin-web.md](./deploy-admin-web/info_aux_deploy-admin-web.md)

## Diretrizes travadas

| # | Diretriz |
|---|----------|
| Domínios | Apex + dev: prod `smartcoreassistant.com.br/v2/admin`, dev `dev.smartcoreassistant.com.br/v2/admin`. gRPC-Web **same-origin** (roteado por `Content-Type: application/grpc-web*`). |
| Build do web | No **runner self-hosted** (Hostinger): instalar Flutter SDK para o `gh-runner`. |
| Endpoint | Build-time `--dart-define=SMARTCORE_API_ENDPOINT=<origem>` por ambiente; sem mudança em `main_*.dart`. |
| Portas fachada | `RUNTIME_API_GRPC_WEB_ADDR` por ambiente (bind localhost): prod `127.0.0.1:50051`, dev `127.0.0.1:50061`. |
| Web roots | `/srv/smart-core-admin/{prod,dev}/web`. |
| Subpath | `--base-href /v2/admin/` + `usePathUrlStrategy()` + SPA fallback (`try_files`) no Caddy. |
| Debug local | 3º contexto: VS Code F5 (compound) / `flutter run`, `main_dev`, **direto no dev remoto** (`https://dev.smartcoreassistant.com.br`), base-href `/`, sem `--wasm`. Cross-origin → matcher do Caddy por **path** (`/smartcore.contracts.*`) cobre o preflight `OPTIONS`; fachada já responde via `CorsLayer mirror_request`. |
| Reuso | Padrão de deploy/rollback existente (symlink prod, `bin.bak` dev), self-hosted runner, sudoers `gh-runner`; fachada gRPC-Web já instrumentada (inalterada, só muda o bind). |

## Fases PREVC

- **P — Planning** ✅ concluído: domínios (apex+dev), build no self-hosted, endpoint via dart-define, portas por ambiente, web roots, base-href + path strategy.
- **R — Review:** ratificar same-origin (deploy) e cross-origin (debug local); matcher do Caddy por **path** (`/smartcore.contracts.*`) cobre o preflight `OPTIONS` — não por content-type; `reverse_proxy` sem h2c (gRPC-Web é HTTP/1.1); path strategy exige `try_files`; porta por ambiente; reuso do padrão de deploy; `detect` do CI → `clients/pubspec.yaml`; Caddyfile versionado como fonte da verdade.
- **E — Execution:** E1 app (`usePathUrlStrategy`) → E2 `infra/Caddyfile` (apex+dev, matcher por path) → E3 `server-setup.sh` (Flutter SDK + web roots + copiar Caddyfile + DNS) → E4 `.env` (`RUNTIME_API_GRPC_WEB_ADDR`) → E5 `ci.yml` (detect + job Flutter via melos + smoke `--wasm`) → E6 `deploy-dev.yml` (build+publish web, rollback) → E7 `deploy-prod.yml` (web versionado + symlink) → E9 `.vscode/launch.json` (debug local compound → dev remoto) → E8 docs.
- **V — Validation:** **debug local (F5)** login ponta-a-ponta contra dev remoto sem erro de CORS (preflight 200); CI verde; `https://dev.smartcoreassistant.com.br/v2/admin` login (porta 50061); `https://smartcoreassistant.com.br/v2/admin` idem (50051); rollback dev/prod; CSP/HSTS + fachada não exposta direto; TLS automático.
- **C — Confirmation:** gate `prevc-final-review`, docs (`10`/`09`), arquivamento do plano.

## Riscos-chave

1. **Disco do KVM2 (8GB)** — Flutter SDK (~1.5GB) + caches; mitigar com `flutter precache --web` e limpeza periódica.
2. **Domínios `api.`/`dev-api.`/`grafana.` legados** — confirmar uso antes de mexer; este plano só **adiciona** apex/dev.
3. **Colisão de porta** — sem `RUNTIME_API_GRPC_WEB_ADDR` por ambiente, dev e prod batem no default `0.0.0.0:50051`.
4. **DNS + TLS** — apex e dev devem apontar para o IP antes de subir o Caddy (emissão Let's Encrypt automática).

## Observabilidade & Auditoria

Plano de **infra/CI** — sem novo comportamento de domínio. App não emite log/auditoria nova (a
linha `usePathUrlStrategy()` não tem evento — intencional). Observabilidade vem de **Caddy
access logs** (`/var/log/caddy/admin-*.log`), **logs do GitHub Actions** e `systemctl is-active`
(smoke). A **fachada gRPC-Web já é instrumentada** (span/traceparent por RPC, auditoria
`login_success`/`token_reuse_detected`/`logout` server-side) e permanece **inalterada** — só
muda o bind por ambiente. Nenhum segredo em log (endpoints são públicos).
