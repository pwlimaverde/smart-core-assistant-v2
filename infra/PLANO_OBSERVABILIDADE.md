# Plano de correção da stack de observabilidade (LGTM)

Levantamento feito em **2026-09-05** direto no servidor `srv1321059`
(76.13.229.210). Nada deste plano foi aplicado ainda — a execução ficou para uma
sessão do Claude Code rodando **no próprio servidor**, via Remote Control.

## O resumo em uma frase

A stack está de pé há dois meses e **não monitora nada**: os painéis de métrica
estão vazios porque o collector roda com uma config que o repositório já
corrigiu, os cinco alertas nunca dispararam pelo mesmo motivo, e o Grafana está
publicado na internet com `admin/admin`.

## Estado encontrado

Tudo isto foi verificado no servidor, não deduzido:

| Item | Situação |
|---|---|
| Containers LGTM | No ar (`grafana`, `loki`, `tempo`, `prometheus`, `promtail`, `otel-collector`) |
| Grafana público | `https://grafana.smartcoreassistant.com.br` responde 200 (rota já existe em `docker/edge/Caddyfile`) |
| Datasources | Loki, Prometheus e Tempo provisionados e saudáveis |
| Dashboards | 5 provisionados; os painéis de métrica estão **vazios** |
| Alertas | 5 regras provisionadas; **nenhuma dispara**, e não há canal de entrega |
| Ingestão de logs | Funciona — promtail entrega os logs de container ao Loki |
| Traces | Chegam ao Tempo (volume com 147 MB) |
| Retenção | **Nenhuma** configurada em Loki, Tempo ou Prometheus |

Recursos do servidor: 2 vCPU, 7,8 GB de RAM (5 GB disponíveis), 96 GB de disco
(76 GB livres). A stack inteira consome ~700 MB de RAM. Espaço não é o problema
hoje; sem retenção, passa a ser.

---

## P1 — Grafana exposto com a senha padrão

**Gravidade: alta. Este é o primeiro item.**

O `compose.yml` da observabilidade nunca definiu `GF_SECURITY_ADMIN_PASSWORD`.
Existe um único usuário (`admin`, criado em 2026-06-20) e `admin/admin`
autentica. O `ufw` bloqueia a porta 3000 vinda de fora, mas isso não protege
nada: o Caddy publica o Grafana em `grafana.smartcoreassistant.com.br` com TLS.

Quem entrar lê logs e traces de **todos os tenants** e, pelo proxy de datasource,
consulta o Prometheus e o Loki à vontade.

### Correção

1. No `docker/observability/compose.yml`, no serviço `grafana`, acrescentar:

   ```yaml
   GF_SECURITY_ADMIN_PASSWORD: ${GF_SECURITY_ADMIN_PASSWORD:?defina no .env}
   GF_SERVER_ROOT_URL: https://grafana.smartcoreassistant.com.br
   GF_USERS_ALLOW_SIGN_UP: "false"
   ```

   O `:?` é proposital: sem a variável a stack **não sobe**, em vez de subir
   insegura em silêncio.

2. A variável só define a senha na **criação** do banco do Grafana. Como o
   usuário já existe, trocar de fato:

   ```bash
   docker exec smart-core-v2-observability-grafana-1 \
     grafana cli --homepath /usr/share/grafana admin reset-admin-password 'NOVA_SENHA'
   ```

3. Guardar a senha em `/opt/smartcore/observability/env/observability.env`
   (fora do repositório — ver P4, que usa o mesmo arquivo).

4. Validar: `curl -s -o /dev/null -w '%{http_code}' -u admin:admin \
   https://grafana.smartcoreassistant.com.br/api/org` deve devolver **401**.

---

## P2 — Todo painel de métrica está vazio (causa raiz)

O container `otel-collector` subiu em **2026-06-20**. O arquivo
`docker/observability/otel-collector-config.yml` foi alterado em **2026-07-10**
pelo commit `64f46a6`, que removeu `namespace: "smartcore"` do exporter
Prometheus — justamente para não duplicar o prefixo.

O arquivo entra no container por bind mount, e **`docker compose up -d` não
recria um container quando só o conteúdo do arquivo montado muda**. O collector
nunca releu a config. O resultado, no Prometheus de hoje:

| O dashboard consulta | O Prometheus tem |
|---|---|
| `smartcore_rpc_total` | `smartcore_smartcore_rpc_total` |
| `smartcore_outbox_backlog` | `smartcore_smartcore_outbox_backlog` |
| `smartcore_bus_pending` | `smartcore_smartcore_bus_pending` |
| `smartcore_service_up` | `smartcore_smartcore_service_up` |
| `smartcore_pg_pool_size` | `smartcore_smartcore_pg_pool_size` |

As cinco regras em `provisioning/alerting/rules.yml` usam exatamente os mesmos
nomes da coluna da esquerda. Ou seja: **nenhum alerta jamais disparou**, e não
por ausência de incidente.

### Correção

```bash
cd /opt/smartcore/ops/smart-core-assistant-v2/docker/observability
docker compose up -d --force-recreate otel-collector
```

Validar depois de ~1 minuto:

```bash
docker exec smart-core-v2-observability-grafana-1 \
  wget -qO- 'http://prometheus:9090/api/v1/label/__name__/values' \
  | tr ',' '\n' | grep smartcore
```

Deve aparecer `smartcore_rpc_total` (uma vez só o prefixo). As séries antigas
`smartcore_smartcore_*` continuam no TSDB até expirarem pela retenção do P5 —
isso é esperado e não atrapalha.

---

## P3 — O histograma de latência continua quebrado depois do P2

O exporter Prometheus do collector acrescenta o sufixo da unidade por padrão.
Mesmo com o P2 aplicado, a métrica sai como
`smartcore_rpc_duration_ms_milliseconds_bucket`, e o dashboard
`latencia_grpc.json` consulta `smartcore_rpc_duration_ms_bucket`.

### Correção

Em `otel-collector-config.yml`, no exporter `prometheus`:

```yaml
  prometheus:
    endpoint: 0.0.0.0:8889
    add_metric_suffixes: false
    resource_to_telemetry_conversion:
      enabled: true
```

Corrigir aqui, e não nos dashboards: é uma linha contra quatro painéis e uma
regra de alerta.

**Confira ao aplicar:** sem os sufixos automáticos, o exporter também deixa de
acrescentar `_total` aos counters. As métricas do código já nascem com esse
sufixo (`smartcore_rpc_total`), então nada quebra — mas confirme que a série
continua existindo antes de dar o item por fechado.

Este item e o P2 mexem no mesmo arquivo: aplique os dois e faça **um**
`--force-recreate`.

---

## P4 — Alerta que não chega a ninguém

`SMARTCORE_ALERTA_WEBHOOK_URL` está no valor de exemplo
(`http://localhost:9/alerta-nao-configurado`) e o SMTP está desligado. Mesmo com
P2 e P3 aplicados, a regra dispararia para o vazio.

O projeto **já tem um SMTP que funciona**, e o v1 e o v2 usam a mesma conta do
relay da Brevo. Duas fontes para a credencial, ambas disponíveis no servidor:

```bash
# v2 — o caminho mais curto (o arquivo já está no clone de manutenção)
grep -E '^SMTP_|^FROM_EMAIL' /opt/smartcore/ops/smart-core-assistant-v2/server/.env

# v1 — a mesma conta, pelas variáveis do container em produção
docker inspect smartcoreassistant_app \
  --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E '^EMAIL_|^DEFAULT_FROM'
```

Hoje: `smtp-relay.brevo.com:587`, TLS, usuário `9f3e2d001@smtp-brevo.com`,
remetente `suporte@smartcoreassistant.com.br`.

### Correção

1. Criar `/opt/smartcore/observability/env/observability.env` (fora do repo,
   mesmo padrão de `/opt/smartcore/prod/env/prod.env`):

   ```
   GF_SECURITY_ADMIN_PASSWORD=<senha do P1>
   GF_SMTP_ENABLED=true
   GF_SMTP_HOST=smtp-relay.brevo.com:587
   GF_SMTP_USER=9f3e2d001@smtp-brevo.com
   GF_SMTP_PASSWORD=<a mesma do container do v1>
   GF_SMTP_FROM_ADDRESS=suporte@smartcoreassistant.com.br
   SMARTCORE_ALERTA_EMAIL=<destino de plantão>
   ```

   `GF_SMTP_HOST` no Grafana é **host:porta**, não só o host.

2. Nos dois workflows de deploy, antes de subir a observabilidade, copiar esse
   arquivo para `docker/observability/.env` e subir com `--env-file .env` —
   exatamente como `deploy-prod.yml` já faz com `prod.env`.

3. Testar a entrega pelo botão **Test** do contact point no Grafana, e não pelo
   "salvou sem erro".

---

## P5 — Retenção infinita

Nenhum dos três armazenamentos descarta dado velho. Hoje: Loki 531 MB, Tempo
147 MB, Prometheus 69 MB. Com 76 GB livres isso demora, mas o fim é conhecido —
e disco cheio derruba a stack inteira, não só a observabilidade.

**Retenção definida: 14 dias.**

### Correção

`loki-config.yml`:

```yaml
limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  retention_period: 336h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
```

`tempo-config.yml`:

```yaml
compactor:
  compaction:
    block_retention: 336h
```

`compose.yml`, serviço `prometheus` — ao declarar `command` você **substitui** o
do entrypoint, então repita os caminhos padrão:

```yaml
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=15d
```

Os três exigem `--force-recreate` do respectivo serviço.

---

## P6 — Fechar a porta que deixou o P2 acontecer

Enquanto o deploy usar `docker compose up -d` puro, qualquer correção de config
da observabilidade volta a ficar só no disco, sem efeito no processo — foi assim
que os painéis passaram dois meses vazios sem ninguém notar.

Em `.github/workflows/deploy-dev.yml:280` e no passo equivalente de
`deploy-prod.yml`:

```yaml
      - name: Sobe observabilidade
        working-directory: docker/observability
        run: docker compose up -d --force-recreate
```

Recriar a stack inteira de observabilidade a cada deploy custa poucos segundos e
nenhum dado (tudo persiste em volume nomeado).

**Recomendação adicional, fora do escopo mínimo:** os seis serviços usam tag
`:latest`. Um `--force-recreate` combinado com `pull` pode trazer uma major nova
do Grafana ou do Loki sem aviso. Vale fixar as versões em outro passo.

---

## Ordem de execução

1. **P1** (senha do Grafana) — isolado, resolve a exposição, faça primeiro.
2. **P2 + P3** juntos: editar `otel-collector-config.yml` uma vez e um único
   `--force-recreate otel-collector`.
3. Esperar 2 minutos e conferir que os painéis de `servicos_saude` e
   `latencia_grpc` preenchem. **Não siga sem isto** — é a prova de que a
   telemetria voltou.
4. **P4** (SMTP) e disparar um teste real de contact point.
5. **P5** (retenção) — um `--force-recreate` por serviço tocado.
6. **P6** (workflows) — commit e PR; só tem efeito no próximo deploy.

Todo item que toca `docker/observability/**` precisa ir para o repositório no
mesmo movimento. O deploy do CI reescreve o que estiver só no disco do servidor.

## O que não fazer

- Não recriar o volume `grafana_data`: os dashboards são provisionados, mas o
  usuário e as preferências não.
- Não compilar nada no servidor. 2 vCPU e 7,8 GB de RAM; build é do CI.
- Não editar dentro de `/home/gh-runner/actions-runner/_work/` — é a workspace do
  runner e o próximo checkout descarta a alteração. O clone de manutenção é
  `/opt/smartcore/ops/smart-core-assistant-v2`.
- Não mexer nos containers `smartcoreassistant_*` (painel v1) nem
  `paulo-ecoprint-*` ao aplicar isto.

## Ponto em aberto, para decidir depois

Só a stack `smart-core-v2-dev` está no ar. `/opt/smartcore/prod/env/` está vazio
e nenhum container `smart-core-v2-prod` existe — o domínio principal ainda cai no
painel v1. A separação dev/prod da telemetria é por `OTEL_SERVICE_NAMESPACE`, e
hoje só existe `smartcore-dev`. Quando prod subir, revisar se os dashboards
precisam de um filtro por namespace.
