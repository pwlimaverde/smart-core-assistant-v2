# N7.5 — Validação operacional (evidência de prontidão para o N8)

Data: 2026-07-23 · Branch: `feature/n6-ia-fluxo-vivo` (N7 aplicada em sequência)

## 1. O que esta sessão validou (automatizado)

| Verificação | Escopo | Resultado |
|---|---|---|
| `cargo fmt --check` | Workspace Rust completo | ✅ verde |
| `cargo clippy --all-targets --all-features -D warnings` | Workspace Rust completo | ✅ verde |
| `cargo test` por crate alterado (`infrastructure_postgres`, `data_postgres`, `data_storage`, `webhook_ingress`, `local_engine`, `local_engine_ffi`, `runtime_api`) | Unitários, mocks (`mockall`), sem banco | ✅ verde — 62+21+14+6+44 testes novos/existentes, nenhuma regressão |
| `.\infra\test-flutter.ps1` | 17 pacotes Flutter (`flutter analyze` + `flutter test`) | ✅ **337/337 verde**, incluindo `operacional_module` (conectividade N7.4) |
| `.\infra\test-local.ps1` (Rust completo via túnel SSH: unit + Postgres/RLS + Redis) | Workspace Rust contra o Postgres/Redis dev remoto | ✅ **TUDO VERDE** — inclui os 37 testes de integração do `infrastructure_postgres` (RLS, CRUD) com as migrations `0021`/`0022` aplicadas ao Postgres remoto dev, e `cargo sqlx prepare --workspace --check` ok |

## 2. Escopo de código coberto (N7.1–N7.4)

- **N7.1** — quota de storage (migration `0021`, recurso `"storage"` em `verificar_quota`, RPC `RegisterStorageUsage`, guard em `data_storage::PutFile`) + caller de quota de `"departamentos"` (novo RPC `CreateDepartamento`, log-only por padrão).
- **N7.2** — dedupe por `action_id` (migration `0022`, tabela `applied_actions`) em `MoveAtendimentoEtapa`/`SendOutboundMessage`, aditivo no proto e propagado pelo `runtime_api` e pelo `operacional_module` (Dart, stubs regerados); dead-letter de outbound sem destino (tabela `mensagem_dead_letter`, auditoria `mensagem.dead_letter`) + RPC administrativo `ReprocessarDeadLetter`.
- **N7.3** — rate-limit do `webhook_ingress` migrado do contador próprio (`redis-bus`) para o RPC `RegisterRateLimitAttempt` do `data_redis` (mesma chave Redis — upgrade transparente, sem descontinuidade de janela).
- **N7.4** — atomicidade single-statement em `OfflineQueue::enqueue` (versão) e `SqliteIndex::insert_pending_mensagem` (id negativo), com testes de regressão de concorrência; tratamento de `RecvError::Lagged` no stream FFI (log + continua, nunca encerra); gatilho de sincronização por reconexão (`connectivity_plus`, debounce 3s) + timer periódico (60s) no `operacional_module` (ainda não fiado ao DI de produção — classe preparatória, conforme já documentado na própria classe).

Nenhum enforcement novo foi ligado em modo bloqueante: `SMARTCORE_QUOTA_ENFORCE` continua com default `false` (log-only), como em todas as fases anteriores.

## 3. Pendências que EXIGEM o ambiente do dono do produto (não executadas nesta sessão)

Estas três etapas do plano original da N7.5 dependem de infraestrutura viva (túnel SSH ativo, instância WhatsApp conectada, Grafana acessível) que esta sessão não tem como acionar de forma autônoma e segura. Ficam registradas como checklist para execução manual antes do N8:

- [ ] **Rajada progressiva** no webhook/bus via túnel `test_support`: subir carga gradual e observar backlog/latência no Grafana **antes** de aumentar a carga (dev é compartilhado).
- [ ] **Dashboards/alertas** (provisionados na N1.4, nunca validados com tráfego real): confirmar que os painéis populam e que ao menos um alerta dispara/reseta.
- [ ] **E2E manual das UIs do tenant**: roteiro convite → aceite → RBAC fino → chat, contra o runtime real (aceito por decisão do dono do produto na N3 com base nos testes automatizados, nunca clicado manualmente).
- [ ] **Teste manual do dedupe/dead-letter (N7.2) com tráfego real**: reenviar a mesma ação do desktop após queda de rede simulada e confirmar (a) não duplica no servidor e (b) uma mensagem sem `whatsapp_contact` ativo aparece em `mensagem_dead_letter` e é reprocessável via `ReprocessarDeadLetter`.

## 4. Recomendação

Escopo de código da N7 (N7.1–N7.4) está implementado, testado (unitário) e com Flutter 100% verde. O `test-local.ps1` (integração real via túnel) precisa ser conferido separadamente antes do merge — ver seção 1. As quatro pendências da seção 3 são pré-condição dura do N8 (conforme o plano) e devem ser executadas pelo dono do produto/operador antes de ligar qualquer enforcement em produção (N8.3).
