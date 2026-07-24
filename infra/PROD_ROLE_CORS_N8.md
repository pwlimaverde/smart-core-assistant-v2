# N8.2 — Role `smartcore_app_rt` e CORS/lifecycle R2 de produção

> Achado da fase N8: os dois itens já estavam praticamente prontos desde N4/N5.3 —
> aqui só documentamos o que falta para aplicar em produção real (nada disso foi
> executado contra infraestrutura real nesta rodada).

## 1. Role não-superuser (`smartcore_app_rt`)

`infra/provision-db-role.sh` (entregue na N4.1) já é genérico — não tem nada
específico de dev, roda contra qualquer Postgres via `DATABASE_ADMIN_URL`. E
`docker/prod/.env.example` **já** aponta `DATABASE_URL` para `smartcore_app_rt`
por padrão (linha 28) — não precisa de mudança de código.

**O que falta é só execução** (fora do escopo desta rodada, que só constrói
código/config):

```bash
DATABASE_ADMIN_URL="postgresql://smartcore_app:<senha-atual-prod>@<host-prod>:5432/smartcore_v2" \
APP_RT_PASSWORD="<senha-forte-nova>" \
bash infra/provision-db-role.sh
```

Depois, preencher `APP_RT_PASSWORD`/`DATABASE_URL` no `.env` real do servidor de
produção (não versionado) e reiniciar `data_postgres` primeiro, na ordem já
documentada no cabeçalho do script.

## 2. CORS do R2 de produção

`infra/r2-cors.json` (fonte da verdade versionada) **já lista as duas origens**
(`https://dev.smartcoreassistant.com.br` e `https://smartcoreassistant.com.br`).
O que estava incompleto era o `.env.example` raiz, que só trazia a origem DEV em
`S3_CORS_ALLOWED_ORIGINS` — **corrigido nesta rodada** para incluir as duas
(comma-separated), já que `data_storage` aplica o CORS do bucket no boot
(`garantir_cors`, best-effort, lê `S3_CORS_ALLOWED_ORIGINS`) e não há mecanismo
separado para "ambiente prod" vs "ambiente dev" além dessa env var.

**O que falta é só execução**: confirmar que o `.env` real do servidor de
produção tem `S3_CORS_ALLOWED_ORIGINS` incluindo `https://smartcoreassistant.com.br`
(herda do `.env.example` atualizado se for copiado de lá; se o `.env` de prod já
existir com um valor antigo, precisa editar manualmente) e reiniciar
`data_storage` para reaplicar o CORS no bucket.

## Lifecycle do R2

`S3_LIFECYCLE_EXPIRATION_DAYS` (N4.3) já é lido de env, default 90 dias — sem
mudança necessária para produção; só confirmar se o valor de retenção real de
produção é diferente do default antes de aplicar.
