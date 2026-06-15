# Plano Completo — Deploy do admin Flutter Web no CI/CD sob `/v2/admin` (dev + prod)

> Feature: `deploy-admin-web`
> Origem: conversa (jun/2026), plano aprovado em plan mode → reestruturado em FASES PREVC.
> Doc auxiliar: `smart-agent-config/.context/plans/deploy-admin-web/info_aux_deploy-admin-web.md`
> Escala recomendada: **MEDIUM** (justificativa abaixo).

---

## 0. Sumário executivo

O `smart-core-admin` (Flutter Web/WASM) já existe e fala com a fachada gRPC-Web da `runtime_api` (concluída no ciclo `login-module`). Falta **colocá-lo no pipeline**: o CI tem um job Flutter quebrado (`detect` aponta para `clients/flutter_windows`, inexistente), os deploys só publicam binários Rust, e o `Caddyfile` versionado é um template de 1 domínio com SPA fallback fora do `handle`. Este plano inclui **build + publicação do bundle web** servindo o admin em **`/v2/admin`** no **mesmo domínio** do gRPC-Web de cada ambiente (same-origin), em **dev e prod**.

### Por que MEDIUM (e não LARGE)

- Quase **nenhum código de aplicação** (uma linha `usePathUrlStrategy()`); o grosso é infra/CI declarativa (YAML, Caddyfile, shell).
- Reaproveita 100% do padrão existente de deploy/rollback (symlink prod, `bin.bak` dev, self-hosted runner, sudoers `gh-runner`). Não introduz ferramentas novas.
- Superfície de risco contida (borda Caddy + estáticos), sem mudança de contrato/schema/banco.
- Validação manual ponta-a-ponta é necessária (2 ambientes, DNS, TLS), o que tira de SMALL, mas não exige fan-out de subagentes nem múltiplas frentes paralelas → MEDIUM.

### Arquitetura-alvo

```
Browser ──HTTPS──> Caddy (apex / dev.)
   ├─ @grpcweb (Content-Type: application/grpc-web*) ──> reverse_proxy 127.0.0.1:<porta facade>
   └─ handle_path /v2/admin/*  ──> root + try_files {path} /index.html + file_server
                                   (/srv/smart-core-admin/<env>/web)
```
- Fachada gRPC-Web por ambiente (`RUNTIME_API_GRPC_WEB_ADDR`, bind localhost): **prod `127.0.0.1:50051`**, **dev `127.0.0.1:50061`**.
- Web root por ambiente: **`/srv/smart-core-admin/{prod,dev}/web`**.
- Bundle compilado com `--base-href /v2/admin/` + endpoint same-origin via `--dart-define`.

---

## FASE P — Planning (CONCLUÍDA)

Definido em plan mode e consolidado no `info_aux`. Decisões travadas (NÃO reabrir):

- Domínios: prod `smartcoreassistant.com.br/v2/admin`, dev `dev.smartcoreassistant.com.br/v2/admin`. gRPC-Web same-origin.
- Build do web no runner self-hosted (instalar Flutter SDK p/ `gh-runner`).
- Endpoint via build-time `--dart-define` por ambiente.
- Portas fachada: prod `127.0.0.1:50051`, dev `127.0.0.1:50061` (env `RUNTIME_API_GRPC_WEB_ADDR`).
- Web roots: `/srv/smart-core-admin/{prod,dev}/web`. base-href `/v2/admin/`. path URL strategy.

### Observabilidade & Auditoria (Fase P)

Eixo declarado já na concepção: este é plano de **infra/CI** — **app não emite log/auditoria nova**; observabilidade vem de Caddy access logs + logs do Actions + `systemctl is-active`; fachada gRPC-Web **já instrumentada** (span/traceparent/auditoria reaproveitados de `grpc_web.rs`), inalterada — só muda o bind por ambiente. Nenhum segredo em log.

---

## FASE R — Review (validar approach e arquitetura)

Objetivo: confirmar que o desenho é coerente com o que existe **antes** de tocar arquivos. Itens de revisão (checklist de gate R):

1. **Same-origin sem CORS bloqueante.** A fachada (`grpc_web.rs`) já tem `CorsLayer` com `mirror_request` + `accept_http1(true)`. Como Caddy roteia o gRPC-Web no **mesmo host/porta 443** que serve o WASM, o browser nem dispara preflight cross-origin. Confirmado: o matcher casa por **content-type**, não por path → captura `/smartcore.contracts.queries.AuthService/*` na raiz mesmo com o app sob `/v2/admin/`.
2. **`reverse_proxy` SEM h2c.** gRPC-Web trafega sobre **HTTP/1.1**; a fachada Tonic escuta HTTP/1.1 plano em `127.0.0.1`. Os blocos legados `api.`/`dev-api.` usam `h2c://` (gRPC puro 8080/8090) — caso distinto. NÃO replicar h2c nos novos blocos apex/dev.
3. **Path URL strategy exige SPA rewrite.** `usePathUrlStrategy()` + `--base-href /v2/admin/` só funcionam com `try_files {path} /index.html` **dentro do `handle_path`** (após o strip, `{path}` é relativo ao webroot). Sem isso → 404 em refresh/deep-link.
4. **Porta por ambiente.** Default do código é `0.0.0.0:50051`; sem `RUNTIME_API_GRPC_WEB_ADDR` distinto por ambiente, dev e prod colidem. Bind `127.0.0.1` (Caddy é a única borda; firewall só abre 80/443).
5. **Padrão de deploy reaproveitado.** Dev = backup `.bak` + cópia atômica (`mv`); Prod = release versionada + symlink estável. O web entra **no mesmo job/rollback** dos binários.
6. **`detect` do CI.** O workspace real é `clients/pubspec.yaml` (pub workspace + melos), não `clients/flutter_windows`. Job Flutter usa melos (`analyze`/`test`) como o resto do projeto.
7. **Fonte da verdade do Caddyfile.** Hoje o `server-setup.sh` gera heredoc inline e o `infra/Caddyfile` versionado fica órfão. Passar a **copiar `infra/Caddyfile`** para `/etc/caddy/Caddyfile`.

Saída esperada da R: este checklist confirmado (sem código alterado) e gate de arquitetura aprovado para iniciar E.

### Observabilidade & Auditoria (Fase R)

Fase de revisão documental; não toca código/infra. **Sem evento de auditoria** (intencional). Sem log/trace/instrumentação a declarar.

---

## FASE E — Execution (construir)

> Convenção de gitflow do projeto: branch `feature/deploy-admin-web` a partir de `dev`. Comentários em pt-br; identificadores/código em inglês.

### E1 — App Flutter: `usePathUrlStrategy()` no bootstrap

**Objetivo:** servir o app sob o subpath `/v2/admin/` com URLs limpas (path strategy), combinando com `--base-href` e o SPA fallback do Caddy. Sem isso, as rotas do `go_router` (`/`, `/login`, `/home`) não respeitam o subpath de forma consistente.

**Arquivos tocados:**
- `clients/apps/smart-core-admin/lib/bootstrap.dart` (editar)
- `clients/apps/smart-core-admin/web/index.html` (somente conferir — `<base href="$FLUTTER_BASE_HREF">` já presente na linha 4; **nada a mudar**)

**Conteúdo concreto** — adicionar o import e a chamada no início de `bootstrap()`, antes de `runApp`:

```dart
import 'package:flutter_web_plugins/url_strategy.dart';
// ... demais imports existentes ...

Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Path URL strategy: URLs limpas sob /v2/admin/ (sem '#'); combina com
  // --base-href /v2/admin/ e o SPA fallback (try_files) do Caddy. Sem isso,
  // refresh/deep-link em /v2/admin/login retornaria 404.
  usePathUrlStrategy();

  final modules = <AppModule>[
    InfraModule(config),
    LoginModule(),
    InitialLoadingModule(),
  ];
  installModules(modules);
  GetIt.instance.registerSingleton<List<AppModule>>(modules);
  runApp(SmartCoreAdminApp(modules: modules));
}
```

Notas:
- `flutter_web_plugins` é parte do SDK — **sem nova dependência** no `pubspec.yaml`.
- `main_dev.dart`/`main_prod.dart` **não mudam**: o endpoint continua vindo de `String.fromEnvironment('SMARTCORE_API_ENDPOINT')`, agora injetado por `--dart-define`. `_normalizarEndpoint` (em `grpc_api_client.dart`) já preserva `https://`.

**Critério de pronto:** `melos run analyze` limpo; `flutter build web --wasm --base-href /v2/admin/ -t lib/main_dev.dart` compila; `<base href>` confirmado no `index.html`.

#### Observabilidade & Auditoria (E1)
- **Logs/traces:** a linha `usePathUrlStrategy()` **não emite log nem trace**. O client continua logando só endpoint/status (sem token/PII), como estabelecido no `login-module`.
- **Auditoria:** **sem evento de auditoria** (intencional — não há mutação de estado de domínio nesta mudança de roteamento de URL).
- **Segredos:** nenhum. Endpoint é público (origem same-origin).

---

### E2 — `infra/Caddyfile`: 2 site blocks (apex + dev), same-origin, subpath

**Objetivo:** substituir o template de 1 domínio (com `try_files`/`file_server` fora do `handle`, errado para subpath) por 2 site blocks reais, cada um com matcher gRPC-Web **dentro do block**, `handle_path /v2/admin/*` (com `root`+`try_files`+`file_server`) e CSP/HSTS no subpath.

**Arquivos tocados:**
- `infra/Caddyfile` (reescrever)

**Conteúdo concreto** (substitui todo o arquivo):

```caddyfile
# Caddyfile — borda pública do smart-core-admin (Flutter Web/WASM) + fachada gRPC-Web.
# Fonte da verdade versionada; o server-setup.sh COPIA este arquivo para /etc/caddy/Caddyfile.
#
# Topologia por ambiente:
#   apex smartcoreassistant.com.br      → web /srv/smart-core-admin/prod/web ; gRPC-Web 127.0.0.1:50051
#   dev. dev.smartcoreassistant.com.br  → web /srv/smart-core-admin/dev/web  ; gRPC-Web 127.0.0.1:50061
# Caddy emite TLS automático (Let's Encrypt) e faz HTTP→HTTPS.

# ===================== PRODUÇÃO (apex) =====================
smartcoreassistant.com.br {
	encode gzip zstd

	# gRPC-Web same-origin (HTTP/1.1). Matcher por content-type DENTRO do block;
	# casa em QUALQUER path (a API sai na raiz: /smartcore.contracts.queries.AuthService/*).
	# SEM h2c: a fachada Tonic escuta HTTP/1.1 plano em 127.0.0.1.
	@grpcweb header Content-Type application/grpc-web*
	handle @grpcweb {
		reverse_proxy 127.0.0.1:50051
	}

	# Bundle Flutter sob /v2/admin/* (handle_path remove o prefixo antes do try_files).
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

	log {
		output file /var/log/caddy/admin-prod.log {
			roll_size 10mb
			roll_keep 5
		}
	}
}

# ===================== DESENVOLVIMENTO (dev.) =====================
dev.smartcoreassistant.com.br {
	encode gzip zstd

	@grpcweb header Content-Type application/grpc-web*
	handle @grpcweb {
		reverse_proxy 127.0.0.1:50061
	}

	handle_path /v2/admin/* {
		root * /srv/smart-core-admin/dev/web
		header {
			Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
			Strict-Transport-Security "max-age=31536000; includeSubDomains"
			X-Content-Type-Options "nosniff"
			X-Frame-Options "DENY"
			Referrer-Policy "strict-origin-when-cross-origin"
			-Server
		}
		try_files {path} /index.html
		file_server
	}

	log {
		output file /var/log/caddy/admin-dev.log {
			roll_size 10mb
			roll_keep 5
		}
	}
}
```

Notas:
- Os blocos legados `api.`/`dev-api.` (h2c 8080/8090) e `grafana.` **não são removidos por este plano** — este plano só **adiciona** apex/dev. Se forem mantidos no servidor, manter como blocos separados (não conflitam: domínios distintos). Confirmar uso antes de mexer (ver "Notas/riscos").
- `connect-src 'self'` é suficiente (same-origin); o gRPC-Web vai para o próprio host.

**Critério de pronto:** `caddy validate --config infra/Caddyfile` passa; revisão confirma matcher dentro do block, `handle_path` com strip, `reverse_proxy` sem h2c, CSP/HSTS no subpath.

#### Observabilidade & Auditoria (E2)
- **Logs:** **Caddy access logs** por site (`/var/log/caddy/admin-{prod,dev}.log`, roll 10mb×5). Cobre requisições do web e do gRPC-Web na borda.
- **Auditoria:** **sem evento de auditoria** no Caddy (a auditoria de auth é server-side, na fachada, inalterada). CSP/HSTS reforçados no subpath são controle de segurança, não evento.
- **Segredos:** nenhum no Caddyfile (sem tokens/senhas; `-Server` remove o header de versão).

---

### E3 — `infra/server-setup.sh`: Flutter SDK + web roots + copiar Caddyfile + DNS

**Objetivo:** provisionar o runner para buildar web (Flutter SDK no `gh-runner`), criar os web roots com perms corretas (escrita `gh-runner`, leitura `caddy`), passar a copiar o `infra/Caddyfile` versionado, e atualizar a nota de DNS (apex + dev).

**Arquivos tocados:**
- `infra/server-setup.sh` (editar fases 3, 4, 8 e o resumo de próximos passos)

**Conteúdo concreto:**

**(a) Fase 3 — Flutter SDK para o `gh-runner`** (adicionar após o bloco do flatc, ainda na seção `[3/8]`):

```bash
# Flutter SDK para o usuário gh-runner (build do smart-core-admin no CI/CD).
# Clone one-shot no canal stable (compatível com sdk ^3.12.2); ~1.5GB no disco.
echo "Instalando Flutter SDK para o gh-runner..."
GHR_HOME="/home/gh-runner"
if [ ! -d "$GHR_HOME/flutter" ]; then
    sudo -u gh-runner git clone https://github.com/flutter/flutter.git \
        -b stable --depth 1 "$GHR_HOME/flutter"
fi
# PATH persistente do gh-runner + safe.directory (evita "dubious ownership").
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$GHR_HOME/.bashrc"
sudo -u gh-runner git config --global --add safe.directory "$GHR_HOME/flutter"
# Baixa só os artefatos web (poupa disco) e valida.
sudo -u gh-runner bash -lc 'flutter precache --web && flutter --version'
```

**(b) Fase 4 — web roots** (adicionar após o `mkdir -p` da estrutura existente):

```bash
# Web roots do smart-core-admin: escrita pelo gh-runner (deploy), leitura pelo caddy.
mkdir -p \
    "$SMARTCORE_DIR/prod/releases" \
    /srv/smart-core-admin/prod \
    /srv/smart-core-admin/dev
# gh-runner é dono (publica o bundle); world-readable (755) para o caddy ler.
chown -R gh-runner:gh-runner /srv/smart-core-admin
chmod -R 755 /srv/smart-core-admin
```

> Nota: o symlink estável `/srv/smart-core-admin/prod/web` e o dir `dev/web` são criados pelo deploy (E6/E7). O setup garante apenas a árvore base e as permissões.

**(c) Fase 8 — copiar o Caddyfile versionado** (substituir o heredoc inline). O `server-setup.sh` roda a partir da raiz do repo clonado:

```bash
# ── 8. Caddy — instala o Caddyfile versionado (fonte da verdade) ──────────────
echo ""
echo "[8/8] Instalando Caddyfile versionado (infra/Caddyfile)..."
install -m 644 infra/Caddyfile /etc/caddy/Caddyfile
echo "Caddyfile copiado de infra/Caddyfile → /etc/caddy/Caddyfile"
echo "IMPORTANTE: valide os domínios e rode 'caddy validate' antes de iniciar."
systemctl enable caddy
# Não inicia o Caddy agora — DNS precisa estar apontado antes (TLS automático).
```

**(d) Resumo / DNS** — atualizar o passo 5 do bloco de "PRÓXIMOS PASSOS":

```bash
echo "  5. Apontar DNS para este IP ($(hostname -I | awk '{print $1}')):"
echo "     smartcoreassistant.com.br       (apex — admin prod + gRPC-Web prod)"
echo "     dev.smartcoreassistant.com.br   (admin dev + gRPC-Web dev)"
echo "     # (blocos legados api./dev-api./grafana. — manter DNS só se ainda em uso)"
```

**Critério de pronto:** `bash -n infra/server-setup.sh` (sintaxe) ok; revisão confirma clone Flutter sob `gh-runner`, `$HOME/flutter/bin` no `.bashrc`, `safe.directory`, `precache --web`, `/srv/smart-core-admin/{prod,dev}` 755 owned by `gh-runner`, `install` do Caddyfile, nota DNS apex+dev.

#### Observabilidade & Auditoria (E3)
- **Logs:** script de provisionamento imprime progresso no stdout (execução manual como root). `flutter --version` e checagens registradas no terminal do operador.
- **Auditoria:** **sem evento de auditoria** (provisionamento de host, não fluxo de domínio).
- **Segredos:** nenhum no script (sem credenciais; `.env` é preenchido manualmente em passo posterior, fora do git).

---

### E4 — `.env` por ambiente: `RUNTIME_API_GRPC_WEB_ADDR`

**Objetivo:** templatizar/documentar a porta da fachada por ambiente (bind localhost), evitando colisão dev↔prod (default do código é `0.0.0.0:50051`). Os services systemd já fazem `EnvironmentFile=/opt/smartcore/{prod,dev}/.env` — basta a variável estar lá.

**Arquivos tocados:**
- `infra/.env.deploy.example` (adicionar bloco documentando a variável por ambiente)
- (operacional, fora do git) `/opt/smartcore/prod/.env` e `/opt/smartcore/dev/.env` no servidor

**Conteúdo concreto** — anexar ao `infra/.env.deploy.example`:

```bash
# ============================================
# Fachada gRPC-Web da runtime_api (bind localhost — Caddy é a borda)
# Define por AMBIENTE no .env de cada deploy (/opt/smartcore/{prod,dev}/.env).
# Sem isto, dev e prod colidem no default 0.0.0.0:50051.
#   PROD: RUNTIME_API_GRPC_WEB_ADDR=127.0.0.1:50051
#   DEV : RUNTIME_API_GRPC_WEB_ADDR=127.0.0.1:50061
# ============================================
RUNTIME_API_GRPC_WEB_ADDR=127.0.0.1:50051
```

No servidor:
- `/opt/smartcore/prod/.env` → `RUNTIME_API_GRPC_WEB_ADDR=127.0.0.1:50051`
- `/opt/smartcore/dev/.env` → `RUNTIME_API_GRPC_WEB_ADDR=127.0.0.1:50061`

**Critério de pronto:** `.env.deploy.example` documenta a variável e as duas portas; ambos os `.env` no servidor setados; `systemctl restart smartcore-{prod,dev}-runtime_api` faz a fachada logar `Subindo fachada gRPC-Web` no addr correto (verificável no journal).

#### Observabilidade & Auditoria (E4)
- **Logs:** a fachada (`grpc_web.rs`) já loga `tracing::info!(%addr, "Subindo fachada gRPC-Web da runtime_api")` no boot — confirma o bind por ambiente sem novo código.
- **Auditoria:** **sem evento novo**; auditoria de auth da fachada permanece inalterada (só muda o addr de bind).
- **Segredos:** `RUNTIME_API_GRPC_WEB_ADDR` é endpoint, não segredo. O `.env` no servidor contém segredos (PG/Redis/JWT) já existentes — nada novo é logado.

---

### E5 — `ci.yml`: corrigir detect + job Flutter via melos

**Objetivo:** consertar a detecção (apontar para o pub workspace real) e rodar `analyze`/`test` do Flutter via melos, com smoke opcional de build web `--wasm`.

**Arquivos tocados:**
- `.github/workflows/ci.yml` (editar jobs `detect` e `flutter`)

**Conteúdo concreto** — substituir o `run` do job `detect`:

```yaml
      - id: check
        run: |
          if [ -f clients/pubspec.yaml ]; then
            echo "flutter=true" >> "$GITHUB_OUTPUT"
          else
            echo "flutter=false" >> "$GITHUB_OUTPUT"
          fi
```

Substituir o job `flutter` inteiro:

```yaml
  flutter:
    name: Flutter — análise e testes
    runs-on: ubuntu-latest
    needs: detect
    if: needs.detect.outputs.flutter == 'true'
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable
          cache: true

      # Pub workspace (Dart >= 3.6): resolve todos os membros a partir da raiz clients/.
      - name: dart pub get (workspace)
        working-directory: clients
        run: dart pub get

      - name: melos analyze
        working-directory: clients
        run: |
          dart pub global activate melos
          melos run analyze

      - name: melos test
        working-directory: clients
        run: melos run test

      # Smoke de build web/WASM: pega quebras de compilação cedo (ex.: flutter_secure_storage).
      - name: Smoke build web (--wasm)
        working-directory: clients/apps/smart-core-admin
        run: flutter build web --wasm --base-href /v2/admin/ -t lib/main_dev.dart --dart-define=SMARTCORE_API_ENDPOINT=https://dev.smartcoreassistant.com.br
```

Notas:
- O smoke usa `main_dev.dart` + endpoint dev só para compilar (não publica). É o catch do problema visto com `flutter_secure_storage` v9.
- `melos` e os scripts `analyze`/`test` já existem em `clients/pubspec.yaml`.

**Critério de pronto:** push numa branch → job `flutter` roda `detect=true`, `melos run analyze`/`test` e o smoke `--wasm` verdes; job `rust` inalterado e verde.

#### Observabilidade & Auditoria (E5)
- **Logs:** logs do GitHub Actions (analyze/test/build). Sem novo log de aplicação.
- **Auditoria:** **sem evento de auditoria** (pipeline de CI, não fluxo de domínio).
- **Segredos:** nenhum impresso; o `--dart-define` do smoke usa um endpoint público.

---

### E6 — `deploy-dev.yml`: build + publicação atômica do web (dev)

**Objetivo:** após o deploy dos binários Rust (mesmo job self-hosted), buildar o bundle dev e publicá-lo atômico em `/srv/smart-core-admin/dev/web`, com backup `web.bak` e inclusão no rollback.

**Arquivos tocados:**
- `.github/workflows/deploy-dev.yml` (inserir steps de build/publish; estender o rollback)

**Conteúdo concreto** — inserir **após** o step "Reinicia serviços DEV" e **antes** do "Smoke test DEV":

```yaml
      - name: Garante Flutter no PATH
        run: echo "$HOME/flutter/bin" >> $GITHUB_PATH

      - name: Build web admin (DEV, --wasm)
        working-directory: clients
        run: |
          dart pub get
          cd apps/smart-core-admin
          flutter build web --wasm \
            --base-href /v2/admin/ \
            -t lib/main_dev.dart \
            --dart-define=SMARTCORE_API_ENDPOINT=https://dev.smartcoreassistant.com.br

      - name: Publica bundle web DEV (atômico, com backup)
        run: |
          WEB_DIR="/srv/smart-core-admin/dev/web"
          SRC="clients/apps/smart-core-admin/build/web"
          STAGE="/srv/smart-core-admin/dev/web.staging"
          # Backup do bundle atual para rollback.
          rm -rf /srv/smart-core-admin/dev/web.bak
          cp -r "$WEB_DIR" /srv/smart-core-admin/dev/web.bak 2>/dev/null || true
          # Cópia para staging + troca atômica (rm do antigo + mv do novo).
          rm -rf "$STAGE"
          cp -r "$SRC" "$STAGE"
          chmod -R 755 "$STAGE"
          rm -rf "$WEB_DIR"
          mv "$STAGE" "$WEB_DIR"
          echo "✓ bundle web DEV publicado em $WEB_DIR (arquivos estáticos: Caddy não precisa reload)"
```

Estender o step "Rollback em falha" (adicionar ao final do `run` existente, dentro do `if: failure()`):

```bash
          # Rollback do bundle web DEV junto com os binários.
          if [ -d "/srv/smart-core-admin/dev/web.bak" ]; then
            rm -rf "/srv/smart-core-admin/dev/web"
            mv "/srv/smart-core-admin/dev/web.bak" "/srv/smart-core-admin/dev/web"
            echo "Bundle web DEV revertido para o backup."
          fi
```

Notas:
- Estáticos não exigem `systemctl reload caddy` (só troca de arquivos).
- O backup só é consumido no rollback; em sucesso fica como `.bak` (sobrescrito no próximo deploy), igual ao padrão `bin.bak`.

**Critério de pronto:** push em `dev` → workflow builda Rust + web, publica em `/srv/smart-core-admin/dev/web`; smoke verde; ao forçar falha, web volta do `.bak`.

#### Observabilidade & Auditoria (E6)
- **Logs:** logs do Actions (build/publish/rollback) + smoke `systemctl is-active` (já existente). Caddy access logs cobrem o tráfego pós-deploy.
- **Auditoria:** **sem `audit_log` no banco** (não há mutação de estado de domínio). Rollback registrado nos logs do job.
- **Segredos:** nenhum impresso; endpoint do `--dart-define` é público; sem credenciais nos logs.

---

### E7 — `deploy-prod.yml`: build + publicação versionada do web (prod)

**Objetivo:** buildar o bundle prod e publicá-lo versionado em `releases/$TAG/web`, com symlink estável `/srv/smart-core-admin/prod/web` (rollback por symlink + limpeza), no mesmo padrão dos binários.

**Arquivos tocados:**
- `.github/workflows/deploy-prod.yml` (inserir steps no job `build-and-deploy`; estender rollback e limpeza)
- (opcional) o job `flutter-windows` — **fora do escopo deste plano** (não tocar; só web). Mantido como está.

**Conteúdo concreto** — inserir **após** "Atualiza symlink current" e **antes** de "Reinicia serviços PROD":

```yaml
      - name: Garante Flutter no PATH
        run: echo "$HOME/flutter/bin" >> $GITHUB_PATH

      - name: Build web admin (PROD, --wasm)
        working-directory: clients
        run: |
          dart pub get
          cd apps/smart-core-admin
          flutter build web --wasm \
            --base-href /v2/admin/ \
            -t lib/main_prod.dart \
            --dart-define=SMARTCORE_API_ENDPOINT=https://smartcoreassistant.com.br

      - name: Publica bundle web PROD (versionado + symlink)
        env:
          TAG: ${{ steps.version.outputs.TAG }}
        run: |
          BASE="/srv/smart-core-admin/prod"
          REL_WEB="$BASE/releases/$TAG/web"
          SRC="clients/apps/smart-core-admin/build/web"
          mkdir -p "$BASE/releases/$TAG"
          rm -rf "$REL_WEB"
          cp -r "$SRC" "$REL_WEB"
          chmod -R 755 "$REL_WEB"
          # Registra o alvo anterior do symlink web para rollback.
          PREV_WEB=$(readlink "$BASE/web" 2>/dev/null || true)
          echo "PREV_WEB=$PREV_WEB" >> "$GITHUB_ENV"
          # Symlink estável que o Caddy serve (root /srv/smart-core-admin/prod/web).
          ln -sfn "$REL_WEB" "$BASE/web"
          echo "✓ web PROD → releases/$TAG/web (anterior: $PREV_WEB)"
```

Estender o step "Rollback em falha" (adicionar dentro do `if: failure()`):

```bash
          # Rollback do symlink web PROD para a release anterior.
          BASE="/srv/smart-core-admin/prod"
          if [ -n "${PREV_WEB:-}" ] && [ -d "${PREV_WEB:-/nonexistent}" ]; then
            ln -sfn "$PREV_WEB" "$BASE/web"
            echo "Symlink web PROD revertido para $PREV_WEB."
          fi
          # A release com falha já é removida adiante (rm releases/$TAG inclui o web).
          rm -rf "$BASE/releases/$TAG" || true
```

Estender o step "Remove releases antigas (mantém últimas 5)" — o `rm -rf` de `releases/v*` já remove o `web/` aninhado de cada release antiga; **nenhuma mudança extra necessária** (registrar no comentário que o web está aninhado por TAG).

**Critério de pronto:** tag `v*` → workflow builda Rust + web, publica `releases/$TAG/web`, aponta o symlink `/srv/smart-core-admin/prod/web`; smoke verde; ao forçar falha, symlink web volta ao `PREV_WEB`; limpeza mantém últimas 5 releases (web incluído).

#### Observabilidade & Auditoria (E7)
- **Logs:** logs do Actions (build/publish/symlink/rollback/limpeza) + smoke `systemctl is-active`. Caddy access logs no apex.
- **Auditoria:** **sem `audit_log`** (deploy de estáticos versionados, não mutação de domínio). Rollback por symlink registrado nos logs.
- **Segredos:** nenhum impresso; `--dart-define` usa origem pública; `pg_dump` (step existente) não vaza credenciais nos logs.

---

### E8 — Documentação

**Objetivo:** registrar topologia, portas por ambiente e o fluxo de deploy do bundle nas docs canônicas do projeto.

**Arquivos tocados:**
- `smart-agent-config/doc_dev/planejamento/10-plano-cicd-devops.md` (nova seção: "Deploy do admin Flutter Web sob /v2/admin")
- `smart-agent-config/doc_dev/planejamento/09-comunicacao-e-autenticacao.md` (nota: rota `/v2/admin` same-origin com a fachada gRPC-Web)

**Conteúdo concreto (resumo a inserir):**
- Em `10-plano-cicd-devops.md`: diagrama da arquitetura-alvo; tabela de portas (prod 50051 / dev 50061, bind 127.0.0.1); web roots; passos do build (`flutter build web --wasm --base-href /v2/admin/ -t lib/main_<flavor>.dart --dart-define=SMARTCORE_API_ENDPOINT=<origem>`); padrão de publicação (dev: `web.bak`; prod: `releases/$TAG/web` + symlink); que o `server-setup.sh` instala Flutter SDK no `gh-runner` e copia o `infra/Caddyfile`.
- Em `09-comunicacao-e-autenticacao.md`: a fachada gRPC-Web é servida **same-origin** com o admin sob `/v2/admin`; o navegador resolve rotas do go_router relativas ao `<base href="/v2/admin/">`; gRPC-Web casa por content-type na raiz (sem CORS preflight bloqueante).

**Critério de pronto:** ambas as docs atualizadas e coerentes com os arquivos de E1–E7; sem referência a `flutter_windows`/`admin.smartcore.example` como topologia atual do web.

#### Observabilidade & Auditoria (E8)
- **Logs/auditoria:** documentação — **sem evento**. Registra explicitamente nas docs a política dos 3 eixos deste plano (app sem evento novo; Caddy access logs; deploy via Actions + systemctl; fachada inalterada).

---

## FASE V — Validation (verificar que funciona)

Objetivo: provar ponta-a-ponta nos 2 ambientes.

1. **CI verde.** Abrir PR/push → job `rust` e job `flutter` (analyze/test + smoke `--wasm`) passam; `detect` resolve `flutter=true` via `clients/pubspec.yaml`.
2. **Dev acessível.** Push em `dev` → deploy builda Rust + web dev e publica em `/srv/smart-core-admin/dev/web`. Acessar `https://dev.smartcoreassistant.com.br/v2/admin` → tela de login carrega (WASM); **login real ponta-a-ponta contra a fachada dev (porta 50061)** funciona; deep-link `…/v2/admin/login` resolve (path strategy + try_files).
3. **Prod acessível.** Tag `v*` → release publica `releases/$TAG/web` + symlink. Acessar `https://smartcoreassistant.com.br/v2/admin` → login ponta-a-ponta **na porta 50051**.
4. **Same-origin sem CORS.** No DevTools (Network), requisições gRPC-Web saem para o **próprio domínio** (`/smartcore.contracts.queries.AuthService/*`), **sem preflight OPTIONS bloqueante**.
5. **Rollback.** Forçar falha no smoke → dev volta do `web.bak`; prod volta o symlink para `PREV_WEB`. Confirmar que o app anterior continua servido.
6. **Segurança.** Resposta de `/v2/admin/` traz **CSP** (`wasm-unsafe-eval`) + **HSTS** + `nosniff`/`DENY` (checar headers no DevTools/`curl -I`). **Fachada gRPC-Web não exposta direto:** `curl http://<IP>:50051` de fora **recusa/timeout** (bind 127.0.0.1; firewall só 80/443). Acesso só via Caddy.
7. **TLS.** Certificados Let's Encrypt emitidos automaticamente para apex e dev ao subir o Caddy (DNS apontado).

**Critério de saída da V:** itens 1–7 verificados; evidências (prints/headers/logs) anexadas ao PR.

### Observabilidade & Auditoria (Fase V)
- **Logs:** validação consome Caddy access logs (`/var/log/caddy/admin-*.log`), journal da fachada (`journalctl -u smartcore-{prod,dev}-runtime_api`) e logs do Actions.
- **Auditoria:** confirmar (server-side, inalterado) que `login_success`/`login_rate_limited`/`logout` são emitidos pela fachada com `traceparent` e IP (via `x-forwarded-for` do Caddy) — **comportamento pré-existente**, só validado aqui.
- **Segredos:** conferir que nenhum log (Caddy/Actions/journal) contém token/senha; endpoints públicos ok.

---

## FASE C — Confirmation (entregar e documentar)

1. **Gate obrigatório `prevc-final-review`** (subagente Opus): compara o implementado contra este plano, corrige desvios sem bloquear, resume correções.
2. **Docs finalizadas** (E8) e coerentes; este plano consolidado.
3. **PR** `feature/deploy-admin-web` → `dev` mergeado após V verde; tag `v*` para exercitar prod quando aprovado.
4. **Arquivamento:** mover o canônico + `info_aux` + este `plano_completo` para `archive/` em `.context/plans/` (convenção `plan-restructuring`).
5. **Commits:** gitflow + conventional commits; **sem auto-referência** (nada de Co-Authored-By/Generated by). Comentários pt-br.

### Observabilidade & Auditoria (Fase C)
- **Logs/auditoria:** entrega/arquivamento — **sem evento**. O relatório de final-review registra que os 3 eixos foram declarados por fase e que a fachada permaneceu inalterada (só bind por ambiente).

---

## Correções aplicadas (vs. plano base) — com fonte no info_aux

1. **`reverse_proxy` SEM `h2c`** nos blocos apex/dev. O plano base citava só "reverse_proxy"; reforçado que **gRPC-Web é HTTP/1.1** e a fachada Tonic escuta HTTP/1.1 plano — `h2c` seria errado (é para gRPC puro, caso dos blocos legados 8080/8090). Fonte: info_aux §2.1.
2. **Matcher `@grpcweb` e `reverse_proxy` DENTRO de `handle`**, no escopo do site block. O `Caddyfile` atual usa `reverse_proxy @grpcweb {upstream}` no escopo do site e `try_files`/`file_server` **fora** de `handle` (errado para subpath). Corrigido para `@grpcweb` + `handle @grpcweb { reverse_proxy ... }` e o SPA fallback **dentro** do `handle_path`. Fonte: info_aux §2.1–2.3.
3. **`handle_path /v2/admin/*`** (com strip do prefixo) em vez de `root`+`file_server` na raiz. Necessário para servir sob subpath; após o strip, `{path}` é relativo ao webroot. Fonte: info_aux §2.1.
4. **CI `detect` → `clients/pubspec.yaml`** (pub workspace) em vez de `clients/flutter_windows/pubspec.yaml` (inexistente). Job Flutter passa a usar **melos** (`dart pub get` + `melos run analyze`/`test`) com **`subosito/flutter-action@v2`**. Fonte: info_aux §3.2 e §1 (melos).
5. **Flutter SDK no `gh-runner` via clone stable + `$GITHUB_PATH`/`.bashrc` + `safe.directory` + `precache --web`.** Detalhado as pegadinhas (PATH só vale no mesmo `run`; dubious ownership). Fonte: info_aux §3.3.
6. **`server-setup.sh` passa a COPIAR `infra/Caddyfile`** (`install -m 644`) em vez de gerar heredoc inline — fonte da verdade versionada. Plano base já pedia; aqui concretizado o comando e a remoção do heredoc.
7. **Web roots `/srv/smart-core-admin/{prod,dev}` 755 owned by `gh-runner`** (escrita deploy, leitura caddy). Ajustado do `…/build/web` do template antigo para a topologia por ambiente.
8. **`RUNTIME_API_GRPC_WEB_ADDR` por ambiente** documentado em `.env.deploy.example` (prod 50051 / dev 50061, bind 127.0.0.1) — evita colisão no default `0.0.0.0:50051`. Fonte: info_aux §0 e §5.3.
9. **COOP/COEP NÃO habilitados.** Decisão explícita: só seriam necessários para **WASM multithread (skwasm)**; o build atual roda single-thread/JS-fallback sem eles, e COEP pode quebrar recursos cross-origin. Revisitar só se ativar rendering multithread. Fonte: info_aux §2.3.
10. **go_router com rotas puras** (`/login`, `/home`) — o subpath é responsabilidade do `<base href>` + servidor; **não** prefixar rotas com `/v2/admin`. Fonte: info_aux §1 (go_router) e §3.1.

---

## Arquivos tocados (consolidado, caminhos reais)

- App: `clients/apps/smart-core-admin/lib/bootstrap.dart` (editar); `…/web/index.html` (só conferir).
- Caddy: `infra/Caddyfile` (reescrever).
- Provisionamento: `infra/server-setup.sh` (fases 3/4/8 + resumo DNS).
- Env: `infra/.env.deploy.example` (+ `/opt/smartcore/{prod,dev}/.env` no servidor).
- CI/CD: `.github/workflows/ci.yml`, `.github/workflows/deploy-dev.yml`, `.github/workflows/deploy-prod.yml`.
- Docs: `smart-agent-config/doc_dev/planejamento/10-plano-cicd-devops.md`, `…/09-comunicacao-e-autenticacao.md`.

## Reuso (não recriar)

- Fachada gRPC-Web + env `RUNTIME_API_GRPC_WEB_ADDR`: `server/apps/runtime_api/src/grpc_web.rs` (já lê o env; default `0.0.0.0:50051`; `accept_http1(true)` + `CorsLayer`).
- Normalização de endpoint: `clients/packages/api_client/lib/src/grpc_api_client.dart` (`_normalizarEndpoint` preserva `https://`).
- Padrão deploy/rollback (symlink prod, `bin.bak` dev), self-hosted runner, sudoers `gh-runner`: `.github/workflows/deploy-*.yml`, `infra/systemd/`, `infra/server-setup.sh`.
- Scripts melos (`analyze`/`test`): `clients/pubspec.yaml`.
- EnvironmentFile dos services: `infra/systemd/smartcore-{prod,dev}-runtime_api.service` (já `EnvironmentFile=/opt/smartcore/{prod,dev}/.env`).

## Notas / riscos

1. **Disco do KVM2 (8GB):** Flutter SDK (~1.5GB) + caches no servidor. Mitigar com `flutter precache --web` (só web) e limpeza periódica de `~/.pub-cache`/`build/`.
2. **Domínios `api.`/`dev-api.`/`grafana.` legados:** confirmar uso antes de mexer; este plano **adiciona** apex/dev, não remove.
3. **`--depth 1` no clone Flutter** pode faltar tags em erro de versão → `git -C $HOME/flutter fetch --tags`. Atualizar SDK periodicamente no runner persistente (`git -C $HOME/flutter pull`).
4. **DNS + TLS:** apex e dev devem apontar para o IP **antes** de `systemctl start caddy` (emissão Let's Encrypt automática ao subir).
