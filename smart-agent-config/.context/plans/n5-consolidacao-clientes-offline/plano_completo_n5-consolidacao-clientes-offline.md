# Plano Completo — Fase N5: Consolidação de Clientes + Offline (desktop, FFI, paridade Web)

> **Reestruturado em 2026-07-06** a partir de `doc_dev/planejamento/20-fase-N5-consolidacao-clientes-offline.md`,
> validado contra a central de libs e a doc atual do Cloudflare R2 (CORS).
> **Canônico:** `.context/plans/n5-consolidacao-clientes-offline.md` · **Docs auxiliares:** [info_aux](./info_aux_n5-consolidacao-clientes-offline.md)
> **Objetivo:** pós-estabilização — consolidar o app (F7), entregar o **local engine FFI** com
> cache/offline (F8) e fechar a **paridade Web** (F10). Só entra **após N1–N4 estáveis em produção**.
> **Regra inegociável:** o `DataSource` abstrato garante a troca `RemoteOnly` ↔ `LocalEngineFFI`
> **sem reescrever telas** (LSP).

## Correções aplicadas (reestruturação)

| # | O quê | Por quê | Fonte |
|---|---|---|---|
| 1 | **CORS é obrigatório mesmo com presigned URLs** no R2 (a assinatura autentica, mas o navegador aplica CORS ao GET pré-assinado); `AllowedOrigins` sem path/barra final; incluir `range` em `AllowedHeaders` (seek de áudio/vídeo) e `ETag`/`Content-Type`/`Content-Length` em `ExposeHeaders`; propagação ≤ 30s | O plano base citava "CORS no bucket" sem os gotchas que costumam quebrar mídia na web | developers.cloudflare.com/r2/buckets/cors (2026-07-06) |
| 2 | `cors.json` **versionado no repositório** e aplicado por script (wrangler ou `PutBucketCors` via aws-sdk-s3) | Config de bucket é código (mesmo princípio do lifecycle da N4.3) | idem |
| 3 | Doc local do `flutter_rust_bridge` (2.0.0, verificado 2026-05-31) marcado para **revalidação na fase P do ciclo N5** | N5 é a última fase — quando chegar, a verificação terá ultrapassado a janela de ~90 dias; FFI é o risco-chave da fase | política da central `doc_dev/libs/README.md` |
| 4 | Nenhuma correção de API nas demais libs (sqlite3, path_provider, get_it, melos) | Central ✅ | triagem 2026-07-06 |

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Telas | `login_module`/`admin_module`/`operacional_module` | Já nascidas coladas às features | F7 é **consolidação** |
| `DataSource` abstrato | padrão dos módulos (RemoteOnly) | Portas injetadas por `get_it`; adapter gRPC-Web | F8 pluga `LocalEngineFFI` sem tocar telas |
| `local_engine` | crate ausente | Não existe | F8 cria dual-target |
| Deploy Web | Caddy `/v2/admin` (dev+prod) | Admin já na web same-origin | F10 é incremental |
| Mídia | `infrastructure_storage` (R2, presign) | Presign real pronto | F8 cacheia por hash; F10 precisa de CORS |

## 1. Escopo

**Dentro:** N5.1 consolidação (F7) · N5.2 `local_engine` FFI + mídia local (F8) · N5.3 paridade Web (F10).
**Fora:** novas features de produto — N5 é consolidação.

## 2. Etapas

### N5.1 — Consolidação do app (F7)

1. Navegação coesa (`go_router`) entre login/admin/operacional (+ painel do tenant da N3); guardas por papel consolidadas.
2. Estados padronizados de carga/erro/vazio (reusar `AppErrorView` do endurecimento admin).
3. Acessibilidade e consistência visual (design system) — revisão transversal.
4. Empacotamento desktop: `flutter build windows --release`; versionar packages estáveis (`api_client`, `domain_models`, `design_system_module`) via melos.

**Observabilidade & Auditoria:** logs de UI sem PII; **sem evento de auditoria** (client-side). Tokens só em `flutter_secure_storage`.

**DoD:** app Windows empacotado; navegação/estados consistentes; `.\infra\test-flutter.ps1` limpo.

### N5.2 — Local Engine (FFI) + mídia local (F8) — risco-chave, entregar em incrementos

1. **8.1** crate `local_engine` dual-target (lib Rust + `cdylib`/`staticlib`). **Sem** lógica multi-tenant sensível nem de webhook (princípio inviolável 4). Revalidar doc do `flutter_rust_bridge` (correção #3) e **provar o binding mínimo** antes de cache/sync.
2. **8.2** índice **SQLite** + cache de leitura (fila/thread) para acesso rápido/offline.
3. **8.3** cache de **mídia em disco**: verificação por **hash** (sha2); download único via URL pré-assinada do `infrastructure_storage`/R2; persistência local (path_provider).
4. **8.4** `local_engine_ffi` + **`DataSource: LocalEngineFFI`** injetado por `get_it` no lugar do RemoteOnly — **sem alterar telas** (LSP; se exigir mudar tela, o port vazou e é o port que se corrige).
5. **8.5** fila offline + sincronização (last-write-wins + versionamento; idempotência por id) — ações offline sincronizam ao reconectar.

**Observabilidade & Auditoria:**
- *Logs/trace:* erros de sync/FFI estruturados (tentativa/estado), sem conteúdo de mensagem.
- *Auditoria:* o cliente **não** emite auditoria própria; ações offline são auditadas **no servidor quando sincronizam** (com o ator real).
- *Sanitização:* cache local sem segredo; tokens só em `flutter_secure_storage`; mídia por hash sem metadado sensível em claro.

**DoD:** app Windows opera com cache offline; troca `RemoteOnly`→`LocalEngineFFI` sem tocar telas; mídia baixada uma vez e servida do disco; ações offline sincronizam sem perda; sem segredo no cache.

### N5.3 — Paridade Web completa (F10)

1. **10.1** Admin já em `/v2/admin` (RemoteOnly, gRPC-Web). Entregar o app **operacional/tenant** na web (reusa packages; **sem** `local_engine_ffi`), mesmo padrão Caddy same-origin do `deploy-admin-web`.
2. **10.2** Mídia na Web via presigned URL do R2 com **CORS no bucket** (correções #1–#2): `cors.json` versionado, `AllowedOrigins` = origem exata do app (`scheme://host[:port]`, sem path), `AllowedMethods: [GET, HEAD]`, `AllowedHeaders: [range]`, `ExposeHeaders: [ETag, Content-Type, Content-Length]`, `MaxAgeSeconds: 3600`; aplicar via wrangler/`PutBucketCors`; teste de carregamento cross-origin (incl. seek de áudio).

**Observabilidade & Auditoria:** logs de carregamento de mídia com status, **sem a URL assinada completa** (a assinatura é credencial temporária); **sem evento de auditoria** (exibição).

**DoD:** paridade RemoteOnly na web validada; mídia carrega via presign com CORS correto (incl. range requests); `.\infra\test-flutter.ps1` limpo.

## 3. SOLID / Ports & Adapters

- **F8 é a prova final do princípio 5:** o `DataSource` abstrato permite plugar `LocalEngineFFI` por `get_it` sem reescrita — se a troca exigir mudança de tela, corrigir o port, não a tela.
- `local_engine` depende de abstrações de storage/index; nada de infra multi-tenant.

## 4. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Dual-target FFI instável | Atraso alto | Incrementos 8.1→8.5; binding mínimo provado primeiro; doc da lib revalidada na fase P |
| Conflitos de sync offline | Perda/duplicação | Last-write-wins + versionamento; auditoria server-side no sync; idempotência por id |
| Port vazando ao plugar FFI | Reescrita de telas | Corrigir o `DataSource`, não a tela |
| Disco do servidor (build web/FFI) | Falha de build | Limpeza periódica; `flutter precache` seletivo (risco visto no deploy-admin-web) |
| CORS de mídia mal configurado | Mídia não carrega | `cors.json` versionado; gotchas da correção #1; teste cross-origin com range |

## 5. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N5** | Escopo de consolidação + incrementos FFI + revalidar flutter_rust_bridge | Aprovar dual-target + estratégia de sync + paridade web | F7 consolida; F8 FFI/offline; F10 paridade web | `test-flutter.ps1`: offline + troca de DataSource + paridade | App empacotado; offline sem perda; web com CORS |

---

## Encerramento do backlog N1–N5

Concluída a N5, o produto tem: MVP endurecido (N1), IA plugada (N2), autonomia do tenant (N3),
prontidão comercial (N4) e clientes consolidados com offline/web (N5). Novas frentes entram
como ciclos PREVC próprios, canonizados via `/plan-restructuring`.
