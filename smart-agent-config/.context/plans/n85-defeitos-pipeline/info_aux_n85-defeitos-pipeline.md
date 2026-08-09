# Documentação Auxiliar — N8.5 Defeitos do Pipeline

> Gerado em: 2026-08-09
> Plano canônico: `.context/plans/n85-defeitos-pipeline.md`
> Plano completo: `.context/plans/n85-defeitos-pipeline/plano_completo_n85-defeitos-pipeline.md`

---

## Escopo de dependências

Esta fase é **inteiramente interna**: nenhuma API externa nova, nenhuma lib nova.
Todas as libs envolvidas estão na central local e **atualizadas** (nenhuma
chamada ao Context7 foi necessária — triagem da etapa 2a).

| Lib | Versão | Doc local (verificação) | Uso nesta fase |
|---|---|---|---|
| `redis` | 0.25.0 | `doc_dev/libs/rust/redis.md` (2026-06-10) | buffer de agregação (E2): `RPUSH`/`LRANGE`/`DEL`, `SET NX EX`, script Lua |
| `tokio` | 1.38 | `doc_dev/libs/rust/tokio.md` | `tokio::spawn` + `time::sleep` do drenador (E2) |
| `sqlx` | 0.9 | `doc_dev/libs/rust/sqlx.md` (2026-06-10) | migration + queries de `feedback_solicitado_em` (E3) |
| `serde` / `serde_json` | 1.0 | `doc_dev/libs/rust/serde.md` | payloads do buffer e dos eventos |
| `tracing` | 0.1.40 | `doc_dev/libs/rust/tracing.md` | spans novos |

### Nota sobre o buffer no Redis (E2)

O padrão de drenagem atômica (`LRANGE` + `DEL` numa operação) pede **script Lua**
ou `MULTI/EXEC`. A doc local de `redis` cobre pipelines e transações; a v1 resolve
com lock explícito (`cache.lock`), o que aqui seria um segundo lock — evitável.

**Referência interna mais útil que qualquer doc externa:** o próprio projeto já
usa `SET NX EX` para lock (`worker/src/main.rs:1075`) e locks de scheduler
(`scheduler.rs:116`). Seguir esses padrões.

---

## Fontes internas (a verdade desta fase)

O plano se baseia em leitura de código, não em documentação externa:

| Comportamento | v1 (referência) | v2 (estado atual) |
|---|---|---|
| Descarte de grupo | `app/evolution_sync/services/webhook.py:158-191` | `domain_whatsapp/src/lib.rs:83` (campo `is_group`, sem leitor) |
| Buffer de mensagens | `app/evolution_sync/services/message_buffer.py` + `attendance_orchestrator.py:197` (`_compile_message_content`) | `worker/src/main.rs:1067-1092` (lock `SET NX EX 2`) |
| Pesquisa de satisfação | `app/atendimentos/models.py:416-470` (`finalizar_atendimento`, `_enviar_solicitacao_feedback`) e `attendance_orchestrator.py:1453` (`_check_and_process_feedback`) | `worker/src/scheduler.rs:141` (só expira); `avaliacao`/`feedback` só em SELECT |
| Mensagens automáticas | `TenantConfig.msg_fallback` / `msg_sem_info` | `config_publisher.rs:40-41` (publica) e nenhum consumidor; `worker/src/main.rs:1118` (`BOT_TEXT_FALLBACK` constante) |
| Eventos de webhook | `webhook.py:59-92` (MESSAGE_UPDATE, PRESENCE, CONTACTS, CONNECTION) | `webhook_ingress/src/main.rs:620-650` (normaliza os 4) × `worker/src/main.rs:710-720` (consome 2) |

---

## Taxonomia de auditoria existente (para nomear os eventos novos)

Convenção observada no código: `<dominio>.<acao>`, em pt-br para o domínio de
negócio e em inglês para alguns legados de infra.

Já em uso: `atendimento.aberto`, `atendimento.feedback_expirado`,
`atendimento.transferido_por_ia`, `bot.respondeu`, `bot.silenciado`,
`bot.degradado`, `mensagem.persistida`, `mensagem.enviada`,
`mensagem.dead_letter`, `mensagem.falha_envio`, `kanban.movido`,
`ticket.transicionado`, `midia.analisada`, `midia.purgada`,
`whatsapp_instance.created` / `.deleted` / `.state_updated`, `quota.excedida`,
`webhook.rejected` / `.ignored` / `.duplicated`, `service.*` (watchdog).

**Eventos novos propostos nesta fase:**
`atendimento.pesquisa_solicitada`, `atendimento.avaliado`.
Reaproveitado: `whatsapp_instance.state_updated` (agora também pelo caminho do
webhook, com campo `origem`).

---

## Grupo C — Observabilidade e Auditoria por etapa

| Etapa | Span/log | `audit_log` | Sanitização |
|---|---|---|---|
| E1 grupo | INFO `motivo="grupo"` + contador `smartcore_webhook_grupo_descartado_total` | **sem evento** (intencional: filtro de ingestão) | JID mascarado; nunca `push_name` nem conteúdo |
| E2 buffer | `mensagem.buffer` (contagem, janela) DEBUG/INFO; span link para o `trace_id` da 1ª mensagem | **sem evento** (intencional: agregação não muda estado) | **conteúdo de mensagem fica no Redis** — TTL curto, nunca logar o texto |
| E3 satisfação | `atendimento.pesquisa_enviada`, `.feedback_recebido` (nota, origem) | **`atendimento.pesquisa_solicitada`, `atendimento.avaliado`** | texto do feedback é PII — só a nota sai do banco |
| E4 msg_* | campo `origem_texto` no `bot.degradado` existente | **sem evento** (a config já é auditada no update) | sem risco |
| E5 eventos | `whatsapp.conexao_mudou`, `.contato_atualizado`; presença em DEBUG | **`whatsapp_instance.state_updated`** com `origem`; **sem** auditoria para presença | telefone mascarado no payload de CONTACTS |

**Política de instrumentação** (arquitetura de erros do projeto):
`#[tracing::instrument(err)]` só onde todo erro é falha real de infra;
repositórios de tenant via `run_in_tenant_transaction` + `#[instrument(skip_all)]`.

## Nota de segurança nova

A E2 faz o **Redis de cache passar a guardar conteúdo de mensagem** (PII) durante
a janela de agregação. Não é o caso hoje — o lock guarda só `"1"`. Registrar em
`doc_dev/modelagem_dados/08_diretrizes_seguranca.md`: PII transitória no Redis,
com TTL de janela × 10 (teto 300 s), chave por tenant, sem persistência em disco
(confirmar `appendonly`/`save` do Redis de cache).
