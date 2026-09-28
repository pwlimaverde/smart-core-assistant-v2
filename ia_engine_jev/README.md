# ia_engine_jev

Motor de IA do Smart Core Assistant v2 com **as decisões pelo Jev** (TypeSafe
System One) e **a geração pela LLM**. Implementa o mesmo contrato gRPC
`IaEngineService` do `ia_engine`: plugar é apontar o worker para este serviço
e ligar `MOTOR_ANALISE` (`llm` | `sombra` | `jev`) na configuração.

Plano: `smart-agent-config/.context/plans/ia-engine-jev.md` (plano completo e
docs na pasta ao lado). SDK: `smart-agent-config/doc_dev/libs/python/typesafe_sdk.md`.

## O que o Jev decide

| RPC | Pelo Jev | Pela LLM |
|---|---|---|
| `Analyse` | intenção principal (`Choice` com descrição e exemplo), várias intenções (`Noul` por intenção), presença e escolha de entidade entre candidatos do código | só o valor de entidade `livre`, conferido depois |
| `Responder` | pedido de humano, regras de transferência do tenant, setor, irritação, trechos da base (um por requisição), resposta apoiada / promete o proibido / diz que transfere | só o texto da resposta |
| `Sentimento` | nota (`Score`, nível mais provável) e sentimento | — |
| `TestarRegraTransferencia` | uma frase contra uma regra | — |

`Embed`, `Transcribe`, `InterpretMedia` e `ExtrairTextoDocumento` são os
mesmos do `ia_engine`.

## Chave e falhas

- A chave é **da plataforma**: CoreSetting `TYPESAFE_API_KEY` (cifrada) na
  configuração geral do painel do superusuário, publicada no Redis com a config
  de cada tenant. Sem chave, este serviço responde pelo caminho da LLM (igual ao
  `ia_engine`). O container **não** tem a variável `TYPESAFE_API_KEY`.
- Jev fora na análise: erro `UNAVAILABLE` (a mensagem fica sem análise, como
  hoje). Jev fora na resposta: **reserva** — o caminho da LLM com schema responde
  e a decisão sai `reserva` (métrica `smartcore_ia_reserva_total`).
- Nada do `state`, das perguntas ou do corpo de erro da TypeSafe vai para log.

## Estrutura

```
src/ia_engine_jev/
  typesafe/     cliente (retry com orçamento ~2 s, HTTP/2, span jev.requisicao)
  perguntas/    PURAS: dados → (state, perguntas)
  decisoes/     PURAS: respostas + limiares → decisão + motivo
  candidatos/   regex, lista e datas
  features/     analise_jev, responder_jev, sentimento_jev, testar_regra
                + as features do ia_engine (caminho da LLM e reserva)
avaliacao/      J0: conjunto rotulado e métricas (roda no VPS, não na CI)
```

## Decisões de arquitetura

- gRPC real (`grpc.aio`, HTTP/2), nunca FFI.
- Serviço **stateless**: nunca abre conexão Postgres. O RAG (busca vetorial) é
  feito pelo `worker` (Rust) via `data_postgres.QueryCompose` **antes** de
  chamar `Responder`; o texto já resolvido chega em `dados_treinamento`.
- **A config do tenant vem do Redis, não do request.** O `data_postgres`
  resolve a cascata `TenantConfig > CoreSettings` (chaves de API decifradas,
  modelo, prompts, persona) e publica em `tenant:config:<tenant_id>`; este
  serviço lê de lá, mantém cópia em RAM e escuta `tenant:config:invalidate`
  para descartá-la quando algo muda no painel — sem reiniciar o contêiner.
  Cada request gRPC carrega só `tenant_id` + os dados da mensagem. Ver
  `doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md`.
- Os **prompts de sistema** têm default no código e podem ser sobrescritos por
  chave (`PROMPT_*` global ou `tenants_tenantconfig.prompts` por tenant). O
  default é o último elo da cascata de propósito: uma chave não semeada não
  pode deixar a IA sem prompt, e a suíte de testes roda sem Redis.
- A `api_key` nunca fica em env/config global do processo e nunca é logada.
- Mídia sempre por `MediaRef.url` (URL pré-assinada R2), baixada via `httpx` —
  nunca binário inline.
- `traceparent` (W3C TraceContext) viaja só via metadata gRPC.

## Contrato

O `.proto` canônico é compartilhado com o lado Rust e vive em
`../server/crates/contracts/schemas/ai/ai_engine.proto`. **Não** editar/duplicar
aqui — os stubs Python são gerados a partir dele.

## Desenvolvimento

```bash
uv sync                       # instala deps (runtime + dev)
uv run python scripts/gen_proto.py   # gera stubs em src/ia_engine_jev/contracts/
uv run pytest                 # testes (LLM fake, sem rede/chave real)
uv run ruff check .           # lint
uv run python -m ia_engine_jev.server    # sobe o servidor gRPC (porta 50060)
```
