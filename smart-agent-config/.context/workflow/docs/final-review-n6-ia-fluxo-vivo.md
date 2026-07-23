# Final Review — n6-ia-fluxo-vivo
Data: 2026-07-22 · Modelo: Opus · Diff: dev...HEAD

## Rótulo: CONFORME

Auditoria das 5 etapas contra o plano completo/info_aux, o eixo de Observabilidade & Auditoria de cada uma, e os padrões do projeto. A implementação está fiel e limpa. Nenhuma correção foi necessária — clippy, fmt, mypy, ruff e pytest passam sem alterações.

## Resumo das correções
- Nenhuma. Não foram encontrados desvios (fora dos já aceitos e registrados durante a execução) nem defeitos a corrigir.

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---|---|---|
| N6.1 mídia no pipeline vivo | ✅ | `NormalizedMessage.media_payload/media_mime/media_file_size` (`domain_whatsapp/src/lib.rs`), pipeline `processar_pipeline_midia` em background (download via `DownloadWhatsappMedia` reusado → R2 PutFile/PresignFile → Transcribe/InterpretMedia → `AnexarAnaliseMidia`), degradação graciosa em cada etapa. Desvio aceito confirmado: sem RPC novo, rota estendida com limite de tamanho (`SMARTCORE_MEDIA_MAX_BYTES`, default 20 MiB) no `data_whatsapp`. |
| N6.2 gerado_por_ia/resumo_midia | ✅ | proto 8/9 (admin.proto + fbs), coluna `gerado_por_ia` no SELECT/RETURNING de `mensagens.rs`, mapeamento em `grpc_web.rs`, stubs Dart + remoção do default fixo em `atendimento_remote_data_source.dart`. Fluxo verificado ponta-a-ponta. Desvio aceito confirmado: `gerado_por_ia` sempre false + migration nova `0019`. |
| N6.3 fluxos de transferência | ✅ | `ListarFluxosDoTenant`/`TransferirAtendimentoParaFluxo`/`ResolverCamposAtendimento` no data_postgres, cache TTL de fluxos no worker (`FluxosCache`, 30s), `transferir_fluxo_etapa` SOBRESCREVE (sem COALESCE) + registra MovimentoFluxo. Desvio aceito confirmado: campos INPUT-ONLY, sem write-back. |
| N6.4 transcrição real Groq/OpenAI | ✅ | `ApiTranscriber` (fallback encadeado Groq→OpenAI, degrada para ""), `build_transcriber`, embeddings Google forçando `output_dimensionality=1536`, providers groq/google_genai resolvem de verdade, kill-switch `transcription_enabled` (default off). |
| N6.5 sentimento ligado ao fluxo | ✅ | `avaliar_sentimento_best_effort` (texto inbound + transcrição de áudio), persistência via `AtualizarSentimentoAtendimento`, migration `0020`, proto +12/+13, `_SentimentoChip` no Kanban. Desvio aceito confirmado: local_engine/ffi não estendidos (não tocados no diff). |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| — | Nenhum defeito encontrado | — |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| N6.1 pipeline mídia | ✅ span `midia.pipeline` (tenant_id, trace_id, message_id, media_type, error_code via `Span::record`) | ✅ `midia.analisada` (INFO; só mensagem_id/tipo/duração) | ✅ `skip_all`; base64/transcrição nunca em log | Download sem evento de auditoria — conforme plano |
| N6.2 campos chat | ✅ sem span novo (leitura) | ✅ sem evento — conforme | ✅ `resumo_midia` só trafega no corpo RPC | Conforme |
| N6.3 transferência/campos | ✅ `ia.responder` com fluxos_count/campos_pendentes_count (números) | ✅ `atendimento.transferido_por_ia` (só ids/fluxo destino) | ✅ valores de campos (PII) nunca em log | Nome do span é `ia.responder` (plano citou `bot.responder`); campos exigidos presentes |
| N6.4 transcrição | ✅ span `ia.transcribe` por tentativa (provider/model/duration/error_code = só tipo da exceção) | ✅ sem evento novo — conforme | ✅ `SecretStr` na api_key (repr redigido, testado); áudio/texto nunca em log | Conforme |
| N6.5 sentimento | ✅ span `ia.sentimento` (só `nota` numérica) | ✅ sem evento — conforme | ✅ `skip_all`; texto (PII) nunca no span | Conforme |

Sanitização geral: nenhum `warn!/error!` interpola base64, transcrição, conteúdo de mensagem ou valores de campos; api_keys ficam em `SecretStr`/`LlmProviderConfigInput` e nunca são logadas.

## 3. Decisões Autônomas (revisar depois)
- Nenhuma correção autônoma aplicada (não houve o que corrigir). Duas escolhas de NÃO-intervenção registradas:
  1. Span mantido como `ia.responder` (não renomeado para `bot.responder` do plano) — os campos de observabilidade exigidos estão presentes; renomear traria risco de regressão em dashboards existentes.
  2. `responder_via_ia` propaga erro via `?`/anyhow sem gravar `error_code` explícito no span (padrão herdado da N2); fora de escopo mexer no caminho de erro pré-existente.

## 4. Revalidação
- clippy (Rust, `--all-targets --all-features -D warnings`): ✅
- fmt (Rust): ✅
- pytest (Python): ✅ 150 passed
- ruff/mypy (Python): ✅ (mypy: no issues em 75 arquivos)
- flutter analyze/test: N/A para o subagente (nenhuma correção aplicada em `clients/`) — já validado pela sessão principal antes do gate: `.\infra\test-flutter.ps1` 337 testes verdes.

## 5. Pendências (escopo extra ou fora do plano)
- Simplificação documentada no código (não é desvio): o worker reusa o provider LLM do tenant para transcrição/visão (`resolver_provider_ia`), em vez de Groq dedicado como primary. Com provider `openai`, a transcrição vai para OpenAI (incompatibilidade ogg conhecida). Mitigado pelo fallback do `ApiTranscriber` e pelo kill-switch `transcription_enabled=false` por padrão. Providers dedicados de transcrição/visão ficam para uma continuação.
- Gaps já conhecidos e aceitos ao longo da execução (ver decisões da fase E): `gerado_por_ia` sempre false até etapa futura persistir mensagens do bot no thread; `campos_coletados`/`campos_pendentes` input-only; `local_engine`/`local_engine_ffi` sem espelho de sentimento.
- Teste manual de mídia real via WhatsApp em dev (áudio → R2 → transcrição → selo no chat) não executado nesta sessão (exige instância WhatsApp conectada) — pendência documentada para o dono do produto.
