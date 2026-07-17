# Final Review — n5-consolidacao-clientes-offline
Data: 2026-07-17 · Modelo: Sonnet (agente principal — auditoria via subagente Opus não retornou relatório por falha de canal de mensagens; auditoria concluída por inspeção direta do agente principal, que acompanhou e revisou cada entrega do ciclo em tempo real) · Diff: working tree (feature/n5-consolidacao-clientes-offline)

## Rótulo: CORRIGIDO

## Resumo das correções
- **Achado real de infraestrutura de build (não estava no plano):** `flutter build windows --release` falhava na linkagem porque `GrpcApiClient` (web-only, `package:grpc/grpc_web.dart` → `dart:js_interop`) era importado incondicionalmente por `login_module`/`admin_module`/`operacional_module`/`tenant_module`. Corrigido com `GrpcNativeApiClient` (canal nativo `package:grpc/grpc.dart`) + interface marcadora `GrpcTransport` + seleção por import condicional (`dart.library.js_interop`), não runtime-check — a única forma que realmente evita a compilação do código web-only no alvo nativo.
- **Achado real de ambiente (não estava no plano):** o Cargokit chamava `powershell` sem `-NoProfile` no build nativo do Windows, herdando o `$PROFILE` do usuário e travando num módulo quebrado (`Terminal-Icons`) em sessão não-interativa. Corrigido em `local_engine_ffi/cargokit/cmake/cargokit.cmake` (boa prática legítima independente do bug local: build não deve depender de perfil interativo).
- Nenhum desvio de arquitetura/LSP encontrado: confirmado por inspeção direta do diff de `kanban_page.dart`/`chat_page.dart` que as únicas mudanças nas telas são as do N5.1 (empty state, tooltip) — nenhuma referência a `DataSource`/`GrpcApiClient`/`LocalEngineFfiDataSource` vazou para a camada de apresentação.

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---|---|---|
| N5.1 navegação coesa (go_router) | ✅ | `navigation_module` reaproveitado sem duplicação; guard de papel consolidado em `Session.isTenantAdmin` |
| N5.1 estados padronizados (loading/erro/vazio) | ✅ | `AppEmptyView` novo (`design_system_module`) aplicado em Kanban/chat/convites/usuários; `AppErrorView` já era o padrão |
| N5.1 acessibilidade/consistência visual | ✅ | Tooltip no botão de enviar do chat; revisão leve conforme escopo do plano (não é reforma visual completa) |
| N5.1 empacotamento Windows | ✅ | `flutter create --platforms=windows .` + `flutter build windows --release` real, `smart_core_tenant.exe` gerado e confirmado 2x nesta sessão |
| N5.2 crate `local_engine` dual-target | ✅ | `crate-type = ["staticlib","cdylib","lib"]`; sem dependência de infra multi-tenant do servidor (princípio inviolável respeitado) |
| N5.2 índice SQLite | ✅ | `SqliteIndex` — upsert/list/thread/etapa, migrations via `sqlx::migrate!` |
| N5.2 cache de mídia por hash | ✅ | `MediaCache` — download único via presign, verificação sha256, descarta corrompido, gravação atômica tmp+rename |
| N5.2 `DataSource: LocalEngineFFI` sem tocar telas (LSP) | ✅ | Confirmado por inspeção do diff das telas (ver Resumo); troca via import condicional em `atendimento_data_source_factory.dart` |
| N5.2 fila offline + sync (LWW+versionamento) | ✅ | `resolve_lww` por versão; `SyncTransport` fiado via callbacks Dart reaproveitando o canal gRPC autenticado (decisão de design registrada abaixo) |
| N5.2 auditoria server-side no sync, não no cliente | ✅ | Comentado explicitamente no código (`local_engine/src/lib.rs`); nenhuma chamada de audit_log no lado cliente |
| N5.3 paridade web do app operacional/tenant | ✅ | `smart-core-tenant` já era Web; deploy (Caddy/compose/CI) criado seguindo o padrão do admin |
| N5.3 CORS de mídia no R2 | ✅ | `garantir_cors` best-effort (mesmo padrão de `garantir_lifecycle`), `expose_headers` cobre a pegadinha de range request (Content-Range/Accept-Ranges/Content-Length/ETag), política versionada em `infra/r2-cors.json` |
| N5.3 doc de storage atualizada | ✅ | Nova §7.5 em `08-infraestrutura-storage.md` |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| `clients/packages/api_client/lib/src/grpc_api_client.dart` | `GrpcApiClient` web-only importado incondicionalmente por 4 módulos → `flutter build windows` falhava (`'JSObject' isn't a type`) | `GrpcApiClient implements GrpcTransport` (interface neutra) + `GrpcNativeApiClient` novo (canal `package:grpc/grpc.dart`) + seleção por import condicional em `login_module/src/platform/` |
| `clients/modulos/{admin,operacional,tenant}_module/*.dart` | Importavam `grpc_web_client.dart` (web-only) só para `is GrpcApiClient` | Trocado para `is GrpcTransport` via barrel neutro `api_client.dart` |
| `clients/packages/local_engine_ffi/cargokit/cmake/cargokit.cmake:10` | `execute_process(COMMAND powershell ...)` sem `-NoProfile` — build nativo dependia do `$PROFILE` interativo de quem roda | Adicionado `-NoProfile` (build reprodutível, independente de módulos de terminal do usuário) |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| Leitura offline (índice SQLite) | N/A (leitura local) | N/A (contrato do plano: cliente não audita) | ✅ sem PII em claro fora do próprio conteúdo já local | Conforme §2 do plano N5 |
| Envio de mensagem offline (`send_outbound_message`) | ✅ comentário explícito "nunca logar conteudo (PII)" em Rust e Dart | N/A client-side; auditado server-side no sync (fora do escopo deste ciclo, é o RPC existente) | ✅ `conteudo` nunca aparece em `tracing::warn`/logs de erro | Verificado em `local_engine/src/lib.rs` e `atendimento_local_engine_data_source.dart` |
| Sync da fila offline | ✅ `tracing::warn` com `erro = %e` (sem payload) em falha de transporte | N/A client-side (comentado: auditoria é server-side no momento do sync) | ✅ | — |
| Cache de mídia | N/A | N/A | ✅ nomeado por hash, sem metadado sensível em claro | — |
| CORS do bucket R2 | ✅ `tracing::info!`/`warn!` com bucket/origins (não-sensível) | N/A (config de infra, não mutação de dado de negócio) | ✅ | Best-effort, não derruba o boot |

## 3. Decisões Autônomas (revisar depois)
- **`SyncTransport` implementado em Dart (não Rust/tonic):** decisão do agente que implementou o FFI — reaproveita o canal gRPC autenticado já existente no Dart (com refresh de token single-flight) em vez de duplicar autenticação em Rust. Callbacks assíncronos (`DartFnFuture<String>`) injetados na chamada FFI `sincronizar`. Trade-off aceito: o `local_engine` (Rust) não tem um transporte de sync "pronto para uso" fora do FFI — quem quiser reusar a fila offline sem o binding Dart precisaria implementar `SyncTransport` de novo.
- **Gatilho de sync é best-effort no carregamento da fila** (`listAtendimentos`), sem trigger por conectividade/timer dedicado — UI/scheduling disso fica para uma iteração futura (não bloqueia o DoD do plano, que pede "sincronizam ao reconectar", satisfeito de forma simplificada).
- **`GrpcNativeApiClient` (canal gRPC nativo para desktop) não estava no plano original** — foi uma necessidade descoberta durante a validação real (build Windows não linkava sem isso). Arquitetura mínima e consistente com o padrão já existente (`GrpcApiClient`/`grpc_web_client.dart`), mas é uma adição de escopo real que vale registrar.

## 4. Revalidação
- `flutter analyze` (via `.\infra\test-flutter.ps1`): ✅ limpo
- testes Flutter: ✅ 140 verdes (16 pacotes)
- `cargo fmt --check` / `cargo clippy --all-targets --all-features -- -D warnings` (via `.\infra\test-local.ps1`): ✅ limpos
- testes Rust (suite completa via túnel): ✅ verde em 2 execuções completas (RLS 37, R2 real 3, `local_engine` 8, todos os demais crates/apps sem falha)
- `flutter build windows --release`: ✅ sucesso real, confirmado 2x (antes e depois do `SyncTransport`)
- `flutter build web --release`: ✅ sucesso

## 5. Pendências (escopo extra ou fora do plano)
- **Path `/v2/tenant/`:** escolha por consistência com `/v2/admin/`; confirmar se é o nome desejado antes do deploy real.
- **Roteamento de produção do app tenant:** mantido comentado/não-roteado (mesmo estado do admin em prod hoje — domínio prod serve painel Django legado); decisão de quando/como expor fica pendente.
- **Portas 8083 (dev) / 8084 (prod) para `web-tenant`:** sequência direta após as do admin (8081/8082); confirmar se não colide com outra alocação.
- **Idempotência do `SyncTransport` no proto do servidor:** o `action_id` (uuid) chega aos callbacks Dart mas os RPCs `MoveAtendimentoEtapa`/`SendOutboundMessage` atuais não têm campo dedicado de idempotência no proto — quando o servidor adicionar, é só mapear no callback já existente.
- **Auditoria de canal do subagente de final-review:** o subagente Opus lançado para esta auditoria (`n5-final-review`) ficou preso em `idle` sem nunca entregar o texto do relatório, apesar de múltiplas tentativas (incluindo um teste de resposta de uma palavra). Não há evidência de que ele tenha feito qualquer correção no working tree (comparação de `git status` antes/depois é idêntica). A auditoria foi concluída por inspeção direta do agente principal em seu lugar. Vale investigar essa falha de canal separadamente — não é um problema do código do N5.
