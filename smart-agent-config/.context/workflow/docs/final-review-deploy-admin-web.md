# Final Review — deploy-admin-web
Data: 2026-06-15 · Diff: dev...HEAD (branch `feature/deploy-admin-web`)

## Rótulo: CORRIGIDO (informativo — não bloqueia o ciclo)

## Resumo das correções
- `infra/server-setup.sh`: corrigida falta de idempotência na inserção do Flutter PATH no `.bashrc` do `gh-runner` (adicionado guard `grep -qF`) e trocado `git config --global --add` por `--replace-all` para `safe.directory` (evita duplicações em re-execuções do script).

## 1. Plano vs. Implementado

| Item do plano | Status | Observação |
|---------------|--------|------------|
| **E1 — `usePathUrlStrategy()` em `bootstrap.dart`** | ✅ | Chamada no lugar correto (após `WidgetsFlutterBinding.ensureInitialized()`, antes de `runApp`). Comentário pt-br adequado. |
| **E1 — `flutter_web_plugins` no pubspec** | ⚠️ feito com desvio | Plano dizia "sem nova dependência no `pubspec.yaml`", mas `flutter_web_plugins` com `sdk: flutter` **foi adicionado**. Isso é a prática correta do Flutter — o plano estava impreciso. Sem correção necessária; o import funciona somente com a declaração no pubspec. |
| **E1 — `web/index.html` inalterado** | ✅ | Não houve modificação no `index.html` (confirmado pelo diff). |
| **E2 — Caddyfile reescrito (2 site blocks)** | ✅ | Apex (`smartcoreassistant.com.br`) e dev (`dev.smartcoreassistant.com.br`). Matcher `@grpcapi path /smartcore.contracts.*` dentro do block. `handle_path /v2/admin/*` com `root`+`try_files`+`file_server`. `reverse_proxy` sem h2c. CSP/HSTS por subpath. Logs com `roll_size`+`roll_keep`. |
| **E2 — HSTS prod vs dev** | ✅ | Prod tem `preload`; dev não (correto — preload em dev pode causar problemas). |
| **E2 — `connect-src 'self'`** | ✅ | Same-origin; suficiente para gRPC-Web. |
| **E3 — Flutter SDK para `gh-runner`** | ✅ | Clone `--depth 1` no canal stable. `precache --web` para economizar disco. |
| **E3 — PATH persistente no `.bashrc`** | ⚠️ → ✅ | **Corrigido nesta revisão:** faltava guard de idempotência (linha 86 duplicava a cada execução do script). Adicionado `grep -qF` antes do `echo`. |
| **E3 — `safe.directory`** | ⚠️ → ✅ | **Corrigido nesta revisão:** `--add` acumulava valores; trocado por `--replace-all`. |
| **E3 — Web roots `/srv/smart-core-admin/{prod,dev}`** | ✅ | Criados com `mkdir -p`, `chown gh-runner:gh-runner`, `chmod 755`. |
| **E3 — Caddyfile copiado via `install`** | ✅ | `install -m 644 infra/Caddyfile /etc/caddy/Caddyfile`. Heredoc inline removido. |
| **E3 — DNS no resumo** | ✅ | Apex + dev. Nota sobre blocos legados. |
| **E4 — `.env.deploy.example`** | ✅ | Bloco documentando `RUNTIME_API_GRPC_WEB_ADDR` por ambiente (prod 50051, dev 50061, bind 127.0.0.1). |
| **E5 — CI `detect` → `clients/pubspec.yaml`** | ✅ | Detecção corrigida para o pub workspace real. |
| **E5 — Job `flutter` via melos** | ✅ | `subosito/flutter-action@v2`, `dart pub get` (workspace), `melos run analyze`, `melos run test`. |
| **E5 — Smoke build web `--wasm`** | ✅ | `flutter build web --wasm --base-href /v2/admin/ -t lib/main_dev.dart --dart-define=...`. |
| **E6 — Build web admin DEV** | ✅ | `flutter build web --wasm` com endpoint dev. `dart pub get` no workspace. |
| **E6 — Publicação atômica DEV** | ✅ | Backup `web.bak`, staging, `rm`+`mv` atômico, `chmod 755`. |
| **E6 — Rollback web DEV** | ✅ | Restauração do `web.bak` integrada ao step de rollback `if: failure()`. |
| **E7 — Build web admin PROD** | ✅ | `flutter build web --wasm` com endpoint prod e `main_prod.dart`. |
| **E7 — Publicação versionada PROD** | ✅ | `releases/$TAG/web`, `mkdir -p`, `cp -r`, `chmod 755`, `ln -sfn`. `PREV_WEB` exportado via `$GITHUB_ENV`. |
| **E7 — Rollback web PROD** | ✅ | Rollback do symlink web para `PREV_WEB` + `rm -rf` da release com falha (web e binários separados). |
| **E7 — Limpeza releases antigas** | ✅ | Step existente (`ls -dt ... | tail -n +6 | xargs rm -rf`) já remove web aninhado por TAG. |
| **E9 — `.vscode/launch.json`** | ✅ | Configuração `dart`/`chrome` com `--dart-define` apontando para dev remoto. Compound "Debug Admin (tudo)". |
| **E9 — `run-admin.ps1` documentação** | ✅ | Linha de exemplo adicionada com endpoint dev remoto. |
| **E8 — Doc `10-plano-cicd-devops.md`** | ✅ | Seção 9.5 com estratégia de build, comandos, publicação/diretórios e roteamento Caddy. |
| **E8 — Doc `09-comunicacao-e-autenticacao.md`** | ✅ | Seções 7.1 (same-origin), 7.2 (roteamento por path), 7.3 (debug local cross-origin CORS). Renumeração de "Próximos Passos" para §8. |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---------------|----------|----------|
| `infra/server-setup.sh:85-87` | Linha `echo 'export PATH=...' >> .bashrc` sem guard de idempotência — duplicava a cada re-execução do script | Adicionado `grep -qF 'flutter/bin' "$GHR_HOME/.bashrc" ||` antes do `echo` |
| `infra/server-setup.sh:87` | `git config --global --add safe.directory` acumulava valores duplicados | Trocado `--add` por `--replace-all` |

## 2b. Observabilidade & Auditoria

| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---------------|-----------|-----------|-------------|------------|
| `usePathUrlStrategy()` (E1) | ✅ | N/A | ✅ | Sem log/trace (intencional — roteamento de URL). Sem segredo. |
| Caddyfile — gRPC-Web + admin (E2) | ✅ | N/A | ✅ | Access logs Caddy por site (`admin-{prod,dev}.log`, roll 10mb×5). `-Server` remove header de versão. Sem segredos. |
| `server-setup.sh` — provisionamento (E3) | ✅ | N/A | ✅ | Progresso no stdout. Sem credenciais no script. |
| `.env.deploy.example` (E4) | ✅ | N/A | ✅ | `RUNTIME_API_GRPC_WEB_ADDR` é endpoint, não segredo. Fachada já loga addr no boot. |
| CI `flutter` job (E5) | ✅ | N/A | ✅ | Logs do Actions. `--dart-define` usa endpoint público. |
| Deploy web DEV (E6) | ✅ | N/A | ✅ | Logs do Actions (build/publish/rollback). Sem credenciais impressas. |
| Deploy web PROD (E7) | ✅ | N/A | ✅ | Logs do Actions. `pg_dump` (step existente) não vaza credenciais. |
| Debug local (E9) | ✅ | N/A | ✅ | Logs no console Flutter/DevTools. Endpoint público. |
| Docs (E8) | ✅ | N/A | ✅ | Registra política de observabilidade nas docs canônicas. |
| Fachada gRPC-Web (inalterada) | ✅ | ✅ | ✅ | `grpc_web.rs` permanece inalterado — span/traceparent, `login_success`/`logout` server-side, `CorsLayer mirror_request`. Só muda bind por ambiente. |

## 3. Decisões Autônomas (revisar depois)
- Nenhuma decisão autônoma de grande impacto. A única correção foi de qualidade/idempotência no script de provisionamento (guard `grep` + `--replace-all`).

## 4. Revalidação
- lint: N/A (este plano é infra/CI declarativo — sem código Rust/Python/Dart novo além de 1 linha)
- type-check: N/A
- clippy (Rust): N/A (nenhum arquivo Rust alterado)
- testes: N/A (diretriz do projeto — testes são responsabilidade do agente dedicado)
- Caddyfile: ✅ (validação manual da sintaxe — `caddy validate` requer o binário Caddy instalado no Linux)
- Shell syntax (`bash -n`): N/A (WSL não disponível no ambiente de desenvolvimento)

## 5. Pendências (escopo extra ou fora do plano)
- **Fase V (Validation):** Os itens V0–V7 do plano (debug local, CI verde, dev/prod acessíveis, same-origin, rollback, segurança, TLS) dependem de infraestrutura no servidor (DNS apontado, Caddy rodando, Flutter SDK instalado). Ficam como validação a realizar **pós-merge no servidor**, fora do escopo desta auditoria de código.
- **`pubspec.yaml` — `flutter_web_plugins: sdk: flutter`:** Adicionado ao pubspec embora o plano dissesse "sem nova dependência". Está correto tecnicamente (necessário para o import funcionar); o plano estava impreciso. Mantido como está.
- **Idempotência de `cargo PATH` em `.bashrc` (linha 145):** Pré-existente (fora do diff deste plano). Merece correção em ciclo futuro mas não é escopo do `deploy-admin-web`.
- **Job `flutter-windows` em `deploy-prod.yml`:** Referencia `clients/flutter_windows` que pode não existir mais. Fora do escopo deste plano (§E7 explicitamente declara "fora do escopo deste plano (não tocar; só web)").
