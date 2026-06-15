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
```caddyfile
smartcoreassistant.com.br {
  encode gzip zstd

  # gRPC-Web same-origin (matcher por content-type; precede o static).
  @grpcweb header Content-Type application/grpc-web*
  handle @grpcweb {
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
  @grpcweb header Content-Type application/grpc-web*
  handle @grpcweb { reverse_proxy 127.0.0.1:50061 }
  handle_path /v2/admin/* {
    root * /srv/smart-core-admin/dev/web
    header { Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'"; Strict-Transport-Security "max-age=31536000; includeSubDomains" }
    try_files {path} /index.html
    file_server
  }
}
```

### 2.3 Pegadinhas
- `connect-src 'self'` é suficiente (same-origin); o gRPC-Web sai para o próprio host em
  `/smartcore.contracts.queries.AuthService/*` (path na raiz, casado pelo `@grpcweb` por
  content-type, não pelo path `/v2/admin`).
- Ordem: o `handle @grpcweb` e o `handle_path /v2/admin/*` são exclusivos; como o gRPC-Web casa
  por content-type em qualquer path, ele captura as chamadas de API mesmo na raiz.
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

## 5. Notas gerais / riscos
1. **Disco do KVM2 (8GB):** Flutter SDK (~1.5GB) + caches no servidor. Mitigar com
   `flutter precache --web` (só web) e limpeza periódica de `~/.pub-cache`/`build/`.
2. **Domínios api./dev-api. legados** (8080/8090 h2c no `server-setup.sh`): confirmar se ainda
   roteiam algo antes de mexer; este plano **adiciona** apex/dev, não remove.
3. **Porta da fachada por ambiente:** sem `RUNTIME_API_GRPC_WEB_ADDR` distinto, dev e prod
   colidem (default `0.0.0.0:50051`). Setar no `.env` de cada ambiente, bind `127.0.0.1`.
4. **DNS:** apex `smartcoreassistant.com.br` + `dev.smartcoreassistant.com.br` → IP do servidor
   (Caddy emite TLS automático ao subir).
