# Documentação Auxiliar — N10 IA Analítica

> Gerado em: 2026-08-09
> Plano canônico: `.context/plans/n10-ia-analitica.md`
> Plano completo: `.context/plans/n10-ia-analitica/plano_completo_n10-ia-analitica.md`

---

## Libs (triagem da etapa 2a: todas **USAR LOCAL** — central atualizada)

| Lib | Versão | Doc local (verificação) | Uso nesta fase |
|---|---|---|---|
| `langchain` | 1.0+ | `doc_dev/libs/python/langchain.md` (2026-07-06) | schema dinâmico de structured output no `Analyse`; loaders da E5 |
| **`document_loaders`** | — | `doc_dev/libs/python/document_loaders.md` (2026-05-31) | **E5**: pypdf, python-docx, pillow — extração de texto |
| `pydantic` | 2.9+ | `doc_dev/libs/python/pydantic.md` | `create_model` do schema dinâmico (já usado no `analyse_datasource`) |
| `pgvector` | 0.4 (rust) / py | `rust/pgvector.md`, `python/pgvector.md` | vetorização do material extraído |
| `grpcio` | 1.68+ | `python/grpcio.md` | RPC novo `ExtrairTextoDocumento` |
| `sqlx` | 0.9 | `rust/sqlx.md` | migrations de `origem` (etiqueta) e colunas novas |

**Dependências novas no `ia_engine/pyproject.toml`** (E5): `pypdf`, `docx2txt`,
`openpyxl`. O `langchain-community` traz os wrappers de loader. Formatos-alvo
(paridade com a v1): `.pdf`, `.doc`, `.docx`, `.txt`, `.xls`, `.xlsx`, `.csv`.

> Nenhuma chamada ao Context7 foi necessária nesta fase — a central cobre tudo,
> incluindo `document_loaders.md`, que existe justamente porque a v1 usava esses
> loaders.

---

## Fontes internas

| Item | Onde |
|---|---|
| `Analyse` — proto | `contracts/schemas/ai/ai_engine.proto:68-88` |
| `Analyse` — datasource (schema dinâmico) | `ia_engine/src/ia_engine/features/analyse/datasources/analyse_datasource.py` |
| `Analyse` — parâmetros (com `prompts` override) | `.../analyse/domain/parameters.py` |
| Prompts configuráveis | migration `0026_tenant_prompts.sql` (chaves `PROMPT_SYSTEM_ANALISE_PREVIA_MENSAGEM`, `PROMPT_INTENT_SYSTEM`, `PROMPT_INTENT_FOOTER`) |
| `entity_types` do tenant | `tenants_tenantconfig.entity_types` (migration 0002) → `config_publisher.rs` → Redis |
| **Nenhum chamador** | `grep '\.analyse(' server/apps` → vazio |
| Referência v1 — análise prévia | `modules/ai_engine/features/analise_previa_mensagem/` |
| Referência v1 — assunto/tags/contato | `attendance_orchestrator.py:1368` (`_auto_fill_subject`), `:1419` (`_sync_intent_tags`), `message_analyzer.py:105` (`process_contact_entities`) |
| Referência v1 — upload de treinamento | `app/treinamento/views.py:125-201`, `modules/ai_engine/features/load_document_file/` |
| Referência v1 — feedback do teste | `treinamento/models.py:246` (`QueryTestFeedback`), `testar_query.html` |
| Job de vetorização (padrão a seguir na E5) | `worker/src/scheduler.rs:363` (`processar_vetorizacao_pendente`) |

### Padrão de resiliência já estabelecido

`crates/ia_client/src/resilient.rs` centraliza timeout, retry e degradação —
`Analyse` entra por lá, como os outros cinco RPCs. Feature `mock` da crate para
os testes.

---

## Grupo C — Observabilidade e Auditoria por etapa

| Etapa | Span/log | `audit_log` | Sanitização |
|---|---|---|---|
| E1 ligar `Analyse` | `ia.analise` (`intents_count`, `entidades_count`, `duracao_ms`), `skip_all` | **sem evento** (anotação derivada) | **nunca o valor** das entidades — só tipo e contagem |
| E2 assunto | campo `assunto_definido` no span | **sem evento** (derivado; edição manual futura, sim) | assunto vem de rótulo de intenção (vocabulário fechado) — sem PII |
| E3 etiquetas | `etiquetas_aplicadas` (contagem) | **`etiqueta.aplicada_por_ia`** (atendimento, etiqueta, confiança) | nomes de etiqueta são do tenant |
| E4 contato | `campos_contato_preenchidos` (contagem) | **`contato.enriquecido_por_ia`** (contato_id + **lista de campos**, não valores) | ponto mais sensível: nome/e-mail são PII direta |
| E5 arquivo | `treinamento.extracao` (formato, bytes, caracteres) | **`treinamento.arquivo_enviado`**, `.extracao_falhou` | **nunca o texto extraído**; nome do arquivo pode ir |
| E6 feedback | `treinamento.feedback` (avaliação, houve correção) | **`treinamento.feedback_registrado`** | pergunta/resposta correta podem citar cliente — não logar |

**Kill-switch novo:** `analise_previa_habilitada` por tenant (padrão do
`transcription_enabled`, migration 0024), default **ligado**.

**Custo:** o `Analyse` é uma chamada de LLM a mais por mensagem. Rodar em
`tokio::join!` com o `Responder` (são independentes) para não somar latência.
Métrica de chamadas por tenant para acompanhar o custo.
