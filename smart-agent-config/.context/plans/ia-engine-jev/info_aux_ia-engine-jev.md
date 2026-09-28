# Documentação Auxiliar — `ia_engine_jev` (decisões pelo Jev, geração pela LLM)

> Gerado em: 2026-09-28
> Plano canônico: `.context/plans/ia-engine-jev.md`
> Plano completo: `.context/plans/ia-engine-jev/plano_completo_ia-engine-jev.md`
> Origem (histórico): `doc_dev/planejamento/38-plano-ia-engine-jev.md` e
> `doc_dev/planejamento/37-estudo-ia-engine-jev.md`
>
> **Nota de método:** todas as libs estavam na central local com verificação recente
> (triagem abaixo), e a documentação da TypeSafe foi lida por completo em 2026-09-27 e
> reconferida em 2026-09-28 (sem mudanças). Por isso não houve rodada de Context7 nem de
> subagentes de coleta; a única checagem nova foi o PyPI do `typesafe-sdk`, que trouxe as
> dependências transitivas (§1.2).

---

## 0. Triagem da central local (`doc_dev/libs/`)

| Lib | Stack | Doc local | Estado | Observação |
|---|---|---|---|---|
| `typesafe-sdk` 0.7.2 | python | `python/typesafe_sdk.md` (2026-09-28) | **ATUALIZADA nesta rodada** | status → EM_HOMOLOGACAO; chave global; dependências |
| `pydantic` 2.13.5 / `pydantic-settings` 2.15 | python | `python/pydantic.md` (2026-09-10) | USAR LOCAL | o SDK exige ≥ 2.12 — sem conflito |
| `grpcio` 1.83.1 | python | `python/grpcio.md` (2026-09-06) | USAR LOCAL | servidor assíncrono igual ao do `ia_engine` |
| `opentelemetry` 1.x | python | `python/opentelemetry.md` (2026-07-06) | USAR LOCAL | molde já em uso no `telemetry.py`; nada novo de API |
| `loguru` 0.7.x | python | `python/loguru.md` (2026-05-31) | USAR LOCAL | idem |
| `langchain` ≥ 1.0 (+ provedores) | python | `python/langchain.md` | USAR LOCAL | só geração de texto e extração `livre` |
| `mcp` 2.1.1 | python | `python/mcp.md` (2026-09-06) | USAR LOCAL | ferramentas novas seguem o padrão do `mcp_server` |
| `sqlx`, `tokio`, `serde`, `secrecy`, `tracing` | rust | `rust/*.md` | USAR LOCAL | só tabelas/colunas/rotas novas no molde existente |

---

## 1. Libs Python

### 1.1 `typesafe-sdk` 0.7.2 — fonte: `doc_dev/libs/python/typesafe_sdk.md` (2026-09-28)

- Cliente assíncrono: `AsyncTypeSafeClient(api_key=..., model="jev-1.13.0")`, usado como
  `async with`; chamada única `await client.system_one(state=..., questions={...})`.
- Primitivas: `Choice(instructions, criteria)`, `Noul(instructions, criteria=NoulCriteria(true=, false=))`,
  `Score(instructions, criteria=[níveis])`.
- Resposta: `r.choices[id].choice/.probabilities/.confidence`, `r.nouls[id].noul`,
  `r.scores[id].score/.probabilities/.confidence`, `r.usage.input_tokens`, `r.model`.
- Retry: `RetryPolicy(max_retries=, backoff_initial=, backoff_max=, timeout=)` — o SDK já
  faz backoff em 429/529/5xx e respeita `retry-after`. No caminho da conversa, orçamento
  total ~2 s.
- Exceções (base `TypeSafeError`): `TypeSafeAuthenticationError` (401),
  `TypeSafePermissionDeniedError`, `TypeSafeBadRequestError`,
  `TypeSafeUnprocessableEntityError` (422 = pergunta malformada → bug nosso, não retry),
  `TypeSafeRateLimitError` (429), `TypeSafeInternalServerError`,
  `TypeSafeAPIConnectionError`, `TypeSafeAPITimeoutError`,
  `TypeSafeAPIResponseValidationError`. `TypeSafeAPIError` traz `status`, `body`,
  `request_id` — o `request_id` vai para o span, o `body` **não** vai para log (pode ecoar
  o `state`).
- O SDK também lê `TYPESAFE_API_KEY` do ambiente: o container **não** deve ter essa
  variável; a chave entra só por `api_key=` a partir da config publicada no Redis.

### 1.2 Dependências transitivas do SDK (PyPI JSON, 2026-09-28)

`httpx2>=2.0.0` (pacote distinto do `httpx`; última 2.13.1), `pydantic>=2.12.0`,
`pydantic-core>=2.41.1`, `tenacity>=9.0.0`, `typing-extensions>=4.13.0`; extra `http2` →
`httpx2[http2]`. `requires_python >= 3.10` (o projeto usa ≥ 3.13).

### 1.3 `pydantic` — fonte: `doc_dev/libs/python/pydantic.md` (2026-09-10)

Continua dependência (SDK, `config/models.py`, `pydantic-settings`). Sai do domínio e de
toda chamada de modelo no `ia_engine_jev` (ver plano completo §5).

### 1.4 `grpcio`, `opentelemetry`, `loguru` — fontes locais

Reaproveitados do `ia_engine` sem mudança de API: `grpc.aio.server`, health checking,
`opentelemetry-instrumentation-grpc` para o span por RPC, log JSON do `telemetry.py`.

---

## 2. Libs Rust

Nenhuma lib nova. As mudanças são tabelas, colunas e rotas no molde existente:
`sqlx` (query de tempo de execução quando evita regenerar o cache offline — padrão já usado
no `tenants/config.rs`), `secrecy::SecretString` para a chave, `tracing` com
`#[instrument(skip_all)]` nos repositórios de tenant.

---

## 3. Serviços externos

### 3.1 TypeSafe System One (Jev) — `https://api.typesafe.ai`

- **Autenticação:** chave de API da **conta da plataforma** (uma para todos os tenants).
  Integração só via SDK — não escrever cliente HTTP próprio.
- **Modelo:** fixar `jev-1.13.0`; registrar o `model` devolvido em cada resposta.
- **Limites:** 1.200 req/min e 250 mil tokens/s **por conta** (dinâmicos); 64k tokens por
  requisição, 32k para `state` + a maior pergunta; `Choice` até 255 opções (confiável até
  ~240); `Score` de 2 a 10 níveis.
- **Preço:** US$ 0,042 por milhão de tokens de entrada; saída grátis.
- **Idioma:** inglês é o principal; português "funciona com acurácia menor" → J0 decide.
- **Jaggedness (jev-1.13):** leitura literal, sem conta/contagem/datas, `state` com lixo
  derruba acurácia, conteúdo adversarial move a resposta, limiar de `Noul` ≠ confiança de
  `Choice`, `score` não reconstrói números entre níveis.
- **Dados:** não treina com as requisições; ZDR só no plano enterprise → TypeSafe como
  suboperador no termo/DPA do tenant.
- **Cookbooks relevantes** (docs.typesafe.ai): roteamento/function calling, classificação
  hierárquica (catálogo > 240), extração por candidatos pré-analisados, rerank/passagens de
  RAG (um par pergunta–trecho por requisição), citation check (resposta apoiada).

---

## 4. Integração com o que já existe (levantado no código em 2026-09-28)

### 4.1 Onde fica a chave — **configuração geral (CoreSettings)**

- Tabela global `settings_manager_coresettings` (`key`, `value`, `encrypted`,
  `description`; sem RLS) — migração `0009_settings_manager.sql` já semeia
  `OPENAI_API_KEY`, `GROQ_API_KEY`, `GOOGLE_API_KEY` vazias.
- Leitura: `infrastructure_postgres::tenants::settings::load_all_settings` decifra as linhas
  `encrypted` (formato `ct_b64:nonce_b64:tag_b64`); chave ilegível é omitida com WARN só com
  o nome.
- Resolução: `tenants/config.rs::resolve_runtime_config` → `RuntimeConfig`
  (`config_cache.rs`) com `resolve_api_key(<local>, <CORE_KEY>)` (tenant > global).
- Publicação: `data_postgres/src/config_publisher.rs` grava `tenant:config:<uuid>` no Redis
  (`openai_api_key`, … expostos com `expose_secret()` só nesse ponto); o `ia_engine` lê em
  `config/models.py::RuntimeConfig`.
- Edição: painel do superusuário, `admin_module/features/core_settings` (campo com
  `obscureText` quando `encrypted`; valor cifrado não é copiado na exportação) →
  `UpsertCoreSetting` no `data_postgres`, que audita `core_setting_upserted` com
  `{key, encrypted}` (sem valor) e invalida o cache global.

**Consequência para o plano:** a `TYPESAFE_API_KEY` entra como mais uma linha dessa tabela
(cifrada), editada na mesma tela; **sem** override por tenant (a `resolve_api_key` não é
usada para ela — lê só o global). Nada de tela, RPC ou evento de auditoria novo para a chave.

### 4.2 Auditoria

- `AuditPort` (`data_postgres`, handlers de config) e `AuditLogger` (worker, eventos de
  conversa) → Redis `security.audit` → `audit_log`. Sem conteúdo de mensagem; MCP
  identificado por `user_agent` `SmartCoreAssistant-MCP/<tool>`.
- Eventos existentes que o plano estende: `atendimento.transferido_por_ia`,
  `bot.respondeu`, `core_setting_upserted`.

### 4.3 Telemetria

- `ia_engine/src/ia_engine/telemetry.py`: span por RPC, log JSON com `trace_id`, métricas
  sem tenant como rótulo. Mesmo molde no `ia_engine_jev`.

### 4.4 MCP e gRPC-Web

- RPC novo só é alcançável pelo Flutter Web com método concreto no `AdminService`
  (`grpc_web.rs`) e entrada no `rbac.rs` (fail-closed).
- Proto sem `map<>` (conversor proto→flatbuffers): usar `repeated` de pares.

---

## 5. Grupo C — observabilidade e auditoria por etapa (levantamento)

| Etapa | Log/trace | Auditoria | Sanitização |
|---|---|---|---|
| Chave na config geral | WARN de chave ilegível (só o nome) | `core_setting_upserted` (existente) | `SecretString` no Rust; `expose_secret` só no publisher; nunca em log/span |
| Cliente Jev (Python) | span `jev.requisicao` (etapa, nº de perguntas, tokens, modelo, duração, status, request_id) | sem evento de auditoria (chamada técnica) | sem `state`, sem `body` de erro, sem chave |
| Análise | span `ia.analise` + motor/modelo | sem evento novo (análise já anexada à mensagem) | só contagens e ids |
| Transferência | span `ia.responder` + motivo | `atendimento.transferido_por_ia` estendido | motivo = nome da regra ou do sinal; sem texto |
| Regras do tenant | spans dos handlers CRUD | `transferencia_regra.*`, `transferencia_sinais.alterados` | condição e exemplos são config do tenant, não PII — mesmo assim fora dos logs |
| Registro das decisões | — | `oraculo_decisao_ia` (não é auditoria) | sem texto; retenção 90 dias |
| Troca de motor | span do handler | `tenant_config.motor_alterado` | — |

## 6. Notas gerais

- Não há como rodar testes nesta máquina: todo teste roda na CI; a J0 roda no VPS de dev
  (container efêmero na rede do stack), lendo a chave da config publicada no Redis.
- `jev-latest` muda sozinho — qualquer troca de versão repete a J0.
