# 28 — Operação autônoma e alertas (levantamento prévio)

> **Status:** levantamento, não plano fechado. Escrito em 2026-09-05 para ser
> amadurecido depois. Nada aqui foi implementado, com uma exceção anotada no §6.
>
> **Contexto que define tudo neste documento:** manutenção **solo**, primeiro
> sistema em produção do responsável, sem tempo de acompanhar painel. O produto
> é um executável instalado na máquina de cada cliente. A intenção declarada é
> montar um agente Claude no próprio servidor, com tarefas agendadas e leitura
> de log, e receber por e-mail um relatório do que o agente **não** conseguiu
> resolver.

---

## 1. O problema real, em uma frase

Ninguém vai olhar. Então o sistema precisa se defender sozinho e, quando não
conseguir, **falar** — em vez de esperar alguém perguntar.

Isso muda o critério de projeto: a métrica que importa não é "temos
observabilidade?", é **"quantas falhas se resolvem sem intervenção, e quanto
tempo leva até eu ficar sabendo das outras?"**.

## 2. O que já existe (não refazer)

| Peça | Onde | Situação |
|---|---|---|
| Métricas, logs e traces | `docker/observability/` (Prometheus, Loki, Tempo, OTel) | Funcionando |
| Dashboards | `provisioning/dashboards/json/` (5) | Funcionando |
| Regras de alerta | `provisioning/alerting/rules.yml` (5) | **Disparam e morrem** — ver §3 |
| Reinício de container morto | `watchdog` (worker próprio, usa docker.sock) | Funcionando |
| Backup do Postgres | `pg_backup`, diário, com alerta de atraso | Funcionando |
| Runbooks | `infra/RUNBOOK_*.md` | Escritos |

As 5 regras existentes: backlog de outbox, lag do bus, serviço fora do ar,
backup atrasado, taxa de erro RPC.

## 3. O buraco nº 1 — o alerta não sai de casa

Valor real no servidor hoje:

```
SMARTCORE_ALERTA_WEBHOOK_URL=http://localhost:9/alerta-nao-configurado
SMARTCORE_ALERTA_EMAIL=ops@smartcore.local
GF_SMTP_ENABLED=false
```

As regras avaliam, o alerta dispara, e a notificação morre no contact point. O
próprio arquivo (`contact-points.yml`) já avisa disso em comentário.

**Consequência:** hoje, se tudo cair às 3h, ninguém fica sabendo até alguém
abrir o app.

**É o item de maior retorno por esforço do documento inteiro.** Como o usuário
quer e-mail, o caminho é `GF_SMTP_ENABLED=true` + credenciais SMTP (Gmail com
senha de app, Amazon SES, Resend, Brevo — qualquer um serve). O webhook fica
como segundo canal se um dia entrar Discord/Telegram.

Cuidado a decidir depois: **e-mail por alerta vira ruído e é ignorado em duas
semanas.** Preferir digest (ver §5) a notificação por evento, exceto para o
punhado de coisas realmente urgentes (§4).

## 4. O que merece acordar alguém × o que só entra no relatório

Separação que evita o alerta virar spam:

**Urgente (e-mail imediato)**
- Serviço do compose fora do ar por > 5 min (o watchdog já tentou e falhou).
- WhatsApp de um tenant exigindo pareamento (nenhuma mensagem entra; só resolve
  com QR na mão do cliente) — **não existe regra hoje**, ver §6.
- Backup sem sucesso há > 36h.
- Disco > 85%.
- Postgres inacessível.

**Relatório diário (digest, um e-mail)**
- Taxa de erro RPC, latência p95, backlog de outbox e lag do bus.
- Reinícios feitos pelo watchdog nas últimas 24h.
- Reconexões de WhatsApp feitas sozinhas (§6) — saber que 40 reconexões
  aconteceram é informação de saúde, não emergência.
- Quota de storage por tenant.
- Dead letters acumuladas.

**Nunca alertar**
- Falha transitória que a própria retentativa resolveu.
- `unknown` de provedor externo (é "não sei", não "está fora").

## 5. Formato do agente no servidor (a intenção declarada)

Esboço para amadurecer, não decisão:

- **Gatilho:** cron no host chamando Claude Code em modo não-interativo, com
  um prompt fixo versionado no repo (`infra/agente/`). Frequência sugerida:
  a cada 30 min para a varredura curta, 1×/dia para o digest.
- **Entrada:** saída de `docker ps`, `docker logs --since`, consulta ao
  Prometheus (`/api/v1/query`), e as tabelas de saúde do próprio banco.
- **Ação permitida (lista fechada, nunca aberta):** reiniciar container do
  projeto, reprocessar dead letter, disparar reconciliação de conexão, limpar
  arquivo temporário. **Nada que altere schema, apague dado ou mexa em código.**
- **Saída:** e-mail com o que fez, o que não conseguiu, e o que precisa de você.
- **Trava obrigatória:** o agente **não** pode ter poder de deploy nem
  credencial de banco com escrita ampla. O que ele não resolve, ele relata.

Risco a considerar: um agente com docker.sock tem poder de root no host. Vale
restringir por um wrapper com lista fixa de comandos, em vez de dar shell livre.

## 6. Sonda sintética e reconciliação (o que evita o incidente, não só o avisa)

O incidente de 2026-09-05 é o caso de estudo: a conexão de WhatsApp caiu em
algum ponto de agosto, ninguém religou, e ao fim de ~14 dias offline o WhatsApp
**desvinculou o aparelho** — transformando uma falha reparável em "só com QR
presencial". O monitoramento sozinho não teria evitado; teria só avisado antes.

> **Exceção ao "nada aqui foi implementado":** a reconciliação periódica de
> conexões **foi implementada** em 2026-09-05 (`worker/src/scheduler.rs`,
> tarefa `reconciliar_conexoes_whatsapp`, e o RPC
> `ReconciliarConexaoInstancia` no `data_whatsapp`). O que falta é a **regra de
> alerta** para o caso que ela não resolve (`precisa_parear`).

Ainda a fazer:
- **Métrica** `smartcore_whatsapp_instancias_fora` (por tenant) alimentada pela
  reconciliação, e regra de alerta em cima dela.
- **Sonda sintética** do caminho crítico, de fora do servidor: login →
  listar atendimentos → presign de mídia. É o que pega "tudo verde e o produto
  não funciona" — como o storage apontado para MinIO interno, que passou
  despercebido por semanas porque nenhum healthcheck testa o caminho real.

## 7. O que o cliente vê (decisão de produto, já implementada em parte)

Como o app roda na máquina do cliente, erro de operação precisa aparecer **na
tela dele**, não só no seu e-mail:

- ✅ Faixa no topo do quadro quando a conexão está fora, com botão para
  reconectar (`AvisoConexao`, 2026-09-05).
- ✅ Tela de conexões com QR e criação de conexão nova.
- ⬜ Distinguir na tela "religando sozinho, aguarde" de "precisa do seu
  celular agora" — hoje as duas caem no mesmo aviso.
- ⬜ Aviso de versão desatualizada do executável (o cliente instala e esquece;
  sem isso você mantém N versões em campo).

## 8. Ordem sugerida

1. **Canal de e-mail funcionando** (§3). Meia hora, destrava tudo o que já existe.
2. **Alerta de WhatsApp exigindo pareamento** (§6). É a falha que mais dói e a
   única que o servidor não resolve sozinho.
3. **Digest diário** (§4). É o que substitui "olhar o painel".
4. **Sonda sintética** (§6).
5. **Agente no servidor** (§5) — por último: ele é o mais trabalhoso e o mais
   arriscado, e os quatro itens acima já cobrem a maior parte do valor.

## 9. Perguntas em aberto (para decidir ao amadurecer)

- Qual SMTP? (Gmail com senha de app é o mais rápido; SES é o mais barato em
  escala.)
- O digest sai do Grafana (report) ou do agente? O agente dá mais contexto;
  o Grafana não depende de agente nenhum.
- Onde mora o estado do agente entre execuções (o que ele já avisou, para não
  repetir)? Uma tabela no Postgres resolve.
- Multi-tenant: o alerta de conexão caída de um cliente vai só para você, ou o
  cliente também recebe? (Muda o produto, não só a operação.)
