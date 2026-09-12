# Migrations

## Regra que não tem exceção: migration aplicada é imutável

O `sqlx::migrate!` guarda em `_sqlx_migrations` o SHA-384 do arquivo. Alterar um
arquivo já aplicado — **inclusive só um comentário** — faz todo serviço que roda
migrations recusar subir:

```
Error: erro de migração: migration 32 was previously applied but has been modified
```

Não é aviso: é fatal, e por bom motivo. O sqlx não tem como saber se a mudança
foi um comentário ou um `DROP COLUMN`.

Isto aconteceu em 2026-09-11. O commit `07a15fd` acrescentou seis linhas de
comentário à `0032_mcp_oauth_grant.sql`, que já estava aplicada no banco de dev
desde 06:17 do mesmo dia. A imagem que aplicou a migration tinha sido construída
antes do commit, e os deploys seguintes falharam no `pull` por outro motivo — o
arquivo modificado só chegou ao servidor à noite, e aí `data_postgres`,
`worker` e `webhook_ingress` entraram em crash loop. A correção foi restaurar o
conteúdo exato e trazer a explicação para cá.

Três dias antes, 08 a 11 de setembro, a variante inversa causou uma interrupção
de três dias: a `0030` foi aplicada no banco de dev pela máquina do
desenvolvedor antes de a imagem publicada conter o arquivo, e todo restart
morria com `migration 30 was previously applied but is missing in the resolved
migrations`.

### Na prática

- Errou numa migration já aplicada? **Crie a próxima**, não edite a anterior.
- Precisa documentar algo sobre uma migration antiga? Escreva aqui.
- Aplicou uma migration de branch no banco compartilhado de dev? Ela precisa
  chegar à `dev` **antes** do próximo deploy, senão a stack não sobe.

## Notas por migration

### `0032_mcp_oauth_grant.sql` — sem `GRANT` explícito, de propósito

A migration `0018` configurou `ALTER DEFAULT PRIVILEGES IN SCHEMA public` para a
`smartcore_app_rt`, então toda tabela criada depois dela pela mesma role já
nasce com DML concedido. Verificado contra o banco de dev: `tenants_voucher`
(criada na `0027`, também sem `GRANT`) tem SELECT/INSERT/UPDATE/DELETE para a
role de runtime.
