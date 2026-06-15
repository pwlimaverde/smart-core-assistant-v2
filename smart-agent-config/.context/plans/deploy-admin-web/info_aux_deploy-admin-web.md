# Documentação Auxiliar — Deploy do admin Flutter Web sob `/v2/admin`

> Gerado em: 2026-06-15
> Plano canônico: `.context/plans/deploy-admin-web.md`
> Plano completo: `.context/plans/deploy-admin-web/plano_completo_deploy-admin-web.md`
> Origem do plano: conversa (sessão jun/2026), plano aprovado em plan mode.

Plano de **infra/CI-CD** (quase nenhum código novo de aplicação). Reúne a referência atual
de Caddy v2 (reverse proxy + SPA sob subpath), build Flutter Web sob subpath e GitHub Actions.

---

## 0. Contexto fixado (decisões travadas)

- **Domínios (apex + dev):** prod `https://smartcoreassistant.com.br/v2/admin`;
  dev `https://dev.smartcoreassistant.com.br/v2/admin`. gRPC-Web **same-origin** (roteado por
  `Content-Type: application/grpc-web*`).
- **Build do web:** no **runner self-hosted** (Hostinger), junto do build Rust → instalar
  Flutter SDK para o usuário `gh-runner`.
- **Endpoint do app:** build-time `--dart-define=SMARTCORE_API_ENDPOINT=<origem>` por ambiente.
- **Portas da fachada gRPC-Web** (env `RUNTIME_API_GRPC_WEB_ADDR`, bind localhost):
  prod `127.0.0.1:50051`, dev `127.0.0.1:50061`.
- **Web roots:** `/srv/smart-core-admin/{prod,dev}/web`.
- **Debug local (3º ambiente):** rodar o app em debug (VS Code F5 / `flutter run -d chrome`,
  `main_dev.dart`) apontando **direto para o backend dev remoto** `https://dev.smartcoreassistant.com.br`
  (sem Rust local). Disparo por **compound F5** no `.vscode/launch.json` (como o backend é
  remoto, o compound reduz-se à app Flutter — extensível p/ Rust local no futuro). Cross-origin
  → exige matcher por path no Caddy (preflight) + CORS na fachada. Ver §6.

---

## 1. Libs (USAR LOCAL — central já curada)

Nenhuma lib nova. As envolvidas já têm doc local válida e foram exercitadas no ciclo
`login-module`:

- **go_router** — `doc_dev/libs/flutter/go_router.md`. Rotas absolutas (`/login`, `/home`)
  permanecem **puras** (sem prefixo `/v2/admin`); o subpath é responsabilidade do `<base href>`
  + servidor. O navegador combina `<base href="/v2/admin/">` + rota interna.
- **melos** — `doc_dev/libs/flutter/melos.md`. Scripts `analyze`/`test` já definidos em
  `clients/pubspec.yaml` (workspace). CI usa `melos run analyze` / `melos run test`.
- **flutter / flutter_web_plugins** — `doc_dev/libs/flutter/flutter.md`. `usePathUrlStrategy()`
  vem de `package:flutter_web_plugins` (parte do SDK; sem nova dep no pubspec).
- **grpc / tonic-web** — `doc_dev/libs/flutter/grpc.md`, `doc_dev/libs/rust/tonic-web.md`.
  Já validados: `grpc 4.x` (web sobre `package:web`, WASM-safe); fachada Tonic com
  `accept_http1` + CORS→GrpcWebLayer.

> Caddy e `subosito/flutter-action` são **ferramentas de infra/CI**, fora do escopo da central
> de libs por linguagem (`doc_dev/libs/{rust,python,flutter}`). Documentação atual coletada via
> WebFetch abaixo, registrada aqui no info_aux.

---

## 2. Caddy v2 — SPA sob subpath + gRPC-Web same-origin (WebFetch jun/2026)

Fontes: caddyserver.com/docs (caddyfile/concepts, directives `handle`, `handle_path`,
`reverse_proxy`, `file_server`, `try_files`, `header`, `encode`; matchers; automatic-https).

### 2.1 Diretivas-chave
- **`handle` vs `handle_path` vs `route`:** `handle` = blocos mutuamente exclusivos (só o
  primeiro match roda; diretivas reordenadas). `handle_path /v2/admin/*` = `handle` +
  **strip do prefixo** (`/v2/admin/main.dart.js` → `/main.dart.js`). `route` preserva ordem
  literal (não precisamos aqui).
- **Named matcher por header (escopo do site block):**
  `@grpcweb header Content-Type application/grpc-web*` (wildcard prefix). Combinar com
  `handle @grpcweb { reverse_proxy ... }`. **Definir o matcher DENTRO do site block.**
- **gRPC-Web reverse_proxy:** gRPC-Web trafega sobre HTTP/1.1; Caddy negocia sozinho.
  **Não usar `h2c://`** para a fachada Tonic (que escuta HTTP/1.1 plano em 127.0.0.1).
  `reverse_proxy 127.0.0.1:50051` basta. (h2c seria para gRPC puro, não é o caso.)
- **SPA fallback dentro do `handle_path`:** `root * <webroot>` + `try_files {path} /index.html`
  + `file_server`. Após o strip, `{path}` é relativo ao webroot; rotas client-side caem no
  `index.html` (necessário para **path URL strategy**, senão 404 no refresh/deep-link).
- **`header` com matcher de path:** `header /v2/admin/* { ... }` aplica CSP/HSTS só no subpath.
- **`encode gzip zstd`** comprime texto/js/wasm (>512 bytes).
- **Automatic HTTPS:** um site block por domínio (apex + dev) → certificado Let's Encrypt
  automático; HTTP→HTTPS automático.

### 2.2 Caddyfile de referência (a adaptar para 2 ambientes)
> **Matcher por PATH (não por content-type).** O gRPC-Web roda no namespace
> `/smartcore.contracts.*` (raiz). Matchar por **path** captura tanto o POST gRPC-Web quanto o
> **preflight `OPTIONS`** (cross-origin do debug local). Matchar só por `Content-Type:
> application/grpc-web*` **perde o preflight** (OPTIONS não carrega esse header) → CORS quebra
> no debug local contra o dev remoto. Ver §6.
```caddyfile
smartcoreassistant.com.br {
  encode gzip zstd

  # gRPC-Web por PATH do namespace do contrato (pega POST + preflight OPTIONS).
  @grpcapi path /smartcore.contracts.*
  handle @grpcapi {
    reverse_proxy 127.0.0.1:50051
  }

  # Bundle Flutter sob /v2/admin/* (handle_path remove o prefixo).
  handle_path /v2/admin/* {
    root * /srv/smart-core-admin/prod/web
    header {
      Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
      Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      X-Content-Type-Options "nosniff"
      X-Frame-Options "DENY"
      Referrer-Policy "strict-origin-when-cross-origin"
      -Server
    }
    try_files {path} /index.html
    file_server
  }
}

dev.smartcoreassistant.com.br {
  encode gzip zstd
  @grpcapi path /smartcore.contracts.*
  handle @grpcapi { reverse_proxy 127.0.0.1:50061 }
  handle_path /v2/admin/* {
    root * /srv/smart-core-admin/dev/web
    header { Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'"; Strict-Transport-Security "max-age=31536000; includeSubDomains" }
    try_files {path} /index.html
    file_server
  }
}
```

### 2.3 Pegadinhas
- **Matcher por path** captura o gRPC-Web (`/smartcore.contracts.queries.AuthService/*`) e o
  preflight `OPTIONS` no mesmo caminho — essencial para o debug local cross-origin (§6). Não
  colide com `/v2/admin/*` (namespaces de path distintos na raiz).
- `connect-src 'self'` cobre o caso same-origin (prod/dev servindo o bundle); o debug local é
  servido pelo dev server do Flutter (localhost), cujo CSP não restringe `connect-src` ao dev
  remoto.
- Ordem: `handle @grpcapi` e `handle_path /v2/admin/*` são exclusivos; o path do gRPC fica na
  raiz, o do bundle sob `/v2/admin/`.
- **WASM multi-thread (skwasm) exige `Cross-Origin-Opener-Policy: same-origin` +
  `Cross-Origin-Embedder-Policy: require-corp`.** O build atual (`flutter build web --wasm`)
  funciona sem eles em modo single-thread/JS-fallback; só adicionar COOP/COEP se habilitar
  threads (cuidado: COEP pode quebrar recursos cross-origin). **Decisão:** não habilitar
  COOP/COEP por ora (mantém simplicidade); revisitar se ativar rendering multithread.

---

## 3. Flutter Web sob subpath + GitHub Actions (WebFetch jun/2026)

Fontes: docs.flutter.dev (url-strategies, web/wasm, install/linux, deployment/web),
github.com/subosito/flutter-action, issues flutter #107996/#129422.

### 3.1 Build sob subpath
- `flutter build web --wasm --base-href=/v2/admin/ -t lib/main_<flavor>.dart --dart-define=SMARTCORE_API_ENDPOINT=<origem>`.
  `--base-href` **deve** começar/terminar com `/`. Substitui `$FLUTTER_BASE_HREF` no
  `web/index.html` (placeholder já presente no app — confirmado).
- `--wasm` combina com `--base-href` e `--dart-define` normalmente. Saída em `build/web`.
- **`usePathUrlStrategy()`** (de `package:flutter_web_plugins/url_strategy.dart`) **antes do
  runApp/bootstrap** → URLs limpas (`/v2/admin/login`). Exige rewrite no servidor (o
  `try_files` do Caddy resolve). Sem ela, hash strategy (`/v2/admin/#/login`) dispensa rewrite.
  **Decisão do plano:** path strategy + `try_files`.
- go_router: rotas **puras** (`/login`, `/home`); o navegador resolve relativo ao base href.
- `--dart-define=CHAVE=valor` → `String.fromEnvironment('CHAVE')` (const). `main_prod.dart` já
  lê `SMARTCORE_API_ENDPOINT`; `_normalizarEndpoint` preserva `https://`.
- Limitação WASM: nada de `dart:html`/`package:js` (já migrado para `package:web`); iOS sem
  WasmGC (fallback JS) — irrelevante para admin desktop/web.

### 3.2 CI — `subosito/flutter-action@v2` (v2.23.0)
```yaml
- uses: subosito/flutter-action@v2
  with: { channel: stable, flutter-version: 3.x, cache: true }
- run: dart pub get   # em clients/ (workspace)
- run: dart pub global activate melos && melos run analyze && melos run test
```

### 3.3 Flutter SDK no runner self-hosted (Hostinger / usuário gh-runner)
```bash
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
echo "$HOME/flutter/bin" >> "$GITHUB_PATH"        # persiste PATH entre steps
git config --global --add safe.directory "$HOME/flutter"  # evita "dubious ownership"
flutter precache --web                             # baixa só artefatos web
flutter --version
```
Pegadinhas: `export PATH` só vale no mesmo `run` (use `$GITHUB_PATH`); `--depth 1` pode faltar
tags (`git -C "$HOME/flutter" fetch --tags` se erro de versão); atualizar o SDK em runner
persistente periodicamente (`git -C "$HOME/flutter" pull`). No `server-setup.sh` o clone é
one-shot no provisionamento; o PATH entra no `.bashrc` do gh-runner.

---

## 4. Observabilidade & Auditoria (Grupo C — transversal)

Plano de **infra/CI**, sem novo comportamento de domínio:
- **App (uma linha `usePathUrlStrategy()`):** não emite log/trace; **sem evento de auditoria**
  (intencional). Mantém o já estabelecido no `login-module`: client loga só endpoint/status,
  sem token/PII; auditoria é server-side.
- **Caddy:** access logs por site (stdout/journald). CSP/HSTS reforçados no subpath.
- **Deploy (workflows):** logs do GitHub Actions + `systemctl is-active` (smoke). Sem
  `audit_log` no banco (não há mutação de estado de domínio). Rollback registrado nos logs do
  job. Nada de segredo nos logs (endpoints são públicos; nenhuma credencial impressa).
- **Fachada gRPC-Web:** já instrumentada (span/traceparent por RPC, auditoria reaproveitada) —
  inalterada por este plano; só muda o bind (`127.0.0.1:<porta>`) por ambiente.

---

## 6. Ambiente de debug local (app → dev remoto) + CORS cross-origin

Decisão: o debug local conecta **direto ao backend dev remoto** (`https://dev.smartcoreassistant.com.br`),
sem rodar a stack Rust local. Implicações e setup:

### 6.1 Disparo (VS Code, compound F5)
- Criar `.vscode/launch.json` com uma config Dart/Flutter e um **compound** que a engloba:
  ```jsonc
  {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "admin (dev remoto)",
        "type": "dart",
        "request": "launch",
        "program": "clients/apps/smart-core-admin/lib/main_dev.dart",
        "cwd": "clients/apps/smart-core-admin",
        "deviceId": "chrome",
        "args": [
          "--dart-define=SMARTCORE_API_ENDPOINT=https://dev.smartcoreassistant.com.br"
        ]
      }
    ],
    "compounds": [
      { "name": "Debug Admin (tudo)", "configurations": ["admin (dev remoto)"] }
    ]
  }
  ```
  - **Sem `--base-href`** no debug: roda na raiz (`/`); `usePathUrlStrategy()` funciona em `/`.
  - **Sem `--wasm`** no debug (JS, com hot-restart); o transporte gRPC-Web do `grpc 4.x` roda
    igual em JS. O `--wasm` é só para os builds de deploy.
  - `run-admin.ps1` já aceita `-Endpoint` → `.\run-admin.ps1 -Endpoint "https://dev.smartcoreassistant.com.br"`
    é o equivalente por linha de comando (documentar; opcionalmente adicionar um atalho/flag).
- **Reconciliação (backend remoto × "compound tudo junto"):** como não há Rust local a subir, o
  compound contém só a app. Fica extensível: se um dia o debug for contra Rust local, adicionam-se
  configs/tasks de backend ao mesmo compound.

### 6.2 CORS cross-origin (o ponto crítico)
- O dev server do Flutter serve em `http://localhost:<porta>`; as chamadas gRPC-Web vão para
  `https://dev.smartcoreassistant.com.br/smartcore.contracts.queries.AuthService/*` → **cross-origin**.
- gRPC-Web usa headers custom (`x-grpc-web`, `content-type: application/grpc-web+proto`) → o
  browser dispara **preflight `OPTIONS`** antes do POST.
- **O preflight NÃO casa por content-type** (OPTIONS não tem `application/grpc-web`). Por isso o
  Caddy roteia por **path** (`@grpcapi path /smartcore.contracts.*`) — pega OPTIONS + POST (§2.2).
- A fachada (`grpc_web.rs`) já tem `CorsLayer` com `allow_origin(mirror_request())` +
  `allow_methods(Any)` + headers (`authorization`, `x-grpc-web`, `content-type`, ...) e expõe
  `grpc-status`/`grpc-message`. O `tower_http::CorsLayer` responde o preflight automaticamente.
  → **Nenhuma mudança no Rust** além do que já existe; só garantir que o preflight chega à
  fachada (via matcher por path no Caddy).
- HTTPS-from-HTTP: a página local (http) chamando a API https é permitida (mixed-content só
  bloqueia http-a-partir-de-https). OK.

### 6.3 Dependência
- O ambiente **dev precisa estar deployado e no ar** (pipeline `deploy-dev` + Caddy + DNS dev),
  pois o debug local depende dele como backend. Sem dev no ar, o login local falha.

### 6.4 Fluxo das 3 execuções (consolidado)
| Contexto | Comando/disparo | base-href | Endpoint (`--dart-define`) | Backend |
|---|---|---|---|---|
| **Debug local** | VS Code F5 (compound) / `run-admin.ps1` | `/` | `https://dev.smartcoreassistant.com.br` | dev remoto (porta 50061 via Caddy) |
| **Deploy dev** | push em `dev` | `/v2/admin/` | `https://dev.smartcoreassistant.com.br` | dev (same-origin) |
| **Deploy prod** | tag `v*` | `/v2/admin/` | `https://smartcoreassistant.com.br` | prod (same-origin) |

---

## 5. Notas gerais / riscos
1. **Disco do KVM2 (8GB):** Flutter SDK (~1.5GB) + caches no servidor. Mitigar com
   `flutter precache --web` (só web) e limpeza periódica de `~/.pub-cache`/`build/`.
2. **Domínios api./dev-api. legados** (8080/8090 h2c no `server-setup.sh`): confirmar se ainda
   roteiam algo antes de mexer; este plano **adiciona** apex/dev, não remove.
3. **Porta da fachada por ambiente:** sem `RUNTIME_API_GRPC_WEB_ADDR` distinto, dev e prod
   colidem (default `0.0.0.0:50051`). Setar no `.env` de cada ambiente, bind `127.0.0.1`.
4. **DNS:** apex `smartcoreassistant.com.br` + `dev.smartcoreassistant.com.br` → IP do servidor
   (Caddy emite TLS automático ao subir).
