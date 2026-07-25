# N8.2 — Producao web completa: o que foi habilitado

> **ATUALIZACAO (2026-07-23):** confirmado que `infra/caddy/tenant.caddy` e
> `infra/caddy/admin.caddy` sao config legada, provavelmente nao instalada em
> lugar nenhum hoje (ver item 3 abaixo). A habilitacao REAL de `/v2/admin` e
> `/v2/tenant` em producao foi aplicada em `docker/edge/Caddyfile` (o arquivo
> que `deploy-prod.yml`/`deploy-dev.yml` de fato publicam), seguindo a opcao
> (b) recomendada no item 2 abaixo — um unico site block com multiplos
> `handle_path`, sem o conflito de "ambiguous site definition" descrito ali.
> As edicoes em `tenant.caddy`/`admin.caddy` foram mantidas com um aviso de
> obsolescencia no topo do arquivo, so como referencia historica.
>
> Este documento explica as mudancas ORIGINAIS feitas em `infra/caddy/tenant.caddy` e
> `infra/caddy/admin.caddy` para a fase N8.2, os TODOs/placeholders que ainda
> precisam de um valor real humano, e o comando que **voce** deve rodar
> manualmente no servidor. Nenhum comando foi executado por mim contra nenhum
> servidor — so os arquivos de config versionados foram editados.

## O que mudou

Nos dois arquivos, o bloco `# ── PROD (pendente de decisao) ──` (antes so um
esboco comentado) virou um site block ativo para `smartcoreassistant.com.br`:

- `handle_path /v2/tenant/*` (em `tenant.caddy`) e `handle_path /v2/admin/*`
  (em `admin.caddy`) — **antes** do `reverse_proxy 172.18.0.5:8000` (Django) no
  mesmo site block, entao a v2 tem precedencia nessas rotas e o Django
  continua respondendo todo o resto (coexistencia, nao substituicao).
- Cada `handle_path` faz `reverse_proxy` para o CONTAINER do respectivo build
  web (nao serve arquivos estaticos direto do disco). Motivo: nenhum job de
  CI publica o build `--wasm` em `/srv/*/prod/web` — o bundle e empacotado na
  imagem Docker (`smartcore-web` / `smartcore-web-tenant`, via
  `docker/web/Dockerfile`) e roda como container publicado no host
  (`docker/prod/compose.yml`). Portas usadas (ja documentadas no repo, nao
  inventadas):
  - admin: `localhost:8082` (`WEB_HOST_PORT`, default em `docker/prod/.env.example`; dev usa 8081)
  - tenant: `localhost:8084` (`WEB_TENANT_HOST_PORT`, default em `docker/prod/compose.yml`; dev usa 8083)
- gRPC-Web da `runtime_api` de producao roteado por um matcher de
  **Content-Type** (`application/grpc-web*`), nao por um path fixo. O esboco
  anterior chutava um path `/grpc.runtime/*` que nao corresponde a nada real:
  o `runtime_api` usa `tonic_web::GrpcWebLayer` sobre servicos gRPC gerados
  do `.proto` (`server/apps/runtime_api/src/grpc_web.rs`), cujos paths HTTP
  reais sao por servico/metodo — nao um prefixo previsivel. Um `handle`
  catch-all (como o bloco DEV faz) tambem nao serve em prod: ele roubaria
  toda rota nao-`/v2` do dominio, quebrando o Django. Por isso o matcher e
  por header, robusto independente do path exato.

## Placeholders / TODOs pendentes de confirmacao humana

1. **`{$RUNTIME_API_PROD_GRPC_WEB_PORT:-50052}`** (nos dois arquivos): o
   default `50052` e o valor **documentado** em `docker/prod/.env.example`
   (`RUNTIME_WEB_PORT=50052`, para nao colidir com o `50051` do dev) — nao e
   um chute, mas **confirme que bate com o `.env` real do servidor** antes de
   aplicar (o `.env` real nao esta neste repo). Se divergir, defina a env var
   `RUNTIME_API_PROD_GRPC_WEB_PORT` no ambiente do processo Caddy (ou troque
   o default direto no arquivo).

2. **CONFLITO DE SITE ADDRESS (bloqueante) — precisa de decisao antes de
   aplicar**: `tenant.caddy` e `admin.caddy` agora declaram, **cada um**, um
   site block completo para `smartcoreassistant.com.br`. O formato Caddyfile
   nao aceita dois site blocks com o mesmo endereco, mesmo vindo de arquivos
   `import`ados diferentes — isso falha em `caddy validate` com algo como
   "ambiguous site definition". **Este mesmo problema ja existe hoje nos
   blocos DEV** (`dev.smartcoreassistant.com.br` duplicado nos dois arquivos)
   — nunca foi de fato validado contra um Caddy real. Antes de instalar os
   dois arquivos em `/etc/caddy/conf.d/`, escolha uma destas opcoes:
   - **(a)** Mesclar manualmente os dois `handle_path` (admin + tenant) num
     UNICO site block `smartcoreassistant.com.br { ... }`, num so arquivo
     (e o outro arquivo deixa de declarar o proprio site block prod, viraria
     so um snippet importado); ou
   - **(b) — recomendado, ver secao seguinte**: aplicar o equivalente em
     `docker/edge/Caddyfile`, que ja tem exatamente essa estrutura (varios
     `handle_path` dentro de UM site block) funcionando para
     `dev.smartcoreassistant.com.br` hoje.

3. **Achado importante sobre qual Caddy esta realmente rodando em producao**:
   `docker/edge/Caddyfile` se autodescreve como "Container Caddy que ocupa
   80/443 e roteia TUDO (**substitui o Caddy do host**)", e e o arquivo
   efetivamente publicado pelo `.github/workflows/deploy-prod.yml` /
   `deploy-dev.yml` (`docker compose up -d` em `docker/edge/`). Ja
   `infra/server-setup.sh` so abre as portas 80/443 no firewall para essa
   borda containerizada — nao ha mais nenhum passo de instalacao de
   `/etc/caddy/conf.d/*.caddy` num Caddy de host. Ou seja: **e bem provavel
   que `infra/caddy/tenant.caddy` e `admin.caddy` sejam config legada,
   anterior a migracao full-docker, e que hoje nao estejam de fato instalados
   em lugar nenhum.** Editei os dois arquivos exatamente como pedido (eles
   sao a fonte canonica descrita no plano N8.2), mas se a intencao e que
   `/v2/admin` e `/v2/tenant` respondam na producao REAL, o roteamento
   equivalente (handle_path + matcher de Content-Type, mesmas portas 8082/8084,
   ANTES do `reverse_proxy smartcoreassistant_app:8000`) precisa ser aplicado
   em `docker/edge/Caddyfile` — que ja usa exatamente este padrao de UM site
   block com multiplos `handle_path`, sem o conflito do item 2. Isso nao foi
   feito aqui pois estava fora do escopo pedido (as duas edicoes deveriam
   ficar em `tenant.caddy`/`admin.caddy`); avise se quiser que eu faca essa
   mudanca tambem em `docker/edge/Caddyfile`.

4. **CORS de midia do R2 para o tenant em prod** (fora do escopo desta
   edicao, mas necessario para o app funcionar de verdade): `S3_CORS_ALLOWED_ORIGINS`
   com o dominio real e `infra/r2-cors.json` aplicados por `data_storage`
   (passo 3 do N8.2 no plano), incluindo `Content-Range`/`Accept-Ranges` para
   seek de midia HTML5.

## Comando para aplicar (rodar manualmente no servidor, depois de resolver os TODOs acima)

```bash
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

Eu **nao** rodei este comando nem qualquer outro contra um servidor real —
apenas editei os arquivos de config versionados neste repositorio.
