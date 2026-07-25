# Changelog - Smart Core Assistant v2

Histórico de alterações do projeto com base no ciclo PREVC.

## [2026-07-24] - Auditoria N6–N8: 3 defeitos de bloqueio de cutover + 3 desvios de plano

> Revisão detalhada, sob demanda, de tudo que N6/N7/N8 entregaram (plano vs. código real),
> fora do ciclo PREVC. Dois dos três defeitos abaixo só se manifestariam **depois** do
> cutover/enforce, ou seja, nenhum teste ou final-review anterior os pegaria.

### Corrigido

- **ETL não reposicionava as sequences das tabelas com `id_strategy="preserve"`
  (`infra/migracao-v1/migracao_v1/tables/engine.py`).** Gravar a PK explicitamente
  (`INSERT ... (id, ...) VALUES ($1, ...)`) não avança a sequence do `SERIAL`: depois da
  carga, o primeiro INSERT normal do v2 em `auth_user`, `tenants_plan`,
  `tenants_subscription`, `tenants_paymentrecord` ou `tenants_tenantuser` reusaria um id já
  migrado e estouraria `duplicate key` — cadastrar usuário, criar plano/assinatura, registrar
  pagamento e aceitar convite quebrariam **logo após o cutover**. `--dry-run` não exercita o
  upsert, então a validação prévia do runbook não revelaria isso. Adicionado
  `_ressincronizar_sequence` (`setval(seq, COALESCE(MAX(pk),0)+1, false)`, ignorado quando
  `pg_get_serial_sequence` é NULL — PK UUID) no fim de cada spec `preserve`, + 3 testes.
- **`tenants_storage_usage.total_bytes` era um contador monotônico usado como medidor de uso
  corrente.** A purga de mídia por retenção (`media.purge` → `data_storage`) deleta o objeto
  do R2 mas nunca devolvia os bytes ao tenant, e a mídia é content-addressable — o mesmo áudio
  reenviado sobrescreve a MESMA chave e era contado de novo. Com `SMARTCORE_QUOTA_ENFORCE=true`
  (exatamente o que a N8.3 vai ligar), todo tenant acabaria bloqueado permanentemente com um
  bucket quase vazio. Corrigido: primitiva `StorageClient::tamanho` (HEAD, sem baixar corpo);
  `PutFile` contabiliza só a diferença sobre o que a chave já ocupava; a purga subtrai o que
  existia de fato; `RegisterStorageUsage` aceita delta negativo (rejeita só zero) e o upsert
  clampa em `GREATEST(0, ...)`.
- **A resposta do bot nunca era persistida no thread (N6.2/N6.3).** O worker enviava o texto
  pelo WhatsApp e seguia adiante, então: o atendente não via no chat o que o bot respondeu; o
  próprio bot não tinha memória das suas falas (o `historico` do `Responder` é montado a partir
  do `GetThread`, que só devolvia turnos do contato — a cada rodada o modelo via uma sequência
  de mensagens "human" sem nenhuma resposta sua); e `gerado_por_ia` ficava permanentemente
  `false`, deixando o objetivo declarado da N6.2 ("o chat exibe o selo com dado real")
  inalcançável. O final-review da N6 registrou o campo como gap aceito, mas tratado como
  detalhe de selo na UI, não como perda de contexto conversacional. Corrigido: o worker chama
  `PersistMessage` com `sender_id = "bot"` após o envio bem-sucedido (best-effort — a mensagem
  já foi entregue ao contato), e `MensagemRepository::criar` deriva `gerado_por_ia` do
  remetente no único ponto de escrita da tabela. Sem realimentar o envio outbound:
  `processar_mensagem_persistida` só reage a `"atendente"`. Constantes `REMETENTE_BOT`/
  `REMETENTE_ATENDENTE` substituem os literais espalhados.

### Alterado (desvios de plano quitados na mesma rodada)

- **Kill-switch de transcrição agora é por tenant (N6.4, passo 4).** Só existia a env var
  global `TRANSCRIPTION_ENABLED` do `ia_engine`, que liga/desliga a feature para a instalação
  inteira; o plano pedia a flag por tenant. Migration `0024` adiciona
  `tenants_tenantconfig.transcription_enabled` (nullable) + CoreSetting global
  `TRANSCRIPTION_ENABLED` como fallback, usando a cascata Tenant > CoreSettings que já existia
  no `resolve_runtime_config`. `ResolverConfigIa` expõe o campo e o pipeline de mídia o respeita:
  desligado, o áudio ainda vai ao R2 e o ponteiro é persistido (o atendente continua podendo
  ouvir), mas a chamada à IA **e o presign que a alimentava** são dispensados — antes o pipeline
  gastava as duas etapas para só então o engine recusar. Default segue desligado (custo/latência
  por áudio). Extraído `anexar_analise_midia` para os dois desfechos compartilharem a persistência
  do ponteiro + auditoria `midia.analisada`.
- **Rate limit do webhook ganhou a política log-only ↔ enforce (N7.3).**
  `WEBHOOK_RATE_LIMIT_ENFORCE`, com default **`true`** — diferente das quotas de propósito: o
  bloqueio 429 já valia desde a N4.4 e um default `false` abriria a ingestão a rajadas. A flag
  serve para calibrar `MAX` numa janela de observação (o excesso é medido e auditado, mas passa).
  Documentada nos dois `.env.example` do docker.
- **Guard de quota de storage passou a projetar o custo do upload.** Checava "já excedeu", então
  um único arquivo grande passava livre. `CheckQuota` aceita `delta` opcional e devolve
  `excedido` já combinado (acumulado ou projetado) + `excedido_projetado`/`delta_avaliado` para
  diagnóstico; o `PutFile` envia a diferença que o arquivo realmente vai somar. A projeção ficou
  no `data_postgres` — não no `data_storage` — para a auditoria `quota.excedida` continuar saindo
  de um único ponto.

### Validação

- `.\infra\test-local.ps1`: **tudo verde** (fmt, clippy `-D warnings`, `cargo test --workspace`
  com integração real via túnel, `cargo sqlx prepare --workspace --check`). Testes novos:
  `test_resposta_do_bot_e_persistida_no_thread` e
  `test_pipeline_midia_audio_sem_transcricao_persiste_so_o_ponteiro` (worker, este com
  `expect_transcribe().never()` para falhar se o kill-switch vazar), 3 de projeção de quota
  (`delta` que estoura, que cabe, e com limite nulo), o de delta negativo de storage, o da
  cascata do default de `WEBHOOK_RATE_LIMIT_ENFORCE`, e a asserção de `gerado_por_ia` no teste
  de integração de atendimentos.
- pytest do ETL: 78/78 (75 anteriores + 3 novos de ressincronização de sequence).
- Migration `0024` aplicada ao Postgres dev remoto; `.sqlx` regenerado
  (`cargo sqlx prepare --workspace -- --tests --all-features`).

### Observações (analisado, sem defeito)

- As 4 constraints `UNIQUE` exigidas pelos `ON CONFLICT` das specs `natural` do ETL foram
  conferidas uma a uma contra as migrations: todas existem.
- O ETL depende de rodar com role admin/BYPASSRLS no v2 (todas as tabelas tenant-scoped têm
  `FORCE ROW LEVEL SECURITY` e ele não define `app.current_tenant`). Já é o que o
  `RUNBOOK_CUTOVER_N8.md` manda usar (`smartcore_app`, não `smartcore_app_rt`).
- O dedupe por `action_id` (N7.2), a unificação do contador de rate-limit (N7.3) e a
  atomicidade/`Lagged` da fila offline (N7.4) conferem com o plano, sem ressalvas.

## [2026-07-23] - Fase N8: Migração v1→v2 + habilitação de produção (código/config — execução real pendente)

> Ciclo PREVC `n8-migracao-e-cutover` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CORRIGIDO** (ver Corrigido). Terceira e última fase do port final
> (N6–N8). **Escopo desta rodada, decidido na fase P:** construir todo o código/config
> versionado (ETL, Caddy prod, fix de cifra, tooling de enforce, runbook de cutover) **sem
> executar contra infraestrutura de produção real** — não decripta credencial real de tenant,
> não altera DNS real, não desliga/apaga `old/`. A execução real (rodar o ETL contra produção,
> aplicar o Caddy no servidor, ligar o enforce, virar o cutover) fica para o dono do produto
> rodar depois, seguindo os runbooks entregues.

### Adicionado

- **N8.1 — ETL v1→v2 (`infra/migracao-v1/`):** pacote Python (asyncpg) idempotente com
  `--dry-run`/`--since` (delta) e relatório de conciliação por entidade. Cobre: tenants/planos/
  assinaturas/pagamentos; usuários+RBAC (transforma `module_permissions` aninhado por módulo em
  escopos planos `recurso:ação`, shape aceito por `derivar_escopos`; senha marcada não-utilizável
  — força redefinição pós-cutover, decisão aprovada); contatos/atendimentos/mensagens (a v1 é
  DB-per-tenant — o ETL descobre `TenantDatabase`, conecta no banco físico de cada tenant e
  injeta `tenant_id`, achado arquitetural não documentado no plano original); documentos +
  embeddings (pgvector 1536 nativo dos dois lados, cópia direta via cast `::vector`); credenciais
  (`CipherManagerPy` replica byte-a-byte o `CipherManager` Rust — Fernet(v1).decrypt →
  AES-256-GCM, `InvalidToken` isola a credencial sem abortar o lote); instâncias Evolution + as
  3 fontes de credencial da v1 preservadas sem unificar; etapa 7 nova (mídia legada →  R2).
  75/75 testes pytest de lógica pura.
- **N8.2 — Produção web:** `docker/admin/tenant` habilitados em produção no arquivo Caddy
  **real** (`docker/edge/Caddyfile` — não `infra/caddy/*.caddy`, que ficou obsoleto desde a
  migração full-docker e foi marcado como tal); `handle_path` com precedência sobre o fallback
  Django, gRPC-Web roteado por `Content-Type` (não por path fixo). Role `smartcore_app_rt` e CORS
  do R2 de produção já estavam prontos desde N4/N5.3 — só faltava aplicar (`infra/
  PROD_ROLE_CORS_N8.md`); `.env.example` corrigido para incluir a origem de produção no
  `S3_CORS_ALLOWED_ORIGINS`.
- **N8.3 — Tooling do enforce:** consultas SQL/LogQL para derivar limites reais por plano a
  partir da janela log-only da N7 (`infra/migracao-v1/analise-enforce/`) + runbook de rollout
  (`infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md`). Não liga a flag — depende de dados reais de produção.
- **N8.4 — Runbook de cutover:** `infra/migracao-v1/RUNBOOK_CUTOVER_N8.md` — carga antecipada,
  freeze, delta, validação, virada de rota, critérios go/no-go, rollback (válido só até o
  freeze) e desligamento do legado.
- **Fix de gap fora do plano original (achado na fase P, decisão aprovada):**
  `whatsapp_instance.api_key` tinha o comentário "encriptado em repouso" desde a migration 0008
  mas o adapter Rust gravava texto plano. Migration `0023` muda a coluna para `JSONB`;
  `CipherManager` ganhou `encrypt_to_json`/`decrypt_json_entry`; todo o repositório
  (`infrastructure_postgres::integracoes::whatsapp`) passa a cifrar/decifrar via
  `CipherManager`, com `PgWhatsappStore` recebendo a instância compartilhada.

### Corrigido (final-review)

- ETL: nenhuma conexão asyncpg registrava codec `jsonb` — quebraria em runtime qualquer bind de
  dict/list Python para coluna jsonb (`module_permissions`, `subscribed_events`, `metadados`,
  `api_key`). Corrigido em `migracao_v1/db.py`.
- ETL: o transform de `whatsapp_instance.api_key` serializava JSON manualmente como string
  (suposição desatualizada de schema VARCHAR) em vez de usar o codec jsonb nativo — corrigido
  após o fix do adapter Rust.
- ETL: faltava emissão de `migracao.iniciada`/`migracao.concluida` no `audit_log` global,
  exigida pelo plano — adicionada em `cli.py` (best-effort, pulada em `--dry-run`).
- N8.2: a primeira tentativa de habilitar `/v2/admin`/`/v2/tenant` mirou `infra/caddy/*.caddy`
  (arquivo legado, não publicado pelo deploy real) — corrigido para `docker/edge/Caddyfile`.
- Achado operacional (não é código): os subagentes desta fase rodaram em worktrees isolados
  criados a partir do branch `main` (muito atrasado vs. `dev`, faltando as fases N1–N7 inteiras)
  em vez do HEAD atual — o fix de cifra do WhatsApp teve que ser refeito do zero contra o código
  real; o ETL e o tooling de enforce foram auditados e corrigidos onde necessário.

### Validação

- `cargo fmt --check`, `cargo clippy --all-targets --all-features -D warnings`,
  `cargo sqlx prepare --workspace --check`: verdes.
- `cargo test --workspace` (via túnel SSH, banco dev real): verde, exceto 1 teste pré-existente
  não relacionado (`jwt::validar_token_com_assinatura_adulterada`, confirmado como flaky/
  dependente de ordem — passa isolado; `jwt.rs` não foi tocado neste ciclo).
- Testes de integração `whatsapp`/`integracoes` (4/4, contra banco real): verdes, incluindo
  asserção nova de que a coluna `api_key` nunca guarda o plaintext.
- `pytest infra/migracao-v1` (75/75): verde.
- Auditoria final rodada pelo agente principal (não pelo subagente Opus dedicado — interrompido
  pelo limite mensal de gastos da API a meio da execução); ver
  `final-review-n8-migracao-e-cutover.md` para o relatório completo e a recomendação de uma
  segunda auditoria Opus antes da janela de cutover real.

## [2026-07-23] - Fase N7: Endurecimento residual + operação validada (pré-cutover)

> Ciclo PREVC `n7-endurecimento-residual` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CORRIGIDO** (auditoria vazando em log-only no guard de storage e
> falta de guard de escopo no reprocessamento de dead-letter — ver Corrigido). Segunda fase do
> port final (N6–N8): quita pendências técnicas de N1/N4/N5 e valida a operação com tráfego
> real — pré-condição dura do cutover (N8). Nenhum enforcement novo ligado em produção
> (`SMARTCORE_QUOTA_ENFORCE` continua `false` por padrão).

### Adicionado

- **N7.1 — Quotas restantes:** migration `0021` (`tenants_plan.max_storage_bytes` +
  `tenants_storage_usage`); recurso `"storage"` em `verificar_quota`; RPC novo
  `RegisterStorageUsage` (chamado pelo `data_storage` após `PutFile`) + guard log-only antes do
  upload ao R2. RPC novo `CreateDepartamento` (não existia nenhum antes) com o caller de quota
  de `"departamentos"` embutido.
- **N7.2 — Idempotência do sync + dead-letter:** migration `0022` (`applied_actions`,
  `mensagem_dead_letter`); `action_id` aditivo/opcional em `MoveAtendimentoEtapaRequest`/
  `SendOutboundMessageRequest` (proto + stubs Rust/Dart regenerados), dedupe atômico (mesma
  transação da mutação) em `mover_etapa_atendimento`/`persistir_mensagem`. Outbound sem
  `whatsapp_contact` ativo vira dead-letter auditável (`mensagem.dead_letter`) em vez de erro
  silencioso; RPC administrativo `ReprocessarDeadLetter` reenfileira no outbox.
- **N7.3 — Rate-limit unificado:** `webhook_ingress` migrado do contador próprio (`redis-bus`)
  para o RPC `RegisterRateLimitAttempt` do `data_redis` (mesma chave Redis do `runtime_api` —
  upgrade transparente, sem descontinuidade de janela).
- **N7.4 — Sync offline robusto:** atomicidade single-statement em `OfflineQueue::enqueue`
  (versão) e `SqliteIndex::insert_pending_mensagem` (id negativo) — elimina a corrida entre
  conexões do pool SQLite; `RecvError::Lagged` no stream FFI vira WARN + continua (nunca encerra
  o stream); gatilho de sincronização por reconexão (`connectivity_plus`, debounce 3s) + timer
  periódico (60s) no `operacional_module`.
- **N7.5 — Validação operacional:** relatório arquivado documentando o que foi validado
  automaticamente nesta sessão (Rust `fmt`/`clippy`/`test --workspace` via túnel real, incluindo
  RLS; Flutter 337/337) e o checklist manual (rajada, dashboards/alertas, E2E, dedupe/dead-letter
  com tráfego real) que fica pendente do dono do produto — pré-condição dura do N8.

### Corrigido (final-review)

- Guard de quota de storage no `data_storage` auditava `quota.excedida` mesmo em modo log-only
  (`SMARTCORE_QUOTA_ENFORCE=false`); passou a auditar só quando o enforce real bloqueia.
- RPC `ReprocessarDeadLetter` (mutação administrativa) ganhou checagem de escopo
  (`operacional:admin`/`tenant:admin`), ausente na primeira versão.

### Pendências remanescentes (trabalho futuro)

- `CreateDepartamento` e `ReprocessarDeadLetter` ainda não têm chamador em `runtime_api`/cliente
  — quando expostos via gRPC-Web, exigem registro explícito no `AdminService`.
- As 4 validações manuais da N7.5 (rajada, dashboards/alertas, E2E, dedupe/dead-letter com
  tráfego real) são pré-condição dura do N8 — dependem do ambiente do dono do produto.
- `LocalEngineFfiDataSource` (gatilho de conectividade) ainda não está registrada no DI de
  produção — classe preparatória para o F8 (desktop).

## [2026-07-22] - Fase N6: IA no fluxo vivo (mídia, campos de IA no chat, fluxos de transferência)

> Ciclo PREVC `n6-ia-fluxo-vivo` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CONFORME** (nenhuma correção necessária). Primeira fase do
> port final (N6–N8): liga ao pipeline de mensagens real o que a N2 entregou pronto mas
> não estava cabeado. Nenhuma arquitetura nova — degradação graciosa preservada em
> todos os pontos (falha de IA nunca trava o atendimento).

### Adicionado

- **N6.1 — Mídia no pipeline vivo:** `NormalizedMessage` ganha `media_payload`/`media_mime`/
  `media_file_size`; o worker dispara, em background após a persistência, download da mídia
  (rota `DownloadWhatsappMedia` do `data_whatsapp`, com limite configurável via
  `SMARTCORE_MEDIA_MAX_BYTES`) → gravação no R2 (`data_storage`) → transcrição/interpretação
  via `ia_engine` → persistência do resumo/análise (`AnexarAnaliseMidia`, RPC nova no
  `data_postgres`). Span `midia.pipeline` + auditoria `midia.analisada` (sem conteúdo).
- **N6.2 — Campos de IA no chat:** `MensagemThread` ganha `gerado_por_ia`/`resumo_midia`
  (proto aditivo, campos 8/9); `resumo_midia` sai real de ponta a ponta. Stubs Rust e Dart
  regenerados; UI do chat (selo "gerado por IA" e resumo de mídia) passa a exibir dado real.
- **N6.3 — Fluxos de transferência por tenant:** RPCs novos `ListarFluxosDoTenant`,
  `TransferirAtendimentoParaFluxo` e `ResolverCamposAtendimento` no `data_postgres`; o worker
  monta `fluxos_disponiveis` (cache TTL 30s) e `campos_coletados`/`campos_pendentes` (input-only)
  para o `Responder`, e aplica a transferência automática indicada pela IA (auditoria
  `atendimento.transferido_por_ia`, Kanban atualizado via realtime).
- **N6.4 — Transcrição real + providers Groq/Google:** `ApiTranscriber` substitui o
  `PendingTranscriber` — primary Groq `whisper-large-v3-turbo` (ogg nativo), fallback OpenAI,
  degradação graciosa se ambos falharem. Providers `groq:`/`google_genai:` passam a resolver de
  verdade via `init_chat_model`; embeddings Google forçam `output_dimensionality=1536`
  (obrigatório para não quebrar o pgvector). Flag `transcription_enabled` (off por padrão).
- **N6.5 — Sentimento ligado ao fluxo:** mensagens de texto e áudio transcrito disparam
  avaliação de sentimento best-effort (`ia_engine.Sentimento`); nota/label persistidos no
  atendimento (`AtualizarSentimentoAtendimento`) e exibidos no Kanban/fila via um indicador
  mínimo (`_SentimentoChip`, mesmo padrão do chip de prioridade já existente).
- **Migrations aditivas:** `0019_mensagem_gerado_por_ia.sql` (coluna não existia como o plano
  original assumia) e `0020_atendimento_sentimento.sql`.

### Pendências remanescentes (trabalho futuro)

- **`gerado_por_ia` sempre `false`:** as respostas do bot ainda não são persistidas como linha
  em `oraculo_mensagem` — flag fica pronta no contrato, mas sem fonte real até essa etapa futura.
- **`campos_coletados`/`campos_pendentes` são input-only:** o `ResponderResponse` do `ia_engine`
  não retorna campos extraídos; extração/write-back real exigiria a RPC `Analyse` (fora de escopo).
- **`local_engine`/`local_engine_ffi` (mirror offline) não espelham sentimento** — só a via
  remota (online) exibe o indicador por enquanto.
- **Teste manual de mídia real em dev** (áudio via WhatsApp → R2 → transcrição → selo no chat)
  não executado neste ciclo — requer instância WhatsApp conectada.
- **Simplificação conhecida:** transcrição/interpretação de mídia reusam o provider LLM do
  tenant em vez de um provider dedicado; mitigado pelo fallback e pelo kill-switch.

## [2026-07-17] - Fase N5: Consolidação de Clientes + Offline (desktop, FFI, paridade Web)

> Ciclo PREVC `n5-consolidacao-clientes-offline` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CORRIGIDO** (transporte gRPC nativo para desbloquear o link do build
> Windows + fix de reprodutibilidade no Cargokit — ver Corrigido). Última fase do backlog N1–N5:
> consolida os clientes, prova o `DataSource` abstrato plugando o `LocalEngineFFI` sem reescrever
> telas (LSP), e fecha a paridade Web com mídia servida por presign+CORS.

### Adicionado

- **N5.1 — Consolidação do app:** navegação (`go_router`) e guardas por papel consolidados no
  `smart-core-tenant`; estados padronizados de carregamento/erro/vazio (`AppEmptyView` novo no
  `design_system_module`, aplicado no Kanban/chat/convites/usuários); acessibilidade (tooltips,
  labels semânticos). Plataforma **Windows** adicionada ao app (`flutter create
  --platforms=windows`); `flutter build windows --release` empacota o `.exe` real.
- **N5.2 — `local_engine` (FFI) + mídia local:** novo crate Rust dual-target
  (`crate-type = ["staticlib","cdylib","lib"]`), 100% client-local (sem infra multi-tenant do
  servidor) — índice **SQLite** para leitura offline rápida, **cache de mídia por hash** (download
  único via URL pré-assinada, verificação sha256, sem lixo corrompido), **fila offline** com
  resolução **last-write-wins por versão** (`resolve_lww`) e auditoria 100% server-side no sync
  (nunca no cliente). Integração real via `flutter_rust_bridge` (codegen rodado, pacote
  `local_engine_ffi` gerado) — `LocalEngineFfiDataSource` troca `RemoteOnly`↔`LocalEngineFFI` por
  **import condicional**, **sem tocar nenhuma tela/controller/usecase** (prova final do princípio
  Ports & Adapters do projeto). `SyncTransport` da fila offline fiado via callbacks Dart,
  reaproveitando o canal gRPC autenticado já existente (com refresh de token).
- **N5.3 — Paridade Web:** CORS de mídia no bucket R2 (`garantir_cors`, best-effort, mesmo padrão
  do lifecycle da N4.3) com atenção à pegadinha de range request (`Content-Range`/`Accept-Ranges`
  expostos, senão o seek de áudio/vídeo quebra silenciosamente); política versionada em
  `infra/r2-cors.json`. Deploy Web do app operacional/tenant (`infra/caddy/tenant.caddy`, serviço
  Docker dedicado, job de CI) seguindo o mesmo padrão same-origin já usado pelo admin.

### Corrigido

- **Build Windows não linkava (achado real, fora do plano original):** `GrpcApiClient` (transporte
  gRPC-Web, `dart:js_interop`-only) era importado incondicionalmente por 4 módulos, quebrando a
  compilação nativa (`'JSObject' isn't a type`). Corrigido com `GrpcNativeApiClient` (canal
  `package:grpc/grpc.dart` sobre `dart:io`) + interface `GrpcTransport` + seleção Web↔nativo por
  **import condicional** (não runtime-check — só isso evita compilar o código web-only no alvo
  nativo).
- **Cargokit sem `-NoProfile`:** o build nativo do `local_engine_ffi` chamava `powershell` sem
  `-NoProfile`, herdando o perfil interativo de quem roda o build. Corrigido (build reprodutível,
  independente de módulos de terminal instalados na máquina de quem builda).

### Encerramento do backlog N1–N5

Com a N5 fechada, o produto tem: MVP operacional endurecido (N1), IA plugada (N2), autonomia do
tenant (N3), prontidão comercial (N4) e clientes consolidados com offline/Web (N5). Novas frentes
entram como ciclos PREVC próprios, sempre aterrados no código real.

## [2026-07-16] - Fase N4: Endurecimento de Produção (role não-superuser, quotas, retenção, segurança)

> Ciclo PREVC `n4-endurecimento-producao` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CORRIGIDO** (eliminada inundação da trilha de auditoria no caminho
> quente durante a auditoria — ver Corrigido). Fecha os buracos que separam o MVP de uma operação
> comercial: RLS provado de verdade sob role não-superuser, limites de plano aplicados no caminho
> quente e retenção de mídia governada por política.

### Adicionado

- **N4.1 — Role Postgres não-superuser (`smartcore_app_rt`, `NOSUPERUSER NOBYPASSRLS`):** o
  bootstrap user do container (`smartcore_app`) precisa continuar superuser (exigência do próprio
  Postgres), então a role de runtime real é **nova e aditiva** — provisionada por infra
  (`infra/provision-db-role.sh` em dev/prod; bootstrap do workflow no CI), com grants DML mínimos
  e `ALTER DEFAULT PRIVILEGES` (migrations `0016`/`0018`, idempotentes/condicionais). O runtime
  conecta por essa role (RLS respeitado); operações cross-tenant (assinaturas/pagamentos, audit
  global) usam o `admin_pool` separado — fronteira `pool` × `admin_pool` documentada em
  `connection::criar_admin_pool` e `PgPlansStore::cross_tenant_pool`. **RLS agora é provado de
  verdade:** suíte de isolamento **37 verde sob a role não-superuser** (antes cega sob superuser).
- **N4.2 — Billing/usage e quotas:** medição de uso por tenant (mensagens recebidas/enviadas,
  mídia) exposta como contadores Prometheus (`observability::usage_metrics`); `QuotaStore` (port em
  `data_postgres/ports/quota.rs`) + adapter RPC + `verificar_quota`/`verificar_inadimplencia` na
  infra, aplicado como **decorator** (`aplicar_quota_guard`) no provisionamento de instância e como
  checagem de inadimplência na ingestão do `webhook_ingress`. **Modo log-only por padrão**
  (`SMARTCORE_QUOTA_ENFORCE=false`) → enforce (402 `PAYMENT_REQUIRED`) por flag. Quota de instância
  cabeada (`COUNT active` vs `plan.max_instances`).
- **N4.3 — Retenção de mídia por política:** `tenants_plan.retention_days` (migration `0017`) +
  `COALESCE(p.retention_days, $1)` em `listar_midias_expiradas` — o scheduler consulta a política e
  dispara a purga do R2 (o resumo/análise persiste). **R2 lifecycle versionado** como defesa em
  profundidade (`garantir_lifecycle` via `put_bucket_lifecycle_configuration`,
  `S3_LIFECYCLE_EXPIRATION_DAYS`, best-effort no boot). Documentado em `08-infraestrutura-storage`.
- **N4.4 — Segurança e carga:** rate limiting amplo — `rate_limiter_generico` (port+adapter no
  `data_redis`, rota `RegisterRateLimitAttempt`) aplicado ao webhook (por `tenant:instance`) e ao
  `runtime_api` (por `tenant:user`), fail-open e auditado; `SecretString` no `S3Config`; auditoria
  RLS validada com a role real (vazamento cross-tenant provado verde).

### Corrigido

- **Inundação da trilha de auditoria no caminho quente (achado do final-review Opus):** `CheckQuota`
  auditava `quota.excedida`/`tenant.bloqueado_inadimplencia` em toda chamada — e o webhook invoca
  `CheckQuota` por mensagem recebida só para ler `inadimplente`, então um tenant saudável **no
  limite** do plano geraria uma linha de auditoria por mensagem. Auditoria movida para um flag
  explícito `auditar` (default `false`), setado só no ponto de enforcement real; em log-only apenas
  `tracing::warn` + métricas.
- **Bug latente no helper de teste do Redis (`url_redis_teste`):** concatenava `/15` à `REDIS_URL`
  sem reescrever o índice de DB, gerando `.../1/15` (rejeitado pelo redis) quando a URL já tinha
  índice — formato canônico do `.env.example`. Agora reescreve o índice (`com_db_logico`); suíte de
  integração do Redis **9 verde**.

### Notas

- Testes opt-in de R2 real (`infrastructure_storage/tests/objetos`) não passaram nesta sessão por
  **DNS não resolver o endpoint R2 desta máquina** (ambiental, `dispatch failure`) — verify de teste
  intocado pela N4. Não é desvio de código.
- **Pendências (follow-up):** quota de storage/departamentos medida mas não cabeada (falta coluna de
  limite + caller); testes de rajada da N4.4 pendentes de validação manual documentada; contadores de
  rate-limit do webhook vivem no `redis-bus` (avaliar centralizar via RPC em prod). Detalhes no
  `final-review-n4-endurecimento-producao.md`.

## [2026-07-15] - Fase N3: Painel do Tenant (convites, usuários e permissões)

> Ciclo PREVC `n3-painel-do-tenant` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CORRIGIDO** (falha de segurança real corrigida durante a auditoria —
> ver Corrigido). Dá autonomia ao admin de tenant (persona distinta do superusuário): convites,
> gestão de usuários com RBAC fino de `flow_permissions`, e configuração do próprio tenant, em um
> app Flutter dedicado.

### Adicionado

- **Novo app `smart-core-tenant` (decisão revisada do dono, substitui a recomendação original de
  módulo dentro do `smart-core-admin`):** app Flutter dedicado a tudo que o tenant usa — workspace
  operacional (`OperacionalModule`, movido do `smart-core-admin`, que hoje ficava incorretamente
  preso ao guard exclusivo do superusuário) + novo `TenantModule` (convites, gestão de usuários,
  configuração do próprio tenant). `smart-core-admin` passa a ser exclusivo do superusuário da
  plataforma (só `AdminModule`).
- **RPCs de convites/usuários no `data_postgres`:** `ListInvites`, `RevokeInvite`,
  `ListTenantUsers`, `UpdateTenantUser` — nenhum existia antes; `CreateTenant` estendido para criar
  o primeiro `TenantUser` admin do `owner_id` na mesma operação (bootstrap do 1º admin de um tenant
  novo, lacuna real do produto). RBAC `tenant:admin` aplicado no repositório
  (`ctx.exigir_qualquer`). `module_permissions` do `TenantUser` é a lista PLANA de escopos do
  usuário (mesmo formato usado por `derivar_escopos` no login) — não a estrutura aninhada por
  módulo do legado Django.
- **Exposição gRPC-Web dos 8 RPCs do painel do tenant (`server/apps/runtime_api/src/grpc_web.rs`):**
  descoberta crítica durante a execução — nem `CreateInvite`/`AcceptInvite` (que já existiam no
  roteador de envelope interno) eram alcançáveis pelo Flutter Web, que só fala gRPC-Web via
  `AdminService` (métodos concretos gerados de `.proto`). Adicionados `CreateInvite`,
  `AcceptInvite` (rota pública, sem sessão), `ListInvites`, `RevokeInvite`, `ListTenantUsers`,
  `UpdateTenantUser`, `GetMyTenantConfig`, `UpdateMyTenantConfig` (variantes tenant-scoped de
  `GetTenantConfig`/`UpdateTenantConfig`, com `tenant_id` sempre das claims da sessão, nunca do
  request). Guard `exigir_autenticado_do_metadata` (não superuser); `GetMyTenantConfig`/
  `UpdateMyTenantConfig` exigem também o escopo `tenant:admin`.
- **`tenant_module` (Flutter):** `TenantAdminDataSource` (Ports & Adapters, RemoteOnly) → service →
  8 usecases → controllers (`flutter_bloc`) → páginas de convites (gerar/listar/revogar + aceite
  público), usuários (listar + editar role/escopos/`flow_permissions`) e configuração do tenant
  (api keys mascaradas). RBAC de UI: guard de app nega superusuário puro; rotas administrativas
  `/tenant/*` exigem escopo `tenant:admin` na sessão.
- **Migração `0015_tenant_invite_revoked.sql`:** colunas `revoked`/`revoked_at` em
  `tenants_tenantinvite`.

### Corrigido (achado pelo `prevc-final-review`)

- **Falha de segurança real:** convite **revogado** ainda podia ser **aceito** — `buscar_por_token`
  ignorava a flag `revoked` e `AcceptInvite` nunca a checava, tornando a revogação cosmética (o
  link continuava válido). Corrigido: `buscar_por_token` agora filtra `AND revoked = FALSE`.
- **Lacuna de auditoria:** o bootstrap do primeiro admin em `CreateTenant` (concessão inicial de
  `tenant:admin`) não publicava evento de auditoria. Adicionado `tenant_user_bootstrap_admin`.

### Pendências (fica para um ciclo seguinte)

- Validação manual contra runtime real (subir infra + clicar na UI) não foi realizada — decisão do
  dono na fase V, aceitando a cobertura de testes automatizados (unit + integração, cobrindo RBAC
  negado/concedido nos dois lados) como evidência suficiente.
- Sem invalidação ativa do cache Redis de `flow_permissions` — mantido o TTL 30s passivo já
  documentado (decisão confirmada, não é lacuna).
- Mensagem de erro do `AcceptInvite` não distingue "convite revogado" de "convite inexistente"
  (decisão consciente da correção de segurança, para não vazar o estado do convite).

## [2026-07-10] - Fase N2: `ia_engine` (serviço Python de IA via gRPC)

> Ciclo PREVC `n2-ia-engine` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CORRIGIDO** (bug real de RAG corrigido durante a auditoria —
> ver Corrigido). Cria `ia_engine`, o primeiro serviço Python do monorepo, dando ao bot do
> WhatsApp resposta com RAG (pgvector), score de confiabilidade e degradação graciosa.

### Adicionado

- **`ia_engine/` (novo serviço Python):** `grpc.aio` real (HTTP/2, não o protocolo
  interno `transport::MuxClient`), `uv`/`pyproject.toml`, OTel com propagação W3C via
  interceptor (`opentelemetry-instrumentation-grpc`), healthcheck gRPC, graceful
  shutdown. `FeaturesCompose` da v1 (langchain 0.1.x) reescrita em LCEL 1.x/pydantic v2:
  score triádico de confiabilidade e safety-net de transferência portados
  matematicamente exatos; `RespostaBot` via structured output. 6 RPCs:
  `Transcribe`/`InterpretMedia`/`Analyse`/`Embed`/`Responder`/`Sentimento`. 35 testes
  (LLM/embeddings fake determinístico), ruff/mypy limpos.
- **Contrato gRPC:** `server/crates/contracts/schemas/ai/ai_engine.proto` reescrito com
  `service IaEngineService` (era um placeholder sem `service`); `map<string,string>`
  trocado por `repeated KeyValuePair` local (o pipeline `flatc --proto` deste crate não
  suporta `map<>` nativo nem imports cross-diretório).
- **RAG no `data_postgres`:** RPC `QueryCompose` (busca vetorial pgvector sob RLS de
  tenant, reaproveita `QueryComposeRepository`/`DocumentoRepository` já existentes) e
  RPC `ResolverConfigIa` (resolve `LlmProviderConfig` do tenant via `TenantConfigCache`
  já existente, api_key descriptografada de verdade — RPC interno worker-only, distinto
  do `GetTenantConfig` mascarado do painel admin).
- **Integração `worker` → `ia_engine`:** `IaEngineClient`/`TonicIaEngineClient` (cliente
  gRPC real via `tonic`, endpoint `http://`, worker ganha essa dependência pela primeira
  vez) + `ResilientIaEngine` (timeout + retry bounded `[0,1,2]`s só para erros
  transitórios). Barreira de bot reescrita: `Embed` → `QueryCompose` (RAG) → `Responder`,
  com fallback gracioso para o texto fixo em qualquer falha (`bot.degradado`, WARN) —
  nunca trava o atendimento.
- **UI Flutter:** indicador "gerado por IA" + resumo de mídia no chat
  (`chat_message_bubble.dart`/`mensagem_thread.dart`), sem lógica de IA no cliente.
- **Docker compose dev/prod:** serviço `ia_engine` (imagem própria, contexto = raiz do
  repo para acessar o `.proto` canônico), `worker` com `depends_on: ia_engine`.

### Corrigido

- **Bug de RAG em produção (achado pelo `prevc-final-review`):** `ResolverConfigIa`
  enviava `embeddings_provider` como nome de classe LangChain cru (ex.:
  `"OpenAIEmbeddings"`) em vez de slug de provedor — `init_embeddings` do lado Python
  falhava sempre, mascarado pela própria degradação graciosa (o bot continuava
  respondendo o texto fixo, sem erro visível). Normalizado para a mesma heurística de
  slug já usada para o LLM; api_key de embeddings resolvida separadamente
  (`ConfigIa.embeddings_api_key`, pode divergir do provedor do LLM).
- **Sanitização reforçada:** `Debug` manual (redigido) em `ConfigIa`/
  `LlmProviderConfigInput` — evita que um `{:?}` acidental vaze api_key em claro; teste
  Python `test_api_key_nunca_aparece_em_logs` estendido para cobrir o caminho de erro
  (`servicer._abort`), não só o de sucesso.

### Pendências (fica para um ciclo seguinte)

- `fluxos_disponiveis`/`campos_coletados`/`campos_pendentes` chegam vazios no
  `Responder` — resolução de fluxos de transferência por tenant.
- `Transcribe`/`InterpretMedia`/`Analyse`/`Sentimento` implementados e testados nos dois
  lados mas **não ligados ao pipeline de mensagens ao vivo** (exige estender
  `domain_whatsapp::NormalizedMessage` com URL de mídia).
- Indicador "gerado por IA" no chat Flutter existe mas ainda recebe dado fixo
  (`false`/`null`) — o proto do chat (`operacional`) precisa ganhar os campos
  correspondentes e o backend precisa persisti-los.
- Transcrição real de áudio no Python é um `PendingTranscriber` (interface completa,
  provedor de voz real pendente); `pyproject.toml` só traz `langchain-openai` — Groq/
  Google GenAI degradam graciosamente mas não funcionam de fato ainda.

## [2026-07-09] - Fase N1: Fechamento do MVP + Scheduler do Worker

> Ciclo PREVC `n1-fechamento-mvp-scheduler` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CONFORME** (nenhuma correção necessária). Fecha a única lacuna
> estrutural remanescente da F4 (scheduler temporal do worker) e o elo outbox→outbound do
> atendente; provisiona observabilidade (dashboards + alertas Grafana) como código.

### Adicionado

- **Scheduler temporal do `worker` (F4.3b):** `worker/src/scheduler.rs` novo — loop
  `tokio::spawn` + `tokio::time::interval` (default 60s, configurável via
  `SMARTCORE_SCHEDULER_TICK_SECS`) paralelo ao consumidor do bus. Port `Clock`
  (`SystemClock`) para tempo injetável. Duas tarefas, cada uma sob lock Redis
  cross-tenant `SET NX PX` (`scheduler:lock:feedback_timeout` / `:media_purge`):
  timeout de feedback vencido (transiciona e audita `atendimento.feedback_expirado`)
  e disparo de purga de mídia expirada (publica `media.purge` no bus, já consumido
  pelo `data_storage`).
- **Migração `0014_scheduler_idempotencia.sql`:** colunas `feedback_expirado_em`
  (`oraculo_atendimento`) e `midia_purgada_em` (`oraculo_mensagem`) + índices
  parciais, garantindo que 2 ticks seguidos não dupliquem efeito.
- **RPCs de varredura no `data_postgres`:** `ListarAtendimentosFeedbackVencido`,
  `MarcarFeedbackExpirado`, `ListarMidiasExpiradas`, `MarcarMidiaPurgada` — as duas
  varreduras são cross-tenant via `admin_pool` (BYPASSRLS), mesmo padrão de
  `AdminListAllConnectedInstances`.
- **Elo outbox → outbound do atendente (WS-6.3 / N1.3):** worker consome
  `message.persisted` (já drenado pelo `OutboxRelay`) e, quando `sender_id ==
  "atendente"`, resolve destino (`ResolverDestinoEnvioOutbound`, novo RPC) e envia
  via `data_whatsapp::SendWhatsappMessage` com retry/backoff (1/2/4s) e
  idempotência por `status_envio` (reentrega do consumer group vira no-op).
  Sucesso grava o `stanzaId` (`MarcarMensagemEnviada`); falha definitiva audita
  `mensagem.envio_falhou` (WARN, sem conteúdo) via `MarcarMensagemFalhaEnvio`.
- **Dashboards e alertas Grafana como código (N1.4):**
  `docker/observability/provisioning/dashboards/json/{servicos_saude,latencia_grpc,
  outbox_backlog,trace_chain}.json` (novo) e `provisioning/alerting/{rules,
  contact-points,notification-policies}.yml` (novo); `allowUiUpdates: false` e
  `editable: false` nos providers/datasources para dashboards-como-código de fato.

### Corrigido

- **Bug pré-existente no envio do bot:** `worker` montava o payload de
  `SendWhatsappMessage` com as chaves `instance_id`/`to`, mas o handler em
  `data_whatsapp` sempre esperou `id`/`to_number` — corrigido no mesmo call site
  tocado pelo elo outbox→outbound.
- **Duplicidade de prefixo de métrica no `otel-collector`:** `namespace:
  "smartcore"` do exporter Prometheus duplicava o prefixo já presente nos nomes de
  métrica da aplicação (`smartcore_rpc_duration_ms` → `smartcore_smartcore_...`).
  Removido; adicionado `resource_to_telemetry_conversion.enabled: true` para expor
  `service_name` como label por métrica (pré-requisito dos dashboards por serviço).

### Pendências remanescentes (trabalho futuro)
- TTL de feedback via env var global (`SMARTCORE_SCHEDULER_FEEDBACK_TTL_HORAS`), não
  per-tenant — override por tenant fica para N4 (retenção por política de plano).
- Sem chave de idempotência client-side para o envio outbound (depende de dedupe do
  provedor por `stanzaId`); considerar dead-letter para falha de resolução de
  destino sem `whatsapp_contact` ativo.
- Validação de dashboards/alertas com tráfego real e Grafana rodando fica para
  verificação manual em dev (ambiente de execução deste ciclo não tinha Docker).

## [2026-06-30] - Finalização do MVP Operacional (parcial WS-0..WS-4)

> Ciclo PREVC `finalizacao-mvp-operacional` fechado como **MVP PARCIAL** e arquivado via
> `prevc-final-review`. Final-review: `final-review-finalizacao-mvp-operacional.md` — qualidade
> **CORRIGIDO** (8 desvios corrigidos, 1 crítico de segurança). Entregues WS-0 (parcial), WS-1,
> WS-2 (exceto 2.4), WS-3, WS-4. **Backlog:** WS-2.4 (ticket/kanban), WS-5 (Register/Invite/Accept
> + RBAC), WS-6 (telas Flutter), WS-7 (control_plane CRUD + admin), WS-0.1/0.3/0.4 (stack LGTM,
> e2e de trace, métricas de pool).

### Adicionado

- **WS-1 `webhook_ingress` — autenticação + whitelist + idempotência:** RPCs
  `VerifyWhatsappInstanceToken` (comparação **constante-time** via `subtle`) e `IsPhoneWhitelisted`
  no `data_postgres`; dedupe `SET NX EX` por tenant; rejeição segura 401/403 sem publicar no bus.
  Token de instância em `secrecy::SecretString`; `traceparent` W3C semeado no envelope; telefone
  mascarado na auditoria.
- **WS-2 `worker` — orquestração de atendimento:** crate `domain_whatsapp` (normalização pura, sem
  I/O); RPC `ResolveAtendimentoParaContato` (contato→atendimento em transação RLS, fim do
  `atendimento_id` fixo); cliente RPC reusado no `AppState` (sem reconexão por evento); debounce
  por contato; barreira de bot com eventos `bot.respondeu`/`bot.silenciado`.
- **WS-3 outbound:** envio `worker` → `data_whatsapp` com retry/backoff exponencial (5xx/429);
  confirmações de status (`mensagem.enviada`/`falha_envio`/`confirmada`).
- **WS-4 realtime:** server streaming gRPC real (`StreamAtendimentos`, tonic) com JWT na abertura;
  fan-out por tenant via Redis Pub/Sub 0.25 (subscriber em conexão **dedicada** `into_pubsub()`,
  publisher em `MultiplexedConnection`); auditoria `stream.aberto/fechado/nao_autorizado`.

### Removido

- **`messaging_gateway` descomissionado (WS-0.2):** diretório `server/apps/messaging_gateway/` e
  referências em `.env.example` removidos; papel migrou para `webhook_ingress` + `data_whatsapp`.

## [2026-06-25] - Camada de Mensageria WhatsApp (Evolution Go)

> Ciclo PREVC `camada-mensageria-whatsapp-evolution-go` concluído e arquivado. Final-review:
> `final-review-camada-mensageria-whatsapp-evolution-go.md` — qualidade **CORRIGIDO**.

### Adicionado

- **`infrastructure_messaging` — contrato segregado (ISP):** o trait único de 12 métodos virou
  traits de capacidade — núcleo `InstanceManager`+`MessageSender` e opcionais `PresenceControl`,
  `ReadReceipts`, `Reactions`, `MediaDownloader`, `ProfileQuery`, `AdvancedSettingsControl`. Fachada
  `MessagingProvider` com descoberta `Option<&dyn Cap>` (default `None`), preservando object-safety
  de `Arc<dyn MessagingProvider>`.
- **`ProviderRegistry` + `ProviderRegistryBuilder` (DIP) (`registry.rs`):** resolve `dyn
  MessagingProvider` pela coluna `provider` da instância (chave = `provider_name()`); plugar um novo
  provedor passa a ser nova crate + 1 linha no registry, sem tocar consumidores.
- **`MessagingProviderError::Unsupported(&'static str)` (LSP):** capacidade ausente retorna erro
  canônico em vez de no-op/panic; os handlers de `data_whatsapp` derivam a mensagem desse variante.
- **`webhook_ingress` — `WebhookNormalizer` registry (OCP):** o `match provider` hardcoded virou
  `HashMap<&str, Arc<dyn WebhookNormalizer>>`; canonização dos eventos Go (UPPERCASE/PascalCase +
  aliases) para `MESSAGE`/`CONNECTION`/`PRESENCE`/`QRCODE`/`CONTACTS`/`MESSAGE_UPDATE`; provedor
  desconhecido responde 202 + warn.
- **Novos RPCs em `data_whatsapp`:** markread, react, presence, avatar (foto de perfil), download de
  mídia e reconnect — cada um resolve o `dyn` por instância e respeita LSP.

### Alterado

- **Realinhamento Evolution API v2 (Baileys) → Evolution Go (whatsmeow):** `infrastructure_evolution`
  passa a falar o contrato Go (fonte da verdade: `evolution_go_adapter.py`) — `/instance/connect`
  com token da instância + `subscribe` UPPERCASE + `immediate`; status via `GET /instance/status`;
  envio via `/send/text` e `/send/media` (`type`/`url`/`caption`/`filename`); logout
  `DELETE /instance/logout`; `map_state` ampliado; webhook embutido no `connect`. Mocks wiremock
  migrados de v2 para Go. Nenhum endpoint v2 remanescente.
- **`data_whatsapp`:** `AppState` deixa de segurar o `EvolutionProvider` concreto e passa a usar
  `ProviderRegistry` (concreto só na composition root); `AdminBulkDisconnect` →
  `AdminBulkDisconnectInstances`.

### Observabilidade & Auditoria

- `SecretString` sempre em `skip(...)`; body de erro do provedor truncado a 200 chars; body do
  webhook nunca logado (PII). Auditoria `whatsapp.instance.create/delete` e
  `whatsapp.admin.bulk_disconnect` via `security:stream` → `audit_log` (context sem token).

### Sem mudança de schema

- DB, migração `0008_whatsapp_sync.sql` e ports/adapters já eram genéricos — validados sem alteração.

### Correções do final-review (CORRIGIDO)

- 5 handlers de capacidade opcional em `data_whatsapp` retornavam `AppError::Internal` com strings
  ad-hoc; passaram a derivar de `MessagingProviderError::Unsupported(...)` (conformidade LSP). Teste
  `test_lsp_unsupported_error` ajustado. Revalidado verde via `test-local.ps1 -Fast`.

### Pendências remanescentes (trabalho futuro)

- Confirmar empiricamente o campo `base64` do `/message/downloadmedia` contra o Evolution Go real.
- Auditar o `.proto` dos novos RPCs (markread/presence/etc.) com o time de contratos.
- `translate_go_payload` (ingress, payload whatsmeow → shape canônico) foi além do plano; documentar.

## [2026-06-20] - Painel Gerencial do Superusuário (Admin Total)

> Ciclo PREVC `painel-admin-superusuario` concluído e arquivado. Final-review:
> `final-review-painel-admin-superusuario.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Contratos:** `admin.proto`/`admin.fbs` com o `AdminService` (CoreSettings, TenantConfig, Tenants, Billing, Evolution, Feature Flags, Auditoria/Saúde e export CSV em stream); `build.rs` passa a gerar o `admin.proto`.
- **runtime_api:** fachada gRPC-Web `AdminFacade` com guarda `exigir_superuser_do_metadata` (JWT + blocklist Redis + `is_superuser`) delegando ao `data_postgres`/`control_plane`.
- **data_postgres:** handlers de tenants, planos, assinaturas, pagamentos, feature flags (+ overrides), auditoria, saúde, resumo do dashboard e export CSV; migration `0012_feature_flags` (com RLS por tenant).
- **control_plane:** handler `TestEvolutionConnection` + módulo `evolution` (verificação HTTP via reqwest/secrecy).
- **Flutter:** módulo `admin_module` (domain/data/presentation) consumindo o `AdminService` via gRPC-Web; `api_client` expõe `AdminServiceClient`; `smart-core-admin` registra o módulo e redireciona o superusuário para `/admin/core-settings`.

### Corrigido (follow-up do final-review)
- **Auditoria de mutações sensíveis:** adicionados eventos `feature_flag_set` (flag global e override), `tenant_created` (passa `redis_conn` ao handler/rota), `tenant_api_key_changed` (WARN, só nomes de chaves) e `connection_tested` no `TestEvolutionConnection`.
- **Observabilidade:** `#[tracing::instrument(skip_all)]` nos handlers `test_evolution_connection`/`register_tenant` do `control_plane`.
- **SuperuserGuard (Flutter):** passou a exigir `isSuperuser` (não só autenticação); não-superusuário é redirecionado para `/login`. Teste do guard atualizado.

### Pendências remanescentes (trabalho futuro)
- **Pagamento manual não estende `current_period_end`** da subscription (DoD parcial; exige decisão de modelagem).
- **`data_exported`** não emitido em `ExportTenantsCsv` (leitura, não mutação).
- **`user_agent`** não persistido no `audit_log` (limitação pré-existente de `AuditLogPayload`).

## [2026-06-15] - Deploy do Admin Flutter Web no CI/CD sob `/v2/admin`

> Ciclo PREVC `deploy-admin-web` concluído. Final-review:
> `final-review-deploy-admin-web.md` — qualidade **CORRIGIDO**.

### Adicionado
- **App Flutter (E1):** `usePathUrlStrategy()` em `bootstrap.dart` para URLs limpas sob `/v2/admin/` (path strategy). Dependência `flutter_web_plugins: sdk: flutter` declarada no `pubspec.yaml`.
- **Caddyfile reescrito (E2):** 2 site blocks (apex prod + dev) com matcher por path `@grpcapi path /smartcore.contracts.*` (captura POST e preflight OPTIONS), `handle_path /v2/admin/*` com SPA fallback (`try_files`), CSP (`wasm-unsafe-eval`) + HSTS + headers de segurança. `reverse_proxy` sem h2c (gRPC-Web é HTTP/1.1). Access logs por site com rotação.
- **Provisionamento (E3):** Flutter SDK para o `gh-runner` (clone stable + `precache --web`), web roots `/srv/smart-core-admin/{prod,dev}` (755, owned by `gh-runner`), Caddyfile copiado via `install` (fonte da verdade versionada), DNS apex+dev no resumo.
- **Ambiente (E4):** `RUNTIME_API_GRPC_WEB_ADDR` documentado em `.env.deploy.example` (prod 50051 / dev 50061, bind localhost).
- **CI (E5):** `detect` corrigido para `clients/pubspec.yaml` (pub workspace). Job Flutter via melos (`analyze`/`test`) + smoke build web `--wasm`.
- **Deploy DEV (E6):** Build web + publicação atômica em `/srv/smart-core-admin/dev/web` com backup `web.bak` e rollback integrado.
- **Deploy PROD (E7):** Build web + publicação versionada em `releases/$TAG/web` com symlink estável e rollback por `PREV_WEB`.
- **Debug local (E9):** `.vscode/launch.json` (compound F5 → Chrome debug contra dev remoto). `run-admin.ps1` documentado com endpoint dev remoto.
- **Documentação (E8):** Seção 9.5 em `10-plano-cicd-devops.md` (estratégia de build/deploy web). Seção 7 em `09-comunicacao-e-autenticacao.md` (same-origin, roteamento por path, debug local CORS).

### Corrigido (follow-up do final-review)
- **`server-setup.sh`:** Guard de idempotência (`grep -qF`) na inserção do Flutter PATH no `.bashrc` do `gh-runner` — evita linhas duplicadas em re-execuções. Trocado `--add` por `--replace-all` no `git config safe.directory`.

### Pendências remanescentes (trabalho futuro)
- **Fase V (validação):** Itens V0–V7 (debug local, CI verde, dev/prod acessíveis, same-origin, rollback, segurança, TLS) dependem de infraestrutura no servidor (DNS apontado, Caddy rodando, Flutter SDK instalado).
- **Job `flutter-windows`** em `deploy-prod.yml` referencia `clients/flutter_windows` (possível path obsoleto) — fora do escopo deste plano.
- **Idempotência do cargo PATH** no `.bashrc` (linha 145 de `server-setup.sh`) — pré-existente, merece correção em ciclo futuro.

## [2026-06-11] - Otimização de Pools, Concorrência e Observabilidade de Gargalos

> Ciclo PREVC `otimizacao-pools-observabilidade` concluído. Final-review (Opus):
> `final-review-otimizacao-pools-observabilidade.md` — qualidade **CORRIGIDO**.

### Adicionado
- **F1 Correções críticas:** Argon2 via `spawn_blocking` (`hash_password_async`/`verify_password_async`); `transport::bus::Consumer` com **conexão dedicada** (`get_async_connection`) para o `XREADGROUP BLOCK`; `REDIS_BUS_URL` separada da `REDIS_URL` (cache 6379-local/6380-remoto allkeys-lru × bus 6380-local/6381-remoto noeviction); **ACK condicional** (XACK só em `Ok`, PEL como retry) + DLQ `security:dlq` via `xpending_count.times_delivered` + `xclaim`.
- **F2 Controle de pools:** `PoolConfig::from_env` (`SMARTCORE_PG_POOL_MAX/MIN`, `ACQUIRE_TIMEOUT_MS`, `IDLE_TIMEOUT_S`, `MAX_LIFETIME_S`) com fail-fast e pool quente; admission control no `transport::Server` (semáforo `SMARTCORE_<SVC>_MAX_INFLIGHT`); timeouts Redis via `new_with_backoff_and_timeouts`.
- **F3 Monitoramento:** API de métricas OTel 0.24/OTLP 0.17 (`init_metrics` via `new_pipeline().metrics`); gauges de pool (`observability::pool_metrics`, feature **`pool-metrics`** só-sqlx); RED por método + slowlog com `traceparent` no `transport::runtime`; medição de espera de acquire; gauges de lag (`smartcore_bus_pending`, `smartcore_outbox_backlog`).
- **F4 Eficiência:** `revogar_familia` com DEL variádico; outbox relay marcando publicados em lote (`id = ANY($1)`); consolidação de auditoria em lote por tenant.
- **Ambiente local de testes pré-push (`infra/test-local.ps1`):** esteira completa (fmt → clippy → `cargo test --workspace` com integração via túnel SSH → `sqlx prepare --check`), modos `-Fast`/`-ResetTunnel`; `tunnel.ps1` mapeando as 3 portas (Postgres 5434, cache 6379→6380, bus 6380→6381); servidor Hostinger com `smartcore-v2-redis-bus` provisionado (host 6381, noeviction) e `REDIS_BUS_URL` nos `.env` dev/prod.

### Corrigido (follow-up do final-review)
- **Invariante de arquitetura:** métricas de pool estavam gated por `postgres-audit` (reintroduzia a aresta de produção `observability → infrastructure_postgres`); isoladas na feature `pool-metrics` (apenas `dep:sqlx`), verificado com `cargo tree -e no-dev`.
- `cargo fmt` aplicado no workspace (12 arquivos pendentes do ciclo).

### Validação
- Suíte completa (unit + integração) verde contra o Postgres/Redis reais da Hostinger via túnel (~140 testes, 0 falhas), na topologia cache×bus nova.

### Pendências remanescentes (trabalho futuro)
- **M5:** dashboard Grafana "Saúde de Dados" + 5 alertas (provisioning de infra).
- DoDs de carga formais (20 logins concorrentes, rajada de 200 req, saturação pool max=2) — instrumentação pronta, falta o exercício de carga.
- `worker`/`data_storage` ainda sem timeouts Redis (P4 restrito ao `data_postgres` por plano).
- Restart dos services dev/prod para ativarem `REDIS_BUS_URL` (entra no próximo deploy).

## [2026-06-07] - DevOps Completo: CI/CD, Ambientes e Provisionamento do Servidor

> Ciclo PREVC `cicd-devops` concluído. Final-review (Opus):
> `final-review-cicd-devops.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Workflows GitHub Actions (`.github/workflows/`):** `ci.yml` (lint, testes, `cargo sqlx prepare --check` offline, detecção Flutter), `deploy-dev.yml` (build + deploy automático em push `dev` no self-hosted runner), `deploy-prod.yml` (build + deploy com approval manual, rollback via symlink/`PREV_RELEASE`, backup de banco, GitHub Release, job Flutter Windows) e `pr-to-main.yml` (PR automático `dev→main` após tag).
- **Provisionamento do servidor (`infra/server-setup.sh`):** setup completo do Hostinger KVM2 (Ubuntu 22.04) — usuários `smartcore`/`gh-runner`, Caddy com TLS automático e h2c para gRPC, journald, ufw (só 22/80/443), sudoers restrito, `protoc`/`flatc`, postgresql-client.
- **Systemd (`infra/systemd/`):** 14 service units (7 por ambiente dev/prod) + 2 targets, com `User=smartcore`, `NoNewPrivileges`, `PrivateTmp`, `EnvironmentFile` por ambiente e ordem de dependências (`runtime_api` depende dos demais).
- **Observabilidade (`docker/`):** stack LGTM (Grafana, Loki, Tempo, Prometheus, OTEL Collector, Promtail) com `mem_limit` por container, rede externa `smartcore_v2_network` e datasources do Grafana pré-provisionados (correlação log↔trace e service map por UID).
- **Backup cifrado dos `.env` (`infra/backup-envs.ps1`):** AES-256-CBC / PBKDF2 / 100k iterações, com manuseio de senha via `SecureString` e variável de ambiente (sem expor segredo na lista de processos).
- **Documentação de deploy:** `README.md` (raiz) com instruções de CI/CD e `.env.example` com todas as variáveis de deploy (incluindo Grafana).

### Corrigido (follow-up do final-review)
- **Datasources do Grafana (`docker/observability/provisioning/datasources/ds.yml`):** `datasourceUid` referenciava o nome em vez do UID — adicionados `uid:` explícitos e corrigidas as correlações derivedField/serviceMap.
- **Smoke tests (`deploy-dev.yml`/`deploy-prod.yml`):** ampliados de 4 para os 7 serviços, alinhando com o critério V.1 ("todos os serviços active").
- **`backup-envs.ps1`:** removido código morto (`$PasswordBytes`) e endurecido o manuseio de senha.

### Pendências remanescentes (trabalho futuro)
- Separar `REDIS_BUS_URL` antes de F3 (registrado no plano).
- `docker/compose/observability.yml`: trocar o default fraco `GRAFANA_ADMIN_PASSWORD:-admin_secret_pass` por variável obrigatória em produção.
- `infra/.env.deploy.example` está coberto pelo `.gitignore` (`.env.*`) — versionar o template na feature de deploy-data/tunnel.

## [2026-06-05] - Refator de Arquitetura Modular por Contrato (RF0–RF6)

> Ciclo PREVC `refator-arquitetura-modular` concluído. Final-review (Opus):
> `final-review-refator-arquitetura-modular.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Crate `contracts` (`server/crates/contracts`):** Fonte de schema canônica em **`.proto`** (`schemas/*.proto`) gerando gRPC/Protobuf via `tonic_prost_build` e FlatBuffers via `flatc --proto`→`.fbs`→`flatc --rust` (`build.rs`). `protoc`/`flatc` vendorizados em `server/bin/`. Decisão de manchete: o `flatc` **não** transpila `.fbs`→`.proto`, então o IDL autorado virou `.proto` — FlatBuffers permanece o codec de fio padrão (`payload:[ubyte]` preservado).
- **Crate `transport` (`server/crates/transport`):** Runtime de transporte sobre UDS — `framing.rs` (len/flags/corr_id), `runtime.rs` (`MuxClient` corr_id→oneshot, timeout, backpressure), `codec.rs` (codec FB/gRPC comutável por env) e `bus.rs` (Redis Streams `STREAM_EVENTOS`/`STREAM_SEGURANCA`, consumer group, XACK, reprocessamento PEL) absorvendo o antigo `event_bus.rs` do `infrastructure_redis`.
- **`ErrorEnvelope` no `error_core` (`envelope_bridge.rs`):** Ponte serializável entre `AppError` e o envelope de contrato; 6 categorias novas em `code.rs` (apêndice, disciplina de não-remover preservada).
- **Rewire de auditoria p/ Streams (`observability/src/audit.rs`):** Auditoria publica em `STREAM_SEGURANCA` via `transport::bus`; consumidor de consolidação no app `data_postgres`.
- **Apps por contrato (`server/apps/*`):** `data_postgres` (RPC 3 protocolos + consumer de auditoria + `OutboxRelay` via PgListener), `data_redis`, `data_storage`, `runtime_api`, `messaging_gateway`, `worker`, `control_plane` (topologia ponta-a-ponta; realtime/WS e `control_plane` como stubs declarados).
- **Crate `application` (`auth/login.rs`):** Caso de uso de login falando por RPC (`transport::conectar_cliente`), sem acesso direto a repositório.
- **Migration `0011_outbox.sql`:** Tabela `outbox` + trigger `pg_notify('outbox_new')` para o relay outbox→bus.
- **Docker:** serviço `redis-bus` com `--maxmemory-policy noeviction` (separado do `allkeys-lru` que evicta Streams).

### Corrigido (follow-up das pendências do final-review)
- **Runtime de transporte resiliente (`transport/src/runtime.rs`):** `MuxClient` reescrito com keepalive (PING→PONG nas flags do `framing`), detecção de conexão morta e reconexão automática com **backoff exponencial + jitter** (teto de tentativas). O `Server` responde PING com PONG sem passar pelos handlers.
- **Ciclo `observability→infrastructure_postgres` removido em produção:** feature `postgres-audit` saiu do `default` (`default = []`); o build padrão publica auditoria só via Redis Streams. Dev-dependency auto-referente reativa a feature nos testes (retrocompatibilidade com banco).
- **`traceparent` W3C ponta-a-ponta no barramento:** `TenantEnvelope`/`EventoBruto` ganham o campo `traceparent` (serde `default`, retrocompatível); publicado e lido no Redis Streams. Propagado em `messaging_gateway` (RPC→bus), `worker` (bus→RPC) e auditoria (`audit.rs`, `data_postgres`).
- **`traceparent` no relay do outbox:** `0011_outbox` ganha a coluna `traceparent`; o `handler_persist_message` persiste o trace da requisição na mesma transação ACID e o `OutboxRelay` o repropaga no barramento (persistência → relay → bus).
- **Stubs eliminados (handlers reais por contrato):**
  - `data_postgres`: `GetThread` carrega a thread de mensagens (RLS); novos RPCs `ListAtendimentos` (snapshot por status, RLS) e `CreateTenant` (escrita admin).
  - `runtime_api`: `StreamAtendimentos` deixa de ser mock e delega ao `data_postgres` (`ListAtendimentos`) via RPC.
  - `control_plane`: `RegisterTenant` deixa de gerar UUID fake e delega ao `data_postgres` (`CreateTenant`) via RPC.

### Pendências remanescentes (trabalho futuro)
- **Streaming multi-frame de verdade** (`runtime_api::StreamAtendimentos`): hoje é snapshot req/reply. Server-streaming real exige um primitivo de Handler com múltiplos frames no `transport` (as flags `STREAM_ITEM`/`STREAM_END` já existem no framing).
- **Validação em banco real:** os handlers novos (`GetThread`/`ListAtendimentos`/`CreateTenant`) passam `fmt`/`clippy`/build offline; a semântica RLS/admin precisa ser exercitada com o túnel SSH + DB (`cargo test`).

## [2026-06-04] - Tratamento de Erros (`error_core`)

### Adicionado
- **Crate `error_core` (`server/crates/error_core`):** Fundação transversal de tratamento de erros rastreável do workspace. Reexporta `ErrorCode`, `ErrorCategory`, `AppError`, `Severity`, `ErrorReport`, `ErrorContext` e `registrar()`.
- **Taxonomia estável `ErrorCode` (`code.rs`):** 17 códigos cobrindo auth/storage/db/cache/validação/conflito/internal, serializáveis em `SCREAMING_SNAKE_CASE` (serde) com `Display` manual (sem `serde_json` no hot path de log) e `category()` para agrupamento em métricas.
- **Agregador `AppError` (`error.rs`):** Enum com payload `String` (erros de infra ainda não existem no workspace) expondo `code()`, `severity()` (composta por variante + conteúdo), `retryable()` e `public_message()` — esta nunca vaza PII, stack trace ou detalhe interno.
- **Registro rastreável (`report.rs`):** `ErrorReport` + `registrar()` emitindo log estruturado via `tracing` (`error!`/`warn!` por severidade) com correlação `trace_id`/`tenant_id`, integrado à crate `observability`.
- **Mapeamento gRPC (`transport.rs`, feature `grpc`):** `to_status()` converte `AppError` em `tonic::Status`; `AuthInsufficientScope → PermissionDenied`, demais auth → `Unauthenticated`, alinhado ao doc 09. `tonic` carregado apenas sob a feature opcional.
- **`tonic = "0.14.6"` no workspace:** Adicionada a `[workspace.dependencies]` e `error_core` registrada em `[workspace.members]` de `server/Cargo.toml`.
- **Testes de integração:** 13 testes (`tests/integration_tests.rs` + submódulos `code`/`error`/`report`/`transport`/`observability`) cobrindo mapeamento de códigos, severidade, retryable, mensagens públicas, transporte gRPC (feature-gated) e integração real com `tracing_subscriber` (correlação e não-vazamento de PII).

## [2026-06-04] - Observabilidade e Auditoria

### Adicionado
- **Migration `0010_audit_log.sql`:** Nova migração no PostgreSQL com tabela `audit_log`, índices focados em desempenho para buscas de tenant/globais, e suporte à isolamento de dados com Row-Level Security (RLS).
- **Módulo `auditoria` no `infrastructure_postgres`:** Repositório Rust (`audit_log.rs`) contendo inserção e busca estruturada de logs. Mapeamentos do SQLx implementados usando formato dinâmico (sem macros `!`) para compatibilidade com compilações locais/CI offline.
- **Crate `observability`:** Nova crate Rust transversal para inicializar o OpenTelemetry gRPC e o Tracing JSON no stdout.
- **`AuditLogger` assíncrono:** Logger fire-and-forget com dual pool (Conventional tenant pool + Admin pool com BYPASSRLS) para gravação concorrente de logs de inquilinos e de superusuários do sistema.
- **Helpers de Propagação:** Helpers utilitários no Rust para injetar e extrair o TraceContext W3C a partir de HashMaps genéricos, preparados para Redis Streams e payloads JSON.
- **Stack LGTM Docker Compose:** Configurações centralizadas em `docker/compose/observability.yml` e arquivos em `docker/observability/` (OTel Collector, Loki, Tempo, Prometheus, Grafana, Promtail) com limites rígidos de memória.
- **Provisionamento de Dashboards:** Configuração as-code para provisionamento automático de datasources no Grafana e criação do dashboard "Smart Core v2 - Auditoria e Segurança" (`audit_log.json`).
