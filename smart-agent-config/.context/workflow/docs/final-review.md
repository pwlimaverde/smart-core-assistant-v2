# Final Review — n85-defeitos-pipeline

Data: 2026-08-09 · Diff: working tree sobre `dev` (branch `feature/n85-defeitos-pipeline`)

## Rótulo: CORRIGIDO (informativo — não bloqueia o ciclo)

## Resumo das correções

Um achado real durante a auditoria: o buffer de agregação gravava conteúdo de
mensagem no Redis **mesmo quando o bot não ia responder** (humano assumiu, flag
desligada, mensagem sem texto). Era PII em repouso coletada para alimentar uma
resposta que nunca sairia. Corrigido com um atalho antes do enfileiramento.
Também foi corrigido, de passagem, um vazamento pré-existente: o log
"Assistente virtual respondendo" imprimia o **telefone completo** do contato.

## 1. Plano vs. Implementado

| Item do plano | Status | Observação |
|---|---|---|
| **E1** — descartar grupo na ingestão | ✅ | `webhook_ingress/src/main.rs`: `evento_de_grupo` com checagem dupla (flag `isGroup`/`IsGroup` + sufixo `@g.us`), nos dois formatos de payload. Descarte com 202 **antes** do rate limit e da idempotência, como o plano exigia. |
| **E2** — buffer de agregação | ✅ | Módulo próprio `worker/src/buffer_mensagens.rs`. Dedupe por `message_id`, drain atômico via Lua, TTL com piso e teto, degradação declarada (`Enfileiramento::Indisponivel`). |
| **E3** — ciclo de satisfação | ✅ | Migration 0028 (coluna + índice parcial + 2 CoreSettings), solicitação na mesma transação do encerramento, interpretação da resposta (regex → IA), expirador corrigido. |
| **E4** — `msg_fallback`/`msg_sem_info` | ✅ | Worker lê `tenant:config:<uuid>` com invalidação por Pub/Sub; `msg_sem_info` aplicada no `ia_engine`. |
| **E5** — consumir `CONNECTION` | ⚠️ | `CONNECTION` e `PRESENCE` implementados. **`CONTACTS` não** — ver "Pendências". |
| ➕ Extra (não planejado) | ➕ | Telefone mascarado no log do acionamento do bot; 3 warnings pré-existentes de clippy corrigidos (`clone_on_copy` ×2, `result_large_err`). |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---|---|---|
| `worker/src/main.rs` (antes do `enfileirar`) | Conteúdo de mensagem ia para o Redis mesmo com o bot silenciado — PII gravada para ser descartada 5 s depois | Atalho: quando `!bot_pode_atender \|\| humano_ativo \|\| sem texto`, chama `acionar_bot` direto e retorna, sem tocar no buffer |
| `worker/src/main.rs` (`acionar_bot`) | `sender = %msg_normalized.sender` imprimia telefone **completo** em INFO (defeito pré-existente) | Passou a usar `mascarar_telefone` |
| `worker/src/config_tenant.rs:139` | `get_async_connection` deprecada | `#[allow(deprecated)]` com justificativa (Pub/Sub exige conexão dedicada), igual ao `realtime.rs` |
| `runtime_api/src/grpc_web.rs:3279,4531` | `clone_on_copy` (pré-existente) | `*req.get_ref()` |
| `data_postgres/src/main.rs:3774` | `result_large_err` (pré-existente) | `#[allow]` justificado: os dois lados do `Result` são o mesmo `Envelope` do protocolo |

## 2b. Observabilidade & Auditoria

| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| Descarte de grupo (E1) | ✅ INFO com `motivo`/`event_type` | ✅ N/A intencional | ✅ JID nunca sai; contador `smartcore_webhook_evento_descartado_total{tenant,motivo}` | Nível INFO deliberado: descartar grupo é o caso normal, WARN poluiria o alerta |
| Agregação de rajada (E2) | ✅ span `mensagem.buffer` com `trace_id`, `mensagens_agregadas`, `janela_ms` | ✅ N/A intencional | ✅ só a **contagem**; conteúdo nunca em log/span/métrica | PII em repouso documentada em `08_diretrizes_seguranca.md` §6.1 |
| Pesquisa solicitada (E3) | ✅ | ✅ `atendimento.pesquisa_solicitada` | ✅ | Emitida no handler porque a trilha vai pelo barramento, e a transação não o alcança |
| Avaliação registrada (E3) | ✅ INFO com `nota` e `origem` (`regex`\|`ia`) | ✅ `atendimento.avaliado` | ✅ `skip_all`; comentário do cliente só na coluna | |
| Fallback do bot (E4) | ✅ campo novo `origem_texto` (`tenant`\|`default`) | ✅ reaproveita `bot.degradado` | ✅ | O campo existe para tornar visível em produção se a config do tenant está sendo aplicada |
| Estado da conexão (E5) | ✅ span `whatsapp.conexao_mudou` | ✅ `whatsapp_instance.state_updated` com `origem` novo | ✅ | `origem` separa "provedor avisou" de "alguém consultou" |
| Presença (E5) | ✅ DEBUG (alto volume) | ✅ N/A intencional | ✅ telefone mascarado no log | Publicado no realtime, **não** persistido |

## 3. Riscos específicos verificados

- **Buffer perde mensagem?** Não. A persistência acontece **antes** do buffer; o que se perde num crash durante a janela é a *resposta automática*, não a mensagem — mesmo comportamento da v1, e o TTL evita chave órfã.
- **Buffer responde duas vezes?** Não no caminho normal (a chave `:timer` elege um único agendador). Existe uma janela teórica de resposta dupla se o Redis falhar **entre** o `RPUSH` e o `SET` do timer: a mensagem responde inline (degradação) e permanece no buffer. É falha parcial de Redis, o efeito é uma repetição, e a alternativa (não responder) é pior.
- **Nota inventada?** Não. A escala é validada nas duas pontas (regex conservador + `1..=5` no handler, que recusa fora da faixa). Testes fixam explicitamente o que **não** pode casar: `"meu pedido 512 ainda não chegou…"` → `None`.
- **Filtro de grupo come mensagem individual?** Não. Só descarta com flag `true` **ou** sufixo `@g.us`; há teste de regressão com JID individual e flag `false`.
- **Migration 0028 idempotente?** Sim: `ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `INSERT … ON CONFLICT DO NOTHING`. Só acrescenta — nenhuma perda ao reverter.

## 4. Revalidação

- `cargo fmt --check`: ✅
- `cargo clippy --all-targets --all-features -- -D warnings`: ✅
- Testes Rust: ✅ (unit/bins 25 suítes; `infrastructure_postgres` 42 + 45; demais 34 suítes)
- `cargo sqlx prepare --workspace --check`: ✅
- `ia_engine`: ✅ 169 testes, `ruff` e `mypy` limpos

## 5. Pendências (fora do escopo desta fase)

- **`whatsapp.contact.updated` sem consumidor.** O plano previa atualizar nome/foto
  do contato, mas **não existe porta de escrita de `whatsapp_contact`** no
  `data_postgres` — nenhum RPC toca essa tabela. Criá-la pela metade agora
  atrapalharia a **N11/E6** (perfil do contato sob demanda), que é onde esse
  domínio tem dono. Registrado em comentário no `despachar_evento`.
- **Override de janela por tenant.** `SMARTCORE_BUFFER_JANELA_MS` é global; o
  `time_cache` por tenant chega com o ETL da N12.
- **A auditoria independente por subagente não produziu relatório** (comportamento
  já registrado na memória do projeto para agentes de modelo alto neste ambiente).
  Esta revisão foi conduzida pelo agente principal seguindo o mesmo roteiro.
