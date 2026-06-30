# Final Review — finalizacao-mvp-operacional (parcial WS-0..WS-4)
Data: 2026-06-30 · Modelo: Opus · Diff: working tree (caminhos WS-0..WS-4)

## Rótulo: CORRIGIDO  (informativo — não bloqueia o ciclo)

> **Nota de escopo (agente principal):** este é um final-review **parcial**. A fase
> E (Execution) está `in_progress` no `status.yaml`. O ciclo entregou **WS-0
> (parcial), WS-1, WS-2, WS-3, WS-4**; **WS-2.4, WS-5, WS-6, WS-7** e
> **WS-0.1/0.3/0.4** ainda não foram implementados (cronograma multi-mês S0.5–S9).
> Por isso o plano **NÃO foi arquivado** — segue ativo. Ver §5 Pendências.

## Resumo das correções
A implementação WS-0..WS-4 estava majoritariamente correta e bem estruturada (Ports &
Adapters, RPCs novos, stream real, fan-out Redis 0.25 com conexão dedicada vs.
multiplexada conforme exigido). Foram encontrados e corrigidos **8 desvios**, sendo
**1 crítico de segurança** (comparação de token NÃO constante-time) e vários de
sanitização/auditoria/observabilidade:

1. Token de instância comparado com `==` simples (timing attack) → trocado por `subtle::ConstantTimeEq`.
2. Token recebido no webhook não estava em `SecretString` → encapsulado.
3. `traceparent` W3C não era semeado no envelope publicado pelo webhook → adicionado via `observability::injetar_contexto_atual`.
4. `stream.nao_autorizado` ausente no handler de stream → auditado nas duas saídas de rejeição.
5. Telefone completo (PII) exposto em vários contextos de auditoria (webhook whitelist + worker) → mascarado.
6. Evento `bot.silenciado` ausente (WS-2.5) → emitido quando a barreira de bot silencia.
7. Eventos `mensagem.enviada`/`mensagem.falha_envio` (WS-3) ausentes no outbound do bot → adicionados.
8. Auditoria de confirmação usava nome fora do glossário (`mensagem.status_atualizado`) → renomeada para `mensagem.confirmada`.

Adicionalmente, completei o descomissionamento do `messaging_gateway` (WS-0.2): já
removido do workspace/compose/Dockerfile, removi também o diretório órfão git-tracked
e as referências em `.env.example`.

## 1. Plano vs. Implementado

| Item WS | Status | Observação |
|---|---|---|
| WS-0.2 plugar `AuditLogger` (worker/webhook) | ✅ | `new_with_redis` no boot, injetado no `AppState` |
| WS-0.2 descomissionar `messaging_gateway` | ⚠️→✅ | Estava fora do workspace/compose/Dockerfile, mas diretório+env órfãos restavam; **removidos na auditoria** |
| WS-1.1 auth token via RPC `VerifyWhatsappInstanceToken` | ⚠️→✅ | RPC ok, mas comparação não constante-time e token sem `SecretString` — **corrigido** |
| WS-1.2 whitelist `IsPhoneWhitelisted` | ✅ | RPC + `WhiteListRepository::esta_na_lista` |
| WS-1.3 idempotência `SET NX EX` | ⚠️ | Funciona, porém key `webhook:idempotency:<tenant>:<id>` (não no formato `tenant:<uuid>:...` do plano). Mantido (decisão autônoma) |
| WS-1.4 rejeição segura 401/403 sem publicar | ✅ | |
| WS-1 obs: `traceparent` semeado | ❌→✅ | **Adicionado** |
| WS-2.1 `domain_whatsapp` puro (sem I/O) | ✅ | Crate nova, parsing puro, testes unitários |
| WS-2.6 cliente RPC no `AppState` (sem reconexão) | ✅ | `pg_client`/`whatsapp_client` `Arc` reusados |
| WS-2.2 resolução contato→atendimento | ✅ | `ResolveAtendimentoParaContato` + repos em transação RLS |
| WS-2.3 debounce `SET NX EX` namespaced | ✅ | `tenant:<uuid>:lock:debounce:<contato>` |
| WS-2.4 ticket policy + Kanban | ❌ | **Não implementado** (sem `DecideTicketPolicy`/`ApplyKanbanStage`/RPCs). Pendência registrada |
| WS-2.5 barreira de bot | ⚠️→✅ | `bot.respondeu` ok; faltava `bot.silenciado` — **adicionado** |
| WS-3.1 outbound + retry/backoff | ✅ | `EvolutionProvider` com 3 tentativas, backoff exponencial em 5xx/429 |
| WS-3.2 confirmações de status | ⚠️→✅ | `UpdateMessageStatus` ok; evento renomeado p/ `mensagem.confirmada` |
| WS-4.1 server streaming (tonic) | ✅ | `StreamAtendimentosStream` + `ReceiverStream`; JWT validado na abertura |
| WS-4.2 fan-out Redis Pub/Sub 0.25 | ✅ | Subscriber em conexão dedicada `into_pubsub()`+`on_message()`; publisher (worker) usa `PUBLISH` |
| WS-4 obs: `stream.aberto/fechado/nao_autorizado` | ⚠️→✅ | `nao_autorizado` faltava — **adicionado** |
| WS-4.3 tonic-web 0.14.1 | ✅ | Pré-existente no workspace (CorsLayer/GrpcWebLayer já configurados) |
| WS-5 Register/Invite/Accept (➕ fora do ciclo) | ➕ | `CreateInvite`/`AcceptInvite` já no `data_postgres` — adiantado, fora do escopo desta auditoria |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---|---|---|
| `data_postgres/src/adapters/whatsapp.rs:177` | Token comparado com `inst.api_key == token` (timing attack) — viola WS-1.1 + tabela de riscos | `subtle::ConstantTimeEq` com igualdade de tamanho prévia |
| `data_postgres/Cargo.toml` + `server/Cargo.toml` | `subtle` indisponível | Adicionada dep `subtle = "2.5"` |
| `webhook_ingress/src/main.rs` (extração token) | Token não em `SecretString` (WS-1.1) | `SecretString::from(...)` + `expose_secret()` só na borda do RPC |
| `webhook_ingress/src/main.rs` (publicação) | `traceparent` W3C não semeado (§1.1) | `observability::injetar_contexto_atual` → `envelope.com_traceparent` |
| `webhook_ingress/src/main.rs` (audit not_whitelisted) | Telefone completo no contexto de auditoria | `mascarar_telefone(...)` (helper novo) |
| `webhook_ingress/Cargo.toml` | Falta `secrecy` | Adicionada dep |
| `runtime_api/src/grpc_web.rs:2434/2437` | Sem `stream.nao_autorizado` em rejeição | Auditoria WARN nas duas saídas (token inválido / tenant inválido) |
| `worker/src/main.rs` (bloco bot) | Só `bot.respondeu`; sem `bot.silenciado`/`mensagem.enviada`/`mensagem.falha_envio`; telefone exposto | Adicionados eventos + `mascarar_telefone` |
| `worker/src/main.rs:510` | Evento `mensagem.status_atualizado` fora do glossário | Renomeado p/ `mensagem.confirmada` |
| `worker/src/main.rs` (3 contextos) | `sender_id` com telefone completo na auditoria | Mascarado |
| `docker/{dev,prod}/.env.example` + `server/apps/messaging_gateway/` | Órfãos do descomissionamento | Referências e diretório removidos |

## 2b. Observabilidade & Auditoria

| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| webhook.received/rejected/duplicated | ✅ span `#[instrument]` | ✅ | ✅ (após correção: token `SecretString`, telefone mascarado) | `traceparent` semeado após correção |
| atendimento.aberto | ✅ | ✅ | ✅ (telefone mascarado após correção) | |
| mensagem.persistida / falha_persistencia | ✅ | ✅ | ✅ (telefone mascarado; conteúdo NÃO vai p/ audit) | |
| bot.respondeu / bot.silenciado | ✅ | ✅ (silenciado adicionado) | ✅ | |
| mensagem.enviada / falha_envio | ✅ | ✅ (adicionados) | ✅ (sem corpo; telefone mascarado) | |
| mensagem.confirmada | ✅ | ✅ (renomeado) | ✅ | |
| ticket.transicionado / kanban.movido | ❌ | ❌ | — | WS-2.4 não implementado |
| stream.aberto/fechado/nao_autorizado | ✅ | ✅ (nao_autorizado adicionado) | ✅ | |
| traceparent W3C bus→RPC | ✅ | — | — | Propagado em todos os RPCs do worker; semeado no webhook após correção |

## 3. Decisões Autônomas (revisar depois)
1. **⚠️ Remoção do diretório `server/apps/messaging_gateway/` (git-tracked) + refs `.env.example`.** Completa o WS-0.2; já estava fora do workspace, então não há impacto de build, mas é remoção de código versionado — confirmar que nenhum tooling externo ainda aponta para ele.
2. **Chave de idempotência mantida como `webhook:idempotency:<tenant>:<msg_id>`** em vez do formato `tenant:<uuid>:webhook:dedup:<msg_id>` do plano. Funcionalmente equivalente e isolada por tenant; não reescrevi para não arriscar divergência com chaves já em uso. Revisar se quiser padronizar o namespace `tenant:<uuid>:...`.
3. **`bot.silenciado` emitido para qualquer caso de barreira** (flag desligada OU humano ativo), com flags no contexto. Alinha ao glossário sem inventar sub-eventos.

## 4. Revalidação
- `cargo build --workspace` (SQLX_OFFLINE): **OK** (1m24s).
- `cargo clippy -D warnings --all-targets` nas crates afetadas (domain_whatsapp, webhook_ingress, worker, runtime_api, data_postgres, infrastructure_evolution, infrastructure_postgres): **OK, sem warnings**.
- `cargo fmt --check`: **OK** (após `cargo fmt`).
- `infra/test-quick.ps1 -Pkg domain_whatsapp,data_postgres`: **31 testes OK** (inclui novos `verify_token_success`, `is_phone_whitelisted_true`).
- `infra/test-quick.ps1 -Pkg worker`: **4 testes OK**.
- Testes de integração com banco (`test-local.ps1`) NÃO executados (exigem túnel SSH/DB remoto); validação restrita a unit+bins+clippy offline, conforme fallback previsto na tarefa.

## 5. Pendências (não implementados neste ciclo)
- **WS-2.4 (ticket policy + Kanban)**: `DecideTicketPolicy`/`ApplyKanbanStage` e RPCs de estágio NÃO existem; eventos `ticket.transicionado`/`kanban.movido` não são emitidos. Requer modelagem de estágios + RPCs no `data_postgres` — não fabricado para evitar lógica de negócio sem suporte.
- **WS-5** (Register/Invite/Accept + RBAC fino no `runtime_api`): handlers `CreateInvite`/`AcceptInvite` já existem no `data_postgres` (➕ adiantado), mas as rotas no `runtime_api`, `RbacGuard`, `flow_permissions` no middleware e `user_agent` no `AuditLogPayload` continuam pendentes. Nota: `AuditLogPayload` ainda **não tem `user_agent`** (exigido doc 08 §4.2 para eventos críticos do WS-5/WS-7).
- **WS-6** (telas Flutter `smart-core-admin`): não iniciado.
- **WS-7** (control_plane CRUD + `TenantConfigCache` plugado + telas admin): não iniciado.
- **WS-0.1/0.3/0.4** (stack LGTM, teste e2e de trace, métricas de pool): fora do diff deste working tree — não auditável aqui.
