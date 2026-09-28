# Plano completo — `ia_engine_jev`: decisões da IA pelo Jev, geração pela LLM

> **Status:** reestruturado em 2026-09-28 — pronto para execução, começando pela J0.1.
> **Branch:** `feature/ia-engine-jev` (a partir da `dev`); cada fase em sub-branch
> `feature/ia-engine-jev-<fase>` com merge na `feature/ia-engine-jev`, e desta na `dev`
> por fase aceita.
> **Origem (histórico):** `doc_dev/planejamento/38-plano-ia-engine-jev.md` (plano aprovado,
> decisões §11) e `37-estudo-ia-engine-jev.md` (estudo e fontes). Diagramas e comparativo
> completos ficam no 38; aqui está a verdade técnica de execução.
> **Docs:** `info_aux_ia-engine-jev.md` (nesta pasta) e `doc_dev/libs/python/typesafe_sdk.md`.
> **Restrição de ambiente:** nenhum teste roda na máquina local. Localmente só
> `ruff`/`dart format`/`dart analyze`/`cargo fmt`; testes na CI; a avaliação (J0) no VPS de dev.

---

## 1. Objetivo

Serviço Python `ia_engine_jev`, derivado do `ia_engine`, que implementa o **mesmo contrato
gRPC `IaEngineService`** e entra no lugar do atual trocando só o endpoint
(`SMARTCORE_IA_ENGINE_ENDPOINT`). Nele:

- toda **decisão** sobre a mensagem é do Jev (TypeSafe System One): intenção, presença e
  escolha de entidades, sentimento, **transferência para atendente**, relevância dos trechos
  da base e conferência da resposta; a regra final é código nosso;
- a **LLM** só escreve a resposta ao cliente e extrai valores livres sem candidato;
- `Embed`, `Transcribe`, `InterpretMedia`, `ExtrairTextoDocumento` não mudam;
- a transferência passa a ser governada por um **cadastro de regras do tenant**, visível nas
  configurações, auditado e operável pelo MCP.

**Fora do escopo:** trocar o provedor da LLM, mudar o RAG (pgvector, chunks, limiares de
distância), mudar o quadro/Kanban.

## 2. Premissas fixadas

| # | Premissa | Origem |
|---|---|---|
| P1 | **A chave TypeSafe fica na configuração geral**, junto com as outras chaves: linha `TYPESAFE_API_KEY` (cifrada) em `settings_manager_coresettings`, editada na tela de configurações globais do painel do superusuário. Sem chave por tenant | dono do produto, 2026-09-28 |
| P2 | Uma conta TypeSafe da plataforma; enterprise quando o limite apertar | 38 §11 |
| P3 | TypeSafe como suboperador no termo/DPA do tenant | 38 §11 |
| P4 | Serviço separado, mesmo contrato gRPC; volta = apontar o endpoint de volta | 38 §11 |
| P5 | Valor livre de entidade: LLM pequena só se o Jev disser que está presente, com o Jev conferindo | 38 §11 |
| P6 | Transferem por padrão: pedido de humano, regras do cadastro, cliente irritado; faixa de dúvida transfere | 38 §11 |
| P7 | Base sem resposta e resposta não apoiada **não** transferem por padrão (enviam `msg_sem_info`); B4 opcional | 38 §11 |
| P8 | A LLM nunca transfere sozinha: promessa de transferir sem regra → gera de novo; persistindo, "a revisar" | 38 §4.3 |
| P9 | J0 (avaliação em português) decide go/no-go antes do resto | 38 §11 |

---

## 3. Correções aplicadas nesta reestruturação

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| C1 | A chave deixou de ser "`typesafe_api_key` cifrada como as outras" (ambíguo, sugeria o JSONB `api_keys` do tenant) e virou a CoreSetting `TYPESAFE_API_KEY`, `encrypted = true` | decisão P1; o mecanismo já existe inteiro: cifragem, tela, `UpsertCoreSetting`, auditoria `core_setting_upserted`, invalidação global do cache | código: `0009_settings_manager.sql`, `tenants/settings.rs`, `admin_module/core_settings` |
| C2 | A chave **não** passa pela `resolve_api_key` (tenant > global): lê só o global | com a cascata, um tenant poderia gravar `typesafe_api_key` no JSONB e usar outra conta, contrariando P2 | `tenants/config.rs:192` |
| C3 | A plumbing da chave saiu da J2 e virou a **J0.1**, primeira entrega | a J0 roda no VPS e precisa da chave pelo caminho oficial (Redis), não por variável solta | ordem das fases |
| C4 | `JEV_MODELO` (`jev-1.13.0`) e `MOTOR_ANALISE` (`llm`) também como CoreSettings, com override por tenant | mesmo padrão de `MODEL`/`LLM_CLASS`; trocar a versão do Jev para todos numa linha | `tenants/config.rs` (cascata) |
| C5 | O container do `ia_engine_jev` **não** tem `TYPESAFE_API_KEY` no ambiente | o SDK lê essa variável sozinho; a chave só pode entrar por `api_key=` a partir da config | doc do SDK |
| C6 | Dependências do SDK registradas: `httpx2` (≠ `httpx`), `tenacity`, pydantic ≥ 2.12 | PyPI 0.7.2; evita surpresa no lock | PyPI JSON |
| C7 | `TypeSafeUnprocessableEntityError` (422) não tem retry e conta como erro nosso; `TypeSafeAPIError.body` nunca vai para log | 422 = pergunta malformada; o body pode ecoar o `state` (mensagem do cliente) | doc de erros do SDK |
| C8 | A J0 roda como container efêmero no VPS de dev, não na CI nem na máquina local | máquina local não roda testes; CI não deve ter a chave de produção nem chamar rede paga em todo push | restrição de ambiente |
| C9 | Migrações a partir de `0046` | última existente é `0045_exclusao_definitiva.sql` | repositório |
| C10 | Sub-seção "Observabilidade & Auditoria" em cada fase | requisito transversal do projeto | skill `plan-restructuring` |

---

## 4. Desenho (resumo executável; detalhe e diagramas no 38 §2–§4)

### 4.1 Análise (`Analyse`, segundo plano)

Uma requisição Jev. `state = {mensagem, historico (≤ 4 falas), empresa (1 linha)}`;
instruções em inglês, opções do tenant em português (ou traduzidas, conforme a J0).

| Pergunta | Primitiva | Consumo |
|---|---|---|
| `intencao_principal` | `Choice` catálogo + `nenhuma`; opção = `{what: descricao, examples: exemplo}` | assunto se `confidence ≥ piso_assunto` |
| `intencao::<tag>` | `Noul` por intenção | etiqueta se `≥ piso_etiqueta`; faixa de dúvida → "a revisar" |
| `entidade_presente::<tipo>` | `Noul` por tipo | só busca valor do que está presente |
| `entidade::<tipo>` | `Choice` entre candidatos do código + `nenhum` | valor copiado do texto |

Estratégias de entidade: `regex`, `lista`, `varios`, `data`, `livre` (38 §4.1). Catálogo
> 240 intenções → dois estágios (grupo, depois intenção).

### 4.2 Resposta com transferência (`Responder`)

1. **Antes de gerar** — uma requisição com `pede_humano` (`Noul`), `regra::<id>` (`Noul`
   por regra ativa de gatilho "condição"), `setor` (`Choice` fluxos + `nenhum`),
   `intencao_principal` (`Choice`), `insatisfacao` (`Score` 3 níveis); e **uma requisição
   por trecho**, em paralelo, com `relevante`, `responde`, `contradiz`, `instrui` (`Noul`).
2. **Decisão 1 (código puro):** transfere sem chamar a LLM se `pede_humano ≥ limiar`, regra
   disparada (condição ≥ limiar da sensibilidade, ou gatilho de intenção com confiança
   ≥ `piso_assunto`; se "depois de coletar", só com os campos do cartão preenchidos),
   irritação `≥ 1,5`, ou faixa de dúvida. Nenhum trecho aprovado + intenção de conteúdo →
   `msg_sem_info` (transfere só se o sinal "base sem resposta" estiver ligado).
3. **LLM** recebe os trechos aprovados em dois blocos ("evidência", "conflito") e o
   comportamento da intenção escolhida pelo Jev; devolve **texto puro**.
4. **Depois de gerar** — `resposta_apoiada`, `promete_o_que_nao_pode`, `resposta_transfere`.
5. **Decisão 2:** transfere se `promete_o_que_nao_pode ≥ 0,8`, ou (B4 ligado)
   `resposta_apoiada < confianca_minima_transferencia`; `resposta_transfere` sem regra →
   regenera uma vez; persistindo, "a revisar". `confiabilidade` gravada = `resposta_apoiada`.
6. **Setor:** destino da regra → `setor` com `confidence ≥ piso_setor` → fluxo padrão.

### 4.3 Cadastro de regras de transferência

Tabela `oraculo_regra_transferencia` (RLS por tenant): `id`, `tenant_id`, `nome`,
`gatilho_tipo` (`condicao` | `intencao`), `condicao`, `intencao_tag`,
`exemplos_sim[]`, `exemplos_nao[]`, `momento` (`imediato` | `apos_coleta`),
`campos_coleta[]`, `destino_tipo` (`fluxo` | `setor_jev` | `padrao`), `destino_fluxo_id`,
`mensagem`, `sensibilidade` (`baixa` | `media` | `alta`), `ativa`, `sugestao`
(criada pela migração), `created_at`, `updated_at`. Unicidade `(tenant_id, lower(nome))`.

Sinais automáticos e padrões na `tenants_tenantconfig` (JSONB `transferencia_sinais`:
liga/desliga + sensibilidade de `pede_humano`, `irritacao`, `duvida_transfere`,
`base_sem_resposta`, `resposta_sem_apoio`; `transferencia_fluxo_padrao_id`;
`msg_transferencia` já existe). Sensibilidade → limiar numérico por tabela calibrada na J0
(o tenant nunca vê número cru).

Regras ativas e sinais vão ao Redis dentro de `tenant:config:<uuid>` (como os prompts); o
contrato gRPC não as carrega.

Tela "Transferência para atendente" (tenant_module, configurações): sinais automáticos,
regras do negócio com **Testar**, padrões, últimas transferências.

### 4.4 Sentimento

`nota` = nível mais provável de um `Score` de 5 níveis (número escrito pelo cliente vence);
`sentimento` = `Choice` positivo/negativo; `feedback` = o texto.

### 4.5 Contrato (`ai_engine.proto`, aditivo, sem `map`)

- `AnalyseRequest`: `repeated IntentDef intents = 7` (`tag`, `grupo`, `descricao`, `exemplo`),
  `repeated EntidadeDef entidades = 8` (`tipo`, `descricao`, `estrategia`, `repeated string opcoes`).
- `AnalyseResponse`: `intent_principal`, `confianca_principal`, `modelo`.
- `ResponderRequest`: `repeated IntentDef intents`, `repeated Trecho trechos` (`id`,
  `conteudo`, `distancia`), `comportamento` à parte (substitui o `dados_treinamento` colado).
- `ResponderResponse`: `motivo_transferencia`, `repeated SinalDaDecisao sinais` (`nome`,
  `valor`, `limiar`), `motor`, `modelo`; `confiabilidade` = `resposta_apoiada`.

### 4.6 Pydantic

Sai do domínio e das chamadas de modelo (`build_dynamic_model`, `AnaliseAvaliacao` removidos;
`IntentItem`/`EntidadeItem`/`IntentsEntidades`/`RespostaFinal` → `dataclass(frozen=True)`;
`RespostaBot` só no caminho de reserva até a J5). Fica em `config/models.py`,
`pydantic-settings` e como dependência do SDK.

### 4.7 Estrutura do módulo

```
ia_engine_jev/
  pyproject.toml         typesafe-sdk[http2]==0.7.2 + deps do ia_engine
  Dockerfile             sem TYPESAFE_API_KEY no ambiente (C5)
  src/ia_engine_jev/
    typesafe/            cliente (AsyncTypeSafeClient por chave, RetryPolicy), exceções → erros RSOE
    perguntas/           PURAS: dados → (state, questions)
    decisoes/            PURAS: respostas + limiares → decisão + motivo + sinais
    candidatos/          regex e listas por tipo de entidade
    features/            analyse, sentimento, responder, embed, transcribe, interpret_media, extrair_texto
    servicer.py server.py config/ telemetry.py
  avaliacao/             conjunto rotulado + script de métricas (roda no VPS)
  tests/                 respostas do Jev gravadas; nenhum teste chama a rede
```

### 4.8 Falhas

Análise: Jev fora → mensagem sem análise (como hoje). Resposta: Jev fora → caminho atual
(LLM com schema; `RespostaBot`), métrica `smartcore_ia_reserva_total`. Retry com orçamento
~2 s; 422 sem retry (C7); 401 → erro de configuração (chave ausente/errada), log ERROR sem
a chave, e a mensagem segue pela reserva.

---

## 5. Fases

Sequência: **J0.1 → J0 → (go/no-go) → J1 → J2 → J3 → J4 → J5.** A J3 vem antes da J4 por
ser a decisão com mais efeito na conversa.

### J0.1 — Chave e modelo na configuração geral (fundação)

**Entrega**
1. Migração `0046_typesafe_core_settings.sql`: `INSERT ... ON CONFLICT (key) DO NOTHING`
   de `TYPESAFE_API_KEY` (`''`, `encrypted = true`, "Chave da plataforma na TypeSafe (Jev).
   Uma conta para todos os tenants; sem chave por tenant."), `JEV_MODELO` (`jev-1.13.0`) e
   `MOTOR_ANALISE` (`llm`).
2. `config_cache.rs::RuntimeConfig`: `typesafe_api_key: SecretString` (só o global — C2),
   `jev_modelo: String`, `motor_analise: String` (tenant > global; valores fora de
   `llm|sombra|jev` → `llm` com WARN). Colunas `jev_modelo`/`motor_analise` no tenant ficam
   para a J2 (antes disso só o global vale).
3. `config_publisher.rs`: publica `typesafe_api_key`, `jev_modelo`, `motor_analise`.
4. `ia_engine/config/models.py` (e depois o do `ia_engine_jev`): campos com padrão `""`,
   `"jev-1.13.0"`, `"llm"` — o `ia_engine` atual os ignora.
5. Painel: nada novo — a chave é cadastrada na tela de configurações globais existente,
   marcando "cifrada". Descrição da CoreSetting orienta.

**Aceite:** CI verde; após o deploy em dev, o superusuário grava a chave na tela e a config
publicada de um tenant traz `typesafe_api_key` não vazia (conferido no Redis sem imprimir o
valor: só o tamanho).

**Observabilidade & Auditoria**
- a) Logs: reaproveita o WARN de chave ilegível de `load_all_settings` (só o nome); WARN novo
  para `motor_analise` inválido com `tenant_id`. Sem span novo.
- b) Auditoria: gravar/alterar a chave gera `core_setting_upserted` `{key: "TYPESAFE_API_KEY",
  encrypted: true}` pelo handler existente (evento de mudança de chave de API, 08 §4.2).
  Migração: sem evento de auditoria (semente vazia).
- c) Sanitização: `SecretString` no Rust; `expose_secret()` só no publisher; teste de que
  `Debug` do `RuntimeConfig` não mostra a chave; a exportação de configurações do painel já
  omite valores cifrados.

### J0 — Avaliação em português (go/no-go)

**Entrega**
1. `ia_engine_jev/avaliacao/`: conjunto de 300 mensagens reais anonimizadas (Ecoprint):
   intenção, multi-intenção, entidades, sentimento e transferência (pedido de humano, regra,
   sem resposta, irritação, falsos positivos) + as 6 perguntas do relatório de migração.
   Rótulo inicial pela LLM grande, revisão humana das divergências.
2. Script de métricas: acurácia da intenção principal; precisão/recall por etiqueta, entidade
   e **transferência**; calibração por faixa; p95; tokens por mensagem.
3. Três variantes de idioma (instruções EN + opções PT; tudo PT; catálogo e regras em EN) e
   duas de trechos (um por requisição × todos juntos).
4. Execução como container efêmero no VPS de dev (C8), lendo a chave de
   `tenant:config:<uuid>` no Redis; saída = relatório em markdown + CSV sem texto de mensagem.
5. Tabela sensibilidade → limiar (baixa/média/alta) por sinal, e pisos iniciais
   (`piso_assunto`, `piso_etiqueta`, `piso_entidade`, `piso_setor`, `piso_resposta_automatica`).

**Aceite:** relatório com os números e decisão go/no-go registrada no plano.

**Observabilidade & Auditoria**
- a) Logs: o script loga progresso e agregados (contagens, tokens, duração); span
  `jev.requisicao` já no molde da J1.
- b) Auditoria: sem evento de auditoria (avaliação offline, sem mudança de estado).
- c) Sanitização: conjunto anonimizado (telefones, nomes, e-mails trocados por marcadores)
  antes de sair do banco; arquivo do conjunto fica no VPS, fora do git; relatório sem texto.

### J1 — Esqueleto do `ia_engine_jev`

**Entrega**
1. Projeto `ia_engine_jev/` (padrão RSOE, Python ≥ 3.13), `typesafe-sdk[http2]==0.7.2`,
   Dockerfile, job de CI (ruff + pytest + imagem GHCR), serviço no compose de dev **sem**
   receber tráfego.
2. Contrato completo copiado; `Embed`, `Transcribe`, `InterpretMedia`,
   `ExtrairTextoDocumento` copiados sem alteração.
3. `typesafe/`: um `AsyncTypeSafeClient` por chave (cache pelo hash da chave, recriado se
   ela mudar), `RetryPolicy` com orçamento ~2 s, mapeamento de exceções para erros RSOE
   (`JevIndisponivel`, `JevChaveInvalida`, `JevPerguntaInvalida`, `JevLimite`).
4. `Analyse` e `Sentimento` pelo Jev (perguntas e decisões puras, com testes sobre respostas
   gravadas).
5. `telemetry.py` no molde atual + span `jev.requisicao` + métricas do Jev.

**Aceite:** CI verde; análise com intenção principal, multi-intenção e confiança real num
teste gravado; imagem publicada.

**Observabilidade & Auditoria**
- a) Logs/trace: span por RPC (herdado); span `jev.requisicao` com `etapa`, `perguntas`,
  `tokens_entrada`, `modelo`, `duracao_ms`, `status`, `request_id`, `trace_id`,
  `tenant_id`; erro com `error_code` (`jev_indisponivel`, `jev_chave_invalida`,
  `jev_pergunta_invalida`, `jev_limite`). Métricas sem tenant:
  `smartcore_jev_requisicoes_total{etapa,status}`, `smartcore_jev_duracao_ms{etapa}`,
  `smartcore_jev_tokens_total{etapa}`, `smartcore_jev_limite_total`.
- b) Auditoria: sem evento de auditoria (serviço técnico; eventos de conversa são do worker).
- c) Sanitização: `state`, perguntas com exemplos do tenant, `body` de erro e chave nunca
  em log/span; teste que captura o log de uma chamada com erro e confere a ausência do
  texto da mensagem e da chave.

### J2 — Contrato e sombra

**Entrega**
1. Proto aditivo (§4.5) e fbs regenerados.
2. Worker: intenções completas (cache por tenant, como o de fluxos), descrições dos tipos de
   entidade e histórico na análise.
3. Colunas `jev_modelo` e `motor_analise` em `tenants_tenantconfig` (migração `0047`),
   cascata tenant > CoreSettings; `motor_analise = sombra` chama os dois motores e grava as
   duas análises e decisões; só a do `llm` vale.
4. Tabela `oraculo_decisao_ia` (migração `0048`, RLS, retenção de 90 dias por job):
   mensagem, motor, modelo, intenção e confiança, sinais, transferiu, motivo, trechos
   aprovados/descartados, tokens, duração.
5. `oraculo_mensagem` grava `motor` e `modelo` junto da `confianca_resposta`.
6. Troca de motor por tenant no painel do superusuário (RPC concreto no `AdminService` +
   `rbac.rs` só superusuário).

**Aceite:** sombra rodando num tenant de dev; Jev ≥ atual na intenção principal.

**Observabilidade & Auditoria**
- a) Logs/trace: spans `ia.analise`/`ia.responder` do worker ganham `motor`, `modelo`,
  `llm_chamada`; divergência de sombra conta em métrica sem tenant.
- b) Auditoria: `bot.respondeu` + `motor`, `modelo`; `tenant_config.motor_alterado`
  `{antes, depois}` com `user_id` do superusuário, IP e user_agent; mudança de `JEV_MODELO`
  global já cai em `core_setting_upserted`. `oraculo_decisao_ia` **não** é auditoria.
- c) Sanitização: `oraculo_decisao_ia` sem texto de mensagem nem de trecho (só ids);
  retenção de 90 dias.

### J3 — Transferência pelo Jev e cadastro de regras

**Entrega**
1. `Responder` com as requisições antes/depois (§4.2), LLM só texto, trechos separados,
   comportamento vindo da intenção do Jev, limiares separados por escala, `RespostaBot` só
   como reserva.
2. Migração `0049`: `oraculo_regra_transferencia` + JSONB `transferencia_sinais` e
   `transferencia_fluxo_padrao_id` na config.
3. `data_postgres`: CRUD (`ListRegrasTransferencia`, `CreateRegraTransferencia`,
   `UpdateRegraTransferencia`, `AtivarRegraTransferencia`, `DesativarRegraTransferencia`,
   `SetSinaisTransferencia`, `GetConfigTransferencia`, `TestarRegraTransferencia`,
   `ListTransferencias`), publicação das regras ativas no Redis e invalidação do cache.
4. `runtime_api`: métodos concretos no `AdminService`/gRPC-Web e entradas no `rbac.rs`
   (`configuracoes:read`/`configuracoes:write`, `atendimentos:read`).
5. Migração do texto atual (prompt de regras, persona, comportamentos) em **sugestões
   inativas** — via LLM uma vez por tenant, sob comando do superusuário.
6. Tela "Transferência para atendente" no `tenant_module` (sinais, regras com Testar,
   padrões, últimas transferências) + testes de widget.
7. MCP: `get_config_transferencia`, `list_regras_transferencia`, `list_transferencias`,
   `create_regra_transferencia`, `update_regra_transferencia`, `ativar_regra_transferencia`,
   `set_sinais_transferencia`, `testar_regra_transferencia`, `desativar_regra_transferencia`
   (destrutiva, confirma pelo nome) — `dry_run` com recusa de duplicata, paridade testada.
8. `testar_pergunta` (tela e MCP) devolve motivo, sinais, intenção e confiança, trechos
   aprovados/descartados e modelo; `ListMyAuditLogRequest.evento_prefixo` e
   `list_auditoria` com filtro por evento.

**Aceite:** as 6 perguntas do relatório com a transferência certa; toda transferência com
motivo; na sombra, menos transferências indevidas que o motor atual.

**Observabilidade & Auditoria**
- a) Logs/trace: `ia.responder` com `transferida`, `motivo` (tipo do sinal ou "regra"),
  `regerada`; métricas `smartcore_transferencias_total{motivo}` (nunca o nome da regra),
  `smartcore_ia_reserva_total`; handlers do CRUD com `#[instrument(skip_all)]` via
  `run_in_tenant_transaction`.
- b) Auditoria: `atendimento.transferido_por_ia` + `motivo`, `regra_id`, sinais (nome,
  valor, limiar), `motor`, `modelo`; `bot.respondeu` + `resposta_apoiada`, `regerada`,
  decisões `sem_info`/`reserva`; `bot.transferencia_prometida_barrada`;
  `transferencia_regra.criada|atualizada|ativada|desativada` `{id, nome, campos}`;
  `transferencia_sinais.alterados` `{antes, depois}`;
  `transferencia_regra.sugestoes_geradas` `{quantidade}`. Pelo MCP, `user_agent`
  `SmartCoreAssistant-MCP/<tool>`.
- c) Sanitização: auditoria sem texto da mensagem nem da resposta; `testar_regra` não grava
  a frase testada; condição/exemplos da regra fora dos logs.

### J4 — Entidades

**Entrega:** candidatos por estratégia (`regex`, `lista`, `varios`, `data`, `livre`);
estratégia por tipo na config do tenant; LLM pequena só em `livre`, conferida por `Noul`
"o valor está no texto?"; `campos_extraidos` da resposta pelo mesmo caminho.

**Aceite:** acerto por tipo medido no conjunto; nenhum valor fora do texto.

**Observabilidade & Auditoria**
- a) Logs/trace: contagem de candidatos e de entidades aceitas por tipo no span da análise;
  métrica `smartcore_entidades_total{estrategia,resultado}`.
- b) Auditoria: sem evento novo — o preenchimento da ficha já é registrado pelo caminho
  existente de `AnexarAnaliseMensagem`; mudança de estratégia por tipo é alteração de config
  auditada pelo handler de config existente.
- c) Sanitização: valores de entidade (telefone, endereço) nunca em log; só tipo e contagem.

### J5 — Troca

**Entrega:** `SMARTCORE_IA_ENGINE_ENDPOINT` → `ia_engine_jev` (e `MOTOR_ANALISE = jev`) por
tenant, depois para todos; alertas no Grafana/Loki (taxa de 429, taxa de reserva, p95 do Jev
> 1 s, custo diário fora do normal); remoção do `ia_engine` antigo e do `RespostaBot`.

**Aceite:** uma semana sem regressão e sem cair na reserva.

**Observabilidade & Auditoria**
- a) Logs/trace: alertas sobre as métricas da J1/J3; dashboard do Jev.
- b) Auditoria: cada troca de motor gera `tenant_config.motor_alterado`; troca global cai em
  `core_setting_upserted` (`MOTOR_ANALISE`).
- c) Sanitização: revisão final — varredura dos logs de uma semana de dev por texto de
  mensagem e por prefixo de chave.

---

## 6. Custo, latência e limites

~19 mil tokens de entrada por mensagem respondida (~US$ 0,0008; ~US$ 0,80 por mil);
~100–300 ms por requisição; ~6 requisições por mensagem → ~200 mensagens/min por conta
(limite de 1.200 req/min). Transferência não chama LLM nem os 3 embeddings do score.

## 7. Riscos

| Risco | Mitigação |
|---|---|
| Português com acurácia menor | J0 com três variantes; sombra; troca só com números |
| Transferência indevida ou perdida | limiares calibrados por tenant; sombra compara com o atual |
| Chave ausente ou inválida | 401 → erro de configuração, reserva na resposta, alerta; chave só na tela global |
| Chave vazando | `SecretString`, publisher único, sem env no container, teste de log |
| Limite de requisições por conta | métrica de 429; enterprise antes de escalar |
| Alias mudando respostas | `JEV_MODELO` fixo; trocar = repetir a J0 |
| Texto do cliente a terceiro | DPA; termo do tenant; ZDR se exigido; nada de conteúdo em log |
| Mensagem adversarial | mensagem é dado; `Noul` de instrução nos trechos é filtro, não barreira |
| Regra mal escrita | uma condição exata; Testar antes de ativar |
| Volta atrás | mesmo contrato: endpoint de volta e `MOTOR_ANALISE = llm` |

---

## 8. Execução (2026-09-28)

Implementado de ponta a ponta na `feature/ia-engine-jev`, sem a chave (os testes
rodam com o Jev dublado; a avaliação real e a ativação ficam para quando a chave
for cadastrada — ver `infra/RUNBOOK_MOTOR_JEV.md`).

| Fase | Entregue |
|---|---|
| J0.1 | migração 0046 (`TYPESAFE_API_KEY` cifrada, `JEV_MODELO`, `MOTOR_ANALISE`); `RuntimeConfig` lê a chave só do global; publicação no Redis |
| J0 | `ia_engine_jev.avaliacao` (métricas puras com teste + script de rodada no VPS, 3 variantes de idioma) e conjunto semente com as 6 perguntas do relatório |
| J1 | serviço `ia_engine_jev` (cópia do `ia_engine` + `typesafe/`, `perguntas/`, `decisoes/`, `candidatos/`), `Analyse` e `Sentimento` pelo Jev, span `jev.requisicao`, métricas `smartcore_jev_*`, job de CI (piso 85%) |
| J2 | proto aditivo; worker com catálogo completo, histórico e motor `llm | sombra | jev` por tenant; migração 0047 (motor por tenant, `oraculo_decisao_ia`, motor/modelo na mensagem); troca de motor no painel do superusuário, auditada |
| J3 | `Responder` pelo Jev (antes/depois, trechos um a um, LLM só texto, reserva); migração 0048 e cadastro de regras (CRUD, sinais, teste, sugestões, últimas transferências); tela "Transferência para atendente"; 10 tools MCP; filtro por evento na trilha; motivo e sinais no ensaio e na auditoria |
| J4 | candidatos por estratégia (regex, lista, varios, data, livre) com a estratégia por tipo em `jev_config.entidades`; campos do cartão pela LLM pequena, conferidos pelo Jev |
| J5 | serviço no compose dev/prod, build das imagens, alertas no Grafana (429, reserva, p95, custo diário). **A troca e a remoção do motor antigo ficam para depois da avaliação e de uma semana sem regressão.** |

### Desvios do plano, e por quê

- **Troca por `motor_analise`, não por endpoint.** O worker tem os dois clientes
  (`SMARTCORE_IA_ENGINE_ENDPOINT` e `SMARTCORE_IA_ENGINE_JEV_ENDPOINT`) e escolhe
  por tenant. É o que torna a sombra possível e a volta instantânea (painel), sem
  redeploy.
- **Sem chave, o `ia_engine_jev` responde pelo caminho da LLM.** Pode ficar no ar
  antes da chave existir.
- **Sugestões de regra sem LLM.** A migração do texto antigo é determinística
  (intenção cujo comportamento fala em transferir → regra por intenção; cada linha
  do prompt de regras → regra por condição), sempre inativa. O que falta de
  julgamento é do tenant, na revisão.
- **Entidades vêm da config do tenant, não do request.** O `ia_engine_jev` lê
  descrições e estratégias do Redis; `EntidadeDef` no contrato fica para quem
  quiser sobrepor.
- **Pisos calibrados por SQL.** `jev_config` não tem tela: é calibração da
  plataforma, a partir da J0. Republica ao reaplicar o motor no painel.
- **Destino sem nada configurado.** Regra → setor do Jev com confiança → fluxo
  padrão → setor mais provável → primeiro fluxo: transferir sem destino deixaria
  a conversa parada com o cliente ouvindo que foi transferido.
