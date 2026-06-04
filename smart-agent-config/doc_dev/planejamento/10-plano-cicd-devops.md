# 10 — Plano: CI/CD e DevOps (Hostinger)

> **Status:** Plano aprovado para detalhamento (greenfield, base operacional).
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Origem:** Estruturação da base operacional. A **observabilidade** foi
> extraída para um doc próprio e antecipada na ordem
> ([05-observabilidade.md](./05-observabilidade.md)); este plano cobre **CI/CD e
> DevOps**. Deriva de [00-planejamento-inicial.md](./00-planejamento-inicial.md),
> [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md) e
> [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md) (aprofunda a
> Etapa 9.5).

---

## 1. Contexto

A camada de dados (Postgres+pgvector, Redis, MinIO) roda em Docker Compose numa
VM Hostinger **KVM2** (~2 vCPU / 8 GB) e o deploy é hoje **manual** via scripts
SSH/SCP em `infra/` (`deploy-data.sh`/`.ps1`, `manage.ps1`, `tunnel.ps1`).
**Ainda não há** `.github/workflows` nem pipeline automatizado. Este plano define
**como automatizar build/entrega e operar a VM** com boas práticas, alinhado ao
que a Hostinger oferece.

> Observabilidade (logs/métricas/traces + stack LGTM) e tratamento de erros são
> tratados nos docs [05](./05-observabilidade.md) e
> [06](./06-tratamento-de-erros.md) — fundação, antes deste plano operacional.

## 2. Decisões travadas

| # | Tema | Decisão | Racional |
|---|------|---------|----------|
| O2 | Mecanismo de CI/CD | **SSH via GitHub Actions + GHCR** | Máximo controle, sem lock-in; reaproveita/evolui os scripts `infra/` atuais. CI builda e publica imagens no GitHub Container Registry; deploy por SSH |
| O3 | Ambientes | **Só produção por ora** | Estágio greenfield; staging fica como evolução futura (branch `dev` → 2ª VM) |

> A hospedagem do stack de observabilidade (**LGTM self-hosted na mesma VM**) é a
> decisão **Obs3** no doc [05](./05-observabilidade.md). **Alternativas não
> adotadas:** action oficial `hostinger/deploy-on-vps@v2` e self-hosted runner (O2).

## 3. Documentos a detalhar (próxima etapa)

Este doc 10 é o **plano-mãe** de CI/CD + DevOps; os dois abaixo serão detalhados.

### `11-ci-cd-pipelines.md`
Pipelines GitHub Actions por stack (CI) + entrega contínua via SSH+GHCR (CD).
- **CI por stack** (gatilho por path): `ci-server.yml` (fmt/clippy/test com
  Postgres+Redis de serviço + cache cargo + `SQLX_OFFLINE`), `ci-ia-engine.yml`
  (uv/ruff/pyright/pytest), `ci-clients.yml` (flutter analyze/test).
- **CD:** `build-images.yml` (push `main` → build multi-stage Rust com cargo-chef
  + imagem `ia_engine`, push GHCR tag SHA+latest) e `deploy-prod.yml` (SSH →
  `docker compose pull && up -d`, evolui `infra/deploy-data.sh`).
- **Dockerfiles:** multi-stage Rust → `debian-slim`/`distroless`; `ia_engine` com
  `uv`. (Hoje só há crates; Dockerfiles de `apps/*` entram quando os binários
  existirem — o CI de lint/test já roda desde já.)
- **Secrets/vars GitHub:** `HOSTINGER_SSH_*`, `SSH_PRIVATE_KEY`, `GHCR_TOKEN`,
  segredos de runtime injetados no `.env` remoto pelo job.
- **Gitflow→pipeline:** PR em `dev` roda CI; merge em `main` builda+deploya;
  branch protections (CI obrigatório; sem rodapé de IA nos commits).
- **Rollback:** tag por SHA (redeploy do SHA anterior); migrations sqlx em passo
  controlado; healthcheck + smoke test pós-deploy.

### `12-devops-hostinger.md`
Topologia, segredos, rede, backup, hardening e runbooks — alinhado à Hostinger.
- **Topologia da VM:** proxy reverso (Caddy/Nginx, TLS + `proxy_buffering off`)
  → apps Rust + `ia_engine` + Evolution Go → dados → LGTM; redes Docker
  segregadas (dados/app/observabilidade).
- **Compose:** `data.yml` (existe), `app.yml`, `observability.yml`,
  `evolution.yml` (novos); um `.env` por stack; convenção `smartcore_v2_*`.
- **Segredos:** padronizar geração (`openssl rand`), rotação, roadmap para
  secrets manager (doc 09 já recomenda p/ `JWT_SECRET`/`DATABASE_ADMIN_URL`);
  matriz de segredos por serviço. Storage de mídia já é externo (R2; doc 08).
- **Rede/firewall:** só 80/443 + 22 públicos; bancos, gRPC (50051) e portas LGTM
  fechados; acesso dev por túnel SSH (já em `tunnel.ps1`/`.sh`).
- **Backup:** `pg_dump` agendado + snapshot de volumes; snapshots/backups do VPS
  Hostinger como camada extra; destino off-site; política de retenção. (Mídia no
  R2 tem durabilidade própria + lifecycle — doc 08.)
- **Hardening:** SSH só por chave, `fail2ban`, updates automáticos, usuário
  não-root de deploy, Docker rootless opcional.
- **Recursos Hostinger:** KVM2 atual + caminho KVM4; API token (já em
  `.env.deploy`) p/ automações; snapshots; DNS/SSL.
- **Runbooks:** deploy, rollback, restart, restore de backup, leitura de
  dashboards, resposta a alerta — evolui o menu do `manage.ps1`.

## 4. Pesquisa de referência (resumo)

- **Hostinger CD:** existe a action oficial `hostinger/deploy-on-vps@v2`
  (API key + VM ID, exige template Docker) — registrada como **alternativa**;
  adotado SSH+GHCR por controle e reaproveitamento dos scripts atuais.
- **CI Rust:** `SQLX_OFFLINE` + cache do cargo; serviços (Postgres/Redis) no job
  para testes de integração.
- **Build de imagem:** cargo-chef para cache de dependências → binário enxuto.

Fontes:
- [Hostinger — Deploy to VPS using GitHub Actions](https://www.hostinger.com/support/deploy-to-hostinger-vps-using-github-actions/)
- [hostinger/deploy-on-vps (GitHub)](https://github.com/hostinger/deploy-on-vps)

## 5. Próximos passos

1. Detalhar os documentos `11` (CI/CD) e `12` (DevOps) no estilo dos docs 00–04.
2. (Opcional) Canonizar no dotcontext via skill `plan-restructuring`.

---

*Plano-mãe de CI/CD + DevOps. Observabilidade no doc 05. Sujeito a refinamento ao
detalhar os documentos 11–12.*
