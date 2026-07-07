# Fase N5 — Consolidação de Clientes + Offline (desktop, FFI, paridade Web)

> **Status:** Plano de execução — criado em **2026-07-06**. Quinta e última fase do
> backlog pós-MVP (N1–N5) — ver [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).
> **Corresponde às Fases 7, 8 e 10 (F7/F8/F10)** do mapa de fases.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** pós-estabilização — **consolidar** o app (navegação/estados/
> empacotamento desktop), entregar o **local engine (FFI)** com cache/offline e
> fechar a **paridade Web**. Só entra **após N1–N4 estáveis em produção**.
> **Regra inegociável:** o `DataSource` abstrato (desde a F6) garante a troca
> `RemoteOnly` ↔ `LocalEngineFFI` **sem reescrever telas**; observabilidade transversal.

---

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Telas | `login_module`/`admin_module`/`operacional_module` | **Já nascidas coladas às features** (login, admin, fila/Kanban/chat). | F7 é **consolidação**, não construção. |
| `DataSource` abstrato | padrão dos módulos (RemoteOnly hoje) | Portas abstratas injetadas por `get_it`; adapter gRPC-Web. | F8 pluga `LocalEngineFFI` **sem tocar telas** (LSP). |
| `local_engine` | crate ausente | Não existe. | F8 cria o crate dual-target. |
| Deploy Web | Caddy `/v2/admin` (dev+prod) | Admin **já roda na web** same-origin (plano `deploy-admin-web`). | F10 avalia app do **tenant/operacional** standalone. |
| Mídia | `infrastructure_storage` (R2, presign) | Presign real pronto. | F8 cacheia mídia por hash via URL pré-assinada. |

> **Conclusão:** F7 é refino; **F8 (FFI) é o risco-chave** (dual-target, sync); F10 é
> incremental porque o admin já está na web.

---

## 1. Escopo

### Dentro do escopo
- **N5.1** Consolidação do app (F7): navegação/estados/acessibilidade + empacotamento Windows.
- **N5.2** `local_engine` FFI (F8): dual-target, índice SQLite, cache de mídia, `DataSource: LocalEngineFFI`, fila offline + sync.
- **N5.3** Paridade Web completa (F10): app do tenant/operacional na web + CORS de mídia.

### Fora do escopo
- Novas features de produto — N5 é consolidação, não expansão funcional.

---

## 2. Contrato de observabilidade (DoD transversal)

- **Telemetria:** logs de UI sem PII; erros de sync/FFI logados de forma estruturada
  (tentativa/estado), sem conteúdo de mensagem.
- **Auditoria:** o cliente **não** emite auditoria própria (server-side). Ações do
  modo offline são auditadas quando sincronizam ao servidor.
- **Sanitização:** cache local **não** guarda segredo; tokens só em `flutter_secure_storage`;
  mídia cacheada por hash, sem metadado sensível em claro.

---

## 3. N5.1 — Consolidação do app (F7)

**Tarefas**
1. **Navegação** coesa (`go_router`) entre login/admin/operacional (+ painel do tenant
   da N3); guardas por papel consolidadas.
2. **Estados** padronizados de carga/erro/vazio em todas as telas (reusar `AppErrorView`
   já adotado no endurecimento admin).
3. **Acessibilidade** e consistência visual (design system) — revisão transversal.
4. **Empacotamento** desktop: `flutter build windows --release`; versionar packages
   estáveis (`api_client`, `domain_models`, `design_system_module`).

**DoD:** app Windows empacotado; navegação/estados consistentes; `flutter analyze`
limpo via `.\infra\test-flutter.ps1`.

---

## 4. N5.2 — Local Engine (FFI) + mídia local (F8)

**Risco-chave:** dual-target FFI. Entregar em incrementos.

**Tarefas**
1. **8.1** `local_engine` dual-target (lib Rust + `cdylib`/`staticlib`). **Sem** lógica
   multi-tenant sensível nem de webhook (princípio inviolável 4).
2. **8.2** índice **SQLite** + cache de dados de leitura (fila/thread) para acesso rápido/offline.
3. **8.3** cache de **mídia em disco**: verificação por **hash**; download único via
   **URL pré-assinada** do `infrastructure_storage`/R2; persistência local.
4. **8.4** `local_engine_ffi` + **`DataSource: LocalEngineFFI`** injetado por `get_it` no
   lugar do RemoteOnly — **sem alterar as telas** (LSP; validação do port do dia 1).
5. **8.5** **fila offline** + sincronização (last-write-wins + versionamento) — ações do
   atendente feitas offline sincronizam ao reconectar, auditadas server-side no sync.

**DoD:** app Windows opera com cache offline; troca `RemoteOnly`→`LocalEngineFFI` sem
tocar telas; mídia baixada uma vez e servida do disco; ações offline sincronizam sem
perda; sem segredo no cache.

---

## 5. N5.3 — Paridade Web completa (F10)

**Tarefas**
1. **10.1** O admin já roda em `/v2/admin` (RemoteOnly, gRPC-Web). Avaliar/entregar o
   app **operacional/tenant** standalone na web (reusa packages; **sem** `local_engine_ffi`).
2. **10.2** Mídia na Web: servida por **URL pré-assinada** do R2 com **CORS** no bucket
   (ver [08-infraestrutura-storage.md §7.5](./08-infraestrutura-storage.md)).

**DoD:** paridade de features RemoteOnly na web validada; mídia carrega via presign com
CORS correto; `flutter analyze` limpo.

---

## 6. SOLID / Ports & Adapters

- **F8 é a prova final do princípio 5:** o `DataSource` abstrato (adotado desde o
  `login_module`) permite plugar `LocalEngineFFI` por `get_it` **sem reescrita** — se a
  troca exigir mudança de tela, o port estava vazando e deve ser corrigido.
- `local_engine` depende de abstrações de storage/index; nada de infra multi-tenant.

---

## 7. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Dual-target FFI (build/binding) instável | Atraso alto | Incrementos 8.1→8.5; provar o binding mínimo antes do cache/sync |
| Conflitos de sync offline | Perda/duplicação de dado | Last-write-wins + versionamento; auditoria server-side no sync; idempotência por id |
| Port vazando ao plugar FFI | Reescrita de telas | Se a troca exigir mudar tela, corrigir o `DataSource` (não a tela) |
| Disco do servidor (build web/FFI) | Falha de build | Limpeza periódica; `flutter precache` seletivo (risco já visto no deploy-admin-web) |
| CORS de mídia mal configurado | Mídia não carrega na web | Config de CORS versionada no bucket; teste de carregamento cross-origin |

---

## 8. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N5** | Escopo de consolidação + incrementos FFI | Aprovar dual-target + estratégia de sync + paridade web | F7 consolida; F8 FFI/offline; F10 paridade web | `test-flutter.ps1`: offline + troca de DataSource + paridade | App empacotado; offline sem perda; web com CORS |

---

## Encerramento do backlog N1–N5

Concluída a N5, o produto tem: MVP operacional endurecido (N1), IA plugada (N2),
autonomia do tenant (N3), prontidão comercial (N4) e clientes consolidados com
offline/web (N5). Novas frentes entram como ciclos PREVC próprios, sempre aterrados
no código real e canonizados via `/plan-restructuring` em `.context/plans/`.

*Plano aterrado no `DataSource` abstrato já em uso, no deploy web existente e no
storage R2 com presign. Pronto para `/plan-restructuring`.*
