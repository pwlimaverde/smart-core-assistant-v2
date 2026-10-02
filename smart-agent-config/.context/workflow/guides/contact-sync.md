# Guia de execução — Sincronização de Contatos WhatsApp

> Plano canônico: [`../../plans/contact-sync.md`](../../plans/contact-sync.md)
> Plano completo (detalhe técnico, snippets, observabilidade por fase):
> [`../../plans/contact-sync/plano_completo_contact-sync.md`](../../plans/contact-sync/plano_completo_contact-sync.md)
> Branch: `feature/contact-sync` a partir da `dev`. Testes **só na CI**; localmente apenas
> `cargo fmt`/`clippy`, `ruff`/`mypy`, `flutter analyze`.

## Mapa de gates

```
[G0] contrato confirmado ─► F1 ─► [G1] decisões D1–D3 ─► F2 ─► [G2] RPCs no data_postgres ─► F3.1 ─► [G3] stubs gerados ─┬─► F4
                                                                                                                       ├─► F3.2
                                                                       F2 (pontos de métrica) ─────────────────────────┴─► F5
```

| Gate | Libera | Condição |
|---|---|---|
| **G0** | F1 | Swagger lido; nomes reais de evento e rota de listagem anotados; fixtures commitadas |
| **G1** | F2 | Usuário respondeu D1, D2, D3 (registrar no plano canônico) |
| **G2** | F3.1 | Rotas `SincronizarContatosDoWhatsapp`, `ListarDivergenciasDeContato`, `ResolverDivergenciaDeContato`, `DefinirSincronizacaoDaAgenda`, `SolicitarSincronizacaoDaAgenda` mergeadas e verdes na CI |
| **G3** | F4, F3.2 | `admin.proto` mergeado; stubs Dart e Python regenerados na mesma PR |

---

## Etapa F0 — Confirmar o contrato da evolution-go

**Entradas:** acesso ao VPS de dev; `docker/evolution/compose.yml`; `ref_evolution_go.md` (N9) como pista, não como verdade.

**Checklist**
- [ ] Ler `http://<host>:8082/swagger/doc.json`: rota de listagem de contatos (candidata `GET /user/contacts`), header `apikey`, envelope `{data, message}`, paginação.
- [ ] Confirmar se existe rota de escrita de contato (esperado: não).
- [ ] Renomear um contato no aparelho de teste e trocar o nome de perfil; capturar `event_type` no log do `webhook_ingress`.
- [ ] Verificar se `canonical_event` descarta os nomes capturados (hipótese: `Contact`, `PushName`).
- [ ] Anonimizar payloads (telefone → `5500000000000`, sem `apikey`) e salvar fixtures.
- [ ] Reescrever a seção Evolution de `info_aux_contact-sync.md` (Bearer → `apikey`, remover rotas da v2 Node).

**Saídas:** `server/apps/webhook_ingress/tests/fixtures/contato_*.json`, `server/crates/infrastructure_evolution/tests/fixtures/contatos_lista.json`, `info_aux` atualizado.
**Observabilidade:** sem código novo; sem evento de auditoria (intencional).
**Bloqueador:** sem rota de listagem → polling sai do escopo; registrar e seguir só com webhook.

---

## Etapa F1 — Banco (migration 0051)

**Entradas:** G0; `migrations/README.md` (imutabilidade); `0004`, `0008`, `0045`, `0050`.

**Checklist**
- [ ] `0051_sincronizacao_de_contatos.sql`: colunas em `oraculo_contato` (`nome_contato_origem`, `nome_agenda_whatsapp`, `perfil_sincronizado_em`, `origem`) e `whatsapp_instance` (`sincronizar_agenda`, `agenda_sincronizada_em`).
- [ ] Tabelas `contato_divergencia` e `contato_evento_aplicado` com `ENABLE` + `FORCE ROW LEVEL SECURITY` e policy `app.current_tenant`.
- [ ] Índice parcial: 1 divergência aberta por `(tenant_id, contato_id, campo)`.
- [ ] Não repetir `GRANT` (default privileges da `0018` cobrem `smartcore_app_rt`).
- [ ] Atualizar os UPDATEs que já gravam `nome_contato` (C4 manual → `'manual'`, P15 IA → `'ia'`).
- [ ] Função pura `decidir_sincronizacao` + `aplicar_perfil_do_whatsapp` (`FOR UPDATE`, `#[instrument(skip_all)]`, sem `err`).
- [ ] `cargo sqlx prepare --workspace` e commit do `.sqlx/`.
- [ ] Testes: tabela-verdade da regra (unit); RLS das tabelas novas e índice parcial (integração, CI).

**Saídas:** migration, `clientes/contatos.rs`, `clientes/divergencias.rs`, `.sqlx/`.
**Observabilidade:** span do repositório dentro do span de `run_in_tenant_transaction`; repositório não audita; nenhum telefone/nome em span.
**Bloqueador:** nunca aplicar a `0051` no banco de dev pela máquina local — só pela imagem do deploy.

---

## Etapa F2 — Backend Rust

**Entradas:** F1 mergeada; **G1** (D1–D3 respondidas); fixtures da F0.

**Checklist**
- [ ] `webhook_ingress`: `canonical_event` aceita os nomes reais; `translate_go_contact` normaliza o payload Go.
- [ ] Mover `mascarar_telefone` para crate base reutilizável (sem dependência de `observability`).
- [ ] `worker`: `ContatoDoProvedor` tipado (`serde(alias)`), `Debug` mascarado, lote de 200 → `SincronizarContatosDoWhatsapp`; falha = `warn!` + `Ok(())`.
- [ ] `data_postgres`: rotas da tabela de G2 + `ListarInstanciasParaSincronizar`; `AtualizarPerfilDoContato` vira wrapper com lote de 1.
- [ ] Auditoria via `AuditPort`: `contato.sincronizacao_aplicada` (por lote), `contato.divergencia_detectada`, `contato.criado_da_agenda`, `contato.divergencia_resolvida`, `whatsapp_instance.sincronizacao_agenda_alterada`, `contato.sincronizacao_solicitada` — contexto só com ids e contagens.
- [ ] `infrastructure_messaging`: trait `ContactDirectory`; `infrastructure_evolution`: `listar_contatos` (header `apikey`, `json_do_provedor`, `#[instrument(skip_all, err)]`).
- [ ] Truncar `MessagingProviderError::ProviderApi.body`.
- [ ] `data_whatsapp`: rota `ListarContatosDaInstancia` (token decifrado → `SecretString`).
- [ ] `worker/scheduler.rs`: tarefa `sincronizacao_agenda` sob lock `scheduler:lock:sincronizacao_agenda`, 1 req/s por instância, recuo em 429, expurgo de `contato_evento_aplicado` > 7 d.
- [ ] Testes (CI): `canonical_event` com fixtures; desserialização com as grafias; `Debug` sem JID; handler com `MockAuditPort` sem PII; integração pessoal/cliente/reentrega/fora de ordem/sem opt-in; HTTP fake 200/401/429.

**Saídas:** código nos apps/crates acima; CI verde.
**Observabilidade:** spans `contact.sync.*` com `tenant_id`, `instance_id`, `error_code`; `err` só em `listar_contatos`.
**Bloqueador:** em Windows, setar `SMARTCORE_<SVC>_ENDPOINT=tcp://127.0.0.1:<porta>` para subir serviços (UDS não roda).

---

## Etapa F3 — Contratos gRPC-Web e MCP

**Entradas:** **G2**.

**Checklist (F3.1)**
- [ ] `admin.proto`: `ListMyDivergenciasDeContato`, `ResolverMyDivergenciaDeContato`, `DefinirMySincronizacaoDaAgenda`, `SolicitarMySincronizacaoDaAgenda`; `MyContato` + campos 9/10; sem `map<>`.
- [ ] `grpc_web.rs`: um método tonic concreto por RPC; guard `exigir_autenticado_do_metadata`; `tenant_id` das claims.
- [ ] Regenerar stubs Dart (`api_client`) e Python (`mcp_server/.../contracts`).

**Checklist (F3.2)**
- [ ] Tools `list_divergencias_contato`, `resolver_divergencia_contato`, `definir_sincronizacao_agenda` no molde de `update_contato` (escopo, `dry_run`, `executor.executar`).
- [ ] Mensagens de retorno/erro sem nome nem telefone.
- [ ] `pytest`, `ruff`, `mypy` (CI).

**Saídas:** proto, `grpc_web.rs`, stubs, tools MCP.
**Observabilidade:** auditoria continua só no `data_postgres`; MCP identificado pelo `user_agent` `SmartCoreAssistant-MCP/<tool>`.
**Bloqueador:** RPC no roteador de envelope sem método em `grpc_web.rs` = inalcançável pelo Flutter Web.

---

## Etapa F4 — Flutter (tenant_module)

**Entradas:** **G3** (stubs Dart).

**Checklist**
- [ ] `ContatosPage` com abas Pessoais / Clientes / Divergências (filtro no servidor).
- [ ] `divergencias_cubit.dart` + `divergencia_tile.dart` (Sistema × WhatsApp, três ações, contador na aba).
- [ ] Switch de opt-in na tela de conexões com aviso LGPD (só se D1 = opt-in).
- [ ] Botão "Sincronizar agora".
- [ ] Nenhum contato em `debugPrint`/log; telefone só com 4 dígitos na aba de divergências.
- [ ] Widget tests + teste do cubit (CI); `flutter analyze`.

**Saídas:** telas e testes em `clients/modulos/tenant_module/lib/src/features/contatos/`.
**Observabilidade:** sem evento de auditoria no cliente (intencional).

---

## Etapa F5 — Monitoramento

**Entradas:** F2 mergeada (pontos de emissão).

**Checklist**
- [ ] Contadores em `observability/src/usage_metrics.rs` (OTel 0.24, `.init()`): `smartcore_contato_sync_total{desfecho}`, `..._divergencias_abertas`, `..._polling_duracao_ms` (sem `tenant_id`), `..._provedor_erro_total{status}`.
- [ ] Emitir só a partir de apps (worker, data_postgres), nunca de `infrastructure_*`.
- [ ] `docker/observability/provisioning/dashboards/json/contatos_sync.json`.
- [ ] Alertas em `alerting/rules.yml`: 429 por 15 min; polling parado > 2× intervalo; divergências > 100/24 h por tenant.
- [ ] Smoke no Grafana de dev após o deploy.

**Saídas:** métricas, painel, alertas.
**Observabilidade:** rótulos só `tenant_id` e enums; sem evento de auditoria (intencional).

---

## Fechamento

- [ ] Validar o merge numa branch `ci/` temporária antes da `dev` (push na `dev` deploya sem gate).
- [ ] Atualizar status das fases no plano canônico e rodar `plan syncMarkdown`.
- [ ] Na conclusão: arquivar com `git mv` (canônico para dentro da pasta, pasta para `plans/archive/`).
