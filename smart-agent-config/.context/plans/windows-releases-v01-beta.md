---
type: plan
name: windows-releases-v0.1-beta
title: "Smart Core Tenant — Instalador Windows v0.1.0-beta (download autenticado e auditado)"
description: "Distribuição do instalador Windows (Velopack) do app tenant para superusuários do admin DEV, com link de download de curta duração emitido pelo control_plane, auditoria no security:stream e releases_server endurecido."
planSlug: windows-releases-v01-beta
summary: "Fecha as lacunas do plano servidor-releases-windows: releases_server funcional e seguro, ticket assinado (HMAC) emitido pelo control_plane via AdminService (runtime_api, gRPC-Web), tela de download no admin Flutter, feed Velopack real no canal beta e trilha de auditoria completa."
prevc_scale: LARGE
supersedes_partially: servidor-releases-windows
generated: 2026-10-03
status: aguardando-review

phases:
  - id: "phase-p"
    name: "Planning — Requisitos, segurança e contrato"
    prevc: "P"
    summary: "Fixar requisitos funcionais, modelo de ameaça, formato do ticket, catálogo de eventos de auditoria, nomes de métricas e as decisões D1–D6."
    required_sensors: ["approval"]
    required_artifacts:
      - "windows-releases-v01-beta/plano_completo_windows-releases-v01-beta.md"
      - "windows-releases-v01-beta/info_aux_windows-releases-v01-beta.md"
    deliverables:
      - "Contrato proto: AdminService.GetWindowsDownloadLink"
      - "Contrato RPC interno: control_plane IssueReleaseDownloadTicket"
      - "Formato do ticket HMAC (claims, TTL, segredo) aprovado"
      - "Catálogo de eventos release_* e métricas smartcore_releases_*"
      - "Decisões D1–D6 registradas (NSIS x Velopack, feed beta, canal)"

  - id: "phase-r"
    name: "Review — Código existente, segurança e desempenho"
    prevc: "R"
    summary: "Revisar releases_server, workflows e compose contra os achados G1–G16; auditoria de segurança do desenho do ticket; orçamento de recursos em 2 vCPU."
    required_sensors: ["security_review", "approval"]
    required_artifacts: ["code_review_findings", "security_audit_report"]
    deliverables:
      - "Lista de correções do releases_server aceita (bloqueadores G1–G8)"
      - "Security review do ticket + ServeDir + upload aprovado"
      - "Aprovação do architect para a fase E"

  - id: "phase-e"
    name: "Execution — Implementação"
    prevc: "E"
    summary: "E1 releases_server; E2 control_plane (ticket + auditoria); E3 runtime_api (AdminService); E4 admin Flutter; E5 CI Velopack canal beta; E6 Caddy + compose."
    required_sensors: ["tests", "build_status"]
    required_artifacts: ["releases_server", "control_plane_rpc", "runtime_api_admin_service", "admin_ui_screen", "ci_velopack_beta", "caddy_compose"]
    deliverables:
      - "releases_server no workspace, compilando no CI, sem stubs"
      - "IssueReleaseDownloadTicket no control_plane com auditoria"
      - "GetWindowsDownloadLink no runtime_api com guarda superuser"
      - "Tela 'Instalador Windows' no admin_module"
      - "Pipeline win-v*-beta gerando feed releases.beta.json real"
      - "Bloco releases. no Caddyfile validado"

  - id: "phase-v"
    name: "Validation — Testes, auditoria e rate limit"
    prevc: "V"
    summary: "Testes de unidade/integração, negativos de segurança, verificação ponta a ponta da trilha de auditoria e do rate limit, instalação e auto-update reais numa VM Windows."
    required_sensors: ["integration_tests", "security_audit"]
    required_artifacts: ["test_matrix_evidence", "audit_trail_evidence", "e2e_windows_evidence"]
    deliverables:
      - "Matriz de testes V1–V12 verde"
      - "Evidência: audit_log com release_download_link_issued + traceparent correlacionado no Tempo"
      - "Evidência: instalação 0.1.0-beta → auto-update para 0.1.1-beta"

  - id: "phase-c"
    name: "Complete — Deploy, docs e runbook"
    prevc: "C"
    summary: "Deploy DEV via CI, dashboard e alertas, runbook de publicar/reverter/revogar, limpeza dos artefatos placeholder e da doc incorreta."
    required_sensors: ["deployment_success"]
    required_artifacts: ["runbook_deploy", "grafana_dashboard", "cleanup_completed"]
    deliverables:
      - "Stack releases no ar em DEV atrás do Caddy"
      - "Painel Grafana + 3 alertas"
      - "Runbook (publicar, reverter, rotacionar segredos, revogar ticket)"
      - "INTEGRACAO_DOWNLOAD_ADMIN.md removido (descreve Django, que não é o admin v2)"
---

# Smart Core Tenant — Instalador Windows v0.1.0-beta

> Plano canônico (versão enxuta). O detalhamento por fase, com subtarefas, critérios de
> sucesso, checklists de observabilidade e riscos, está em
> [`windows-releases-v01-beta/plano_completo_windows-releases-v01-beta.md`](./windows-releases-v01-beta/plano_completo_windows-releases-v01-beta.md).
> Bibliotecas, serviços e decisões ficam em
> [`windows-releases-v01-beta/info_aux_windows-releases-v01-beta.md`](./windows-releases-v01-beta/info_aux_windows-releases-v01-beta.md).

## Relação com `servidor-releases-windows`

Este plano **não substitui** o anterior. Ele recorta a entrega `v0.1.0-beta` e corrige
o que a revisão de 2026-10-03 mostrou ter sido dado como pronto sem estar
(ver "Estado real"). Landing page pública, canal `stable` e v1.0.0+ continuam no
plano anterior e no `n12-cutover-producao`.

## Arquitetura confirmada (2026-10-03)

```
Admin Flutter web (/v2/admin, superusuário)
   │ gRPC-Web + JWT (is_superuser)
   ▼
runtime_api  ── AdminService.GetWindowsDownloadLink
   │  exigir_superuser_do_metadata → auth_access_denied quando negado
   │ transport (RPC interno, Envelope)
   ▼
control_plane ── IssueReleaseDownloadTicket
   │  valida versão/canal no manifesto, assina ticket HMAC-SHA256 (TTL 5 min)
   │  publica release_download_link_issued no security:stream → audit_log
   ▼
URL https://releases.smartcoreassistant.com.br/download/{v}/{arquivo}?t=<ticket>
   ▼
releases_server (Axum 0.8, porta 8086, atrás do Caddy)
   valida ticket (assinatura, expiração, versão/arquivo) → stream do arquivo
   métricas smartcore_releases_* + log estruturado com o jti

App instalado (Velopack UpdateManager) → GET /feed/beta/releases.beta.json + *.nupkg
```

Pontos que mudam o pedido original:

- **O navegador não fala com o control_plane.** A única superfície HTTP dele é o
  authorization server OAuth do MCP (`auth.`, porta 8095). O admin `/v2/admin` é
  **Flutter web** (não Django) e fala gRPC-Web com o `runtime_api`. Por isso o "endpoint
  no control_plane" é um **RPC interno** chamado pelo `runtime_api`, no mesmo padrão
  já usado por `TestEvolutionConnection`.
- **Permissão = claim `is_superuser` do JWT**, checada na borda (`runtime_api`), e não
  OAuth/roles do MCP. O OAuth do control_plane serve só a clientes MCP.
- **Velopack lê `releases.{canal}.json`** no formato `{"Assets":[...]}`. Com canal
  `beta` o arquivo é `releases.beta.json`; `releases.win.json` é só o canal padrão. O
  `releases.win.json` publicado hoje usa um formato próprio que o Velopack não entende.

## Estado real (achados da revisão)

| # | Achado | Gravidade |
|---|---|---|
| G1 | `releases_server` fora de `[workspace].members`: o CI não compila | Bloqueador |
| G2 | Não compila: falta `use secrecy::ExposeSecret`; `IntoResponse` devolve `&msg` de variável local | Bloqueador |
| G3 | Rotas `/:version/:filename`: o Axum 0.8 entra em pânico na subida (o certo é `{version}`) | Bloqueador |
| G4 | Handlers stub: upload responde "success" sem gravar nada; download devolve o texto `"file content here"` | Bloqueador |
| G5 | `ServeDir` em `/releases` publica o diretório inteiro, incluindo `.env` com `RELEASES_UPLOAD_TOKEN`, `server_mock.py` e `server.log` | Crítico |
| G6 | `/opt/smartcore/releases/.env` com permissão 644 | Alto |
| G7 | O `compose.yml` monta dois volumes no mesmo alvo `/data/releases` | Bloqueador |
| G8 | O Setup.exe publicado é um placeholder de 76 bytes ("MZ" + texto); o SHA citado no guia é o de um arquivo vazio | Bloqueador |
| G9 | O guia `INTEGRACAO_DOWNLOAD_ADMIN.md` descreve Django; o admin v2 é Flutter | Doc incorreta |
| G10 | Dois workflows disparam na mesma tag `win-v*`; `release-windows.yml` só tem placeholders | Alto |
| G11 | `vpk pack --channel win` (deveria ser `beta`), `--signParams` sem certificado, upload só do Setup.exe (falta `.nupkg` + feed) | Alto |
| G12 | `velopack_flutter` é importado em `main_branded.dart` mas não está no `pubspec.yaml`; CI usa Flutter 3.24, o app exige `>=3.44` | Alto |
| G13 | NSIS e Velopack geram cada um o seu Setup.exe; um instalador NSIS não monta o layout que o `Update.exe` do Velopack espera | Decisão D1 |
| G14 | Sem bloco `releases.` no Caddyfile: o DNS aponta para cá, mas o TLS falha. O link **ainda não está exposto**, e passa a estar no instante em que o bloco entrar | Médio |
| G15 | Não usa o crate `observability` (sem OTel/traceparent, sem `/metrics`), não tem limite de corpo para upload e a comparação de token vaza o tamanho | Médio |
| G16 | Testes de integração são `assert!(true)` | Médio |

## Escopo do control_plane (código novo em Rust)

1. Rota RPC `IssueReleaseDownloadTicket` em `server.route(...)` no `main.rs`.
2. Módulo `releases/` com: leitura do manifesto (`releases.beta.json` montado como
   somente leitura), assinatura do ticket (`hmac` + `sha2`, segredo
   `RELEASES_DOWNLOAD_SECRET` em `SecretString`) e publicação de
   `release_download_link_issued` no `security:stream`.
3. Recusa fechada: sem `RELEASES_DOWNLOAD_SECRET`, a rota responde erro e o restante do
   control_plane segue no ar (mesmo padrão do `montar_oauth`).

## Fases PREVC (resumo)

| Fase | Saída principal | Gate |
|---|---|---|
| **P** | Contratos (proto + RPC + ticket), catálogo de auditoria, decisões D1–D6 | Plano aprovado |
| **R** | Achados G1–G16 triados, security review do ticket | `security_review` + `approval` |
| **E** | E1 releases_server · E2 control_plane · E3 runtime_api · E4 admin Flutter · E5 CI · E6 Caddy/compose | CI verde, imagens no GHCR |
| **V** | Testes V1–V12, trilha de auditoria ponta a ponta, auto-update real em VM Windows | Evidências anexadas |
| **C** | Deploy DEV, dashboard, alertas, runbook, limpeza | Handoff |

## Auditoria (catálogo resumido)

| Evento | Serviço | Nível | Quando |
|---|---|---|---|
| `release_download_link_issued` | control_plane | INFO | Ticket emitido para um superusuário |
| `auth_access_denied` | runtime_api | WARN | Chamada sem `is_superuser` (guarda existente) |
| `release_download_ticket_rejected` | releases_server | WARN | Ticket inválido, expirado ou adulterado |
| `release_published` | releases_server | INFO | Upload do CI aceito e feed trocado atomicamente |
| `release_upload_rejected` | releases_server | WARN | Token inválido, hash divergente, nome fora do padrão |
| `release_rolled_back` | releases_server (CLI) | WARN | Feed revertido para a versão anterior |

Nunca registrar: o ticket inteiro, `RELEASES_UPLOAD_TOKEN`, `RELEASES_DOWNLOAD_SECRET` ou o JWT.
Só identificadores: `jti`, `user_id`, versão, arquivo e `traceparent`.

## Decisões em aberto (resolver em P/R)

- **D1** Abandonar o NSIS para o app e usar o Setup.exe do Velopack com `--icon`/`--splashImage` (recomendado).
- **D2** Feed beta público com rate limit x feed com token de canal (recomendado: público + rate limit; o app exige login de qualquer forma).
- **D3** Ticket reutilizável dentro do TTL x uso único (recomendado: reutilizável, TTL 5 min; uso único exige Redis no releases_server).
- **D4** Ticket assinado no control_plane (recomendado, pedido do dono) x direto no runtime_api.
- **D5** Assinatura de código (Authenticode) fica fora da beta; o SmartScreen avisa, e isso vai documentado.
- **D6** Tag `win-vX.Y.Z-beta.N` para o canal beta e `win-vX.Y.Z` para stable; um único workflow.
