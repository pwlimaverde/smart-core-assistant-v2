# typesafe-sdk (TypeSafe System One / Jev)

- **Versão Recomendada:** 0.7.2 (SDK) · modelo `jev-1.13.0` (fixar a versão, não o alias)
- **Status de Atualização:** 🧪 EM AVALIAÇÃO (estudo 37 — ainda não é dependência de runtime)
- **Última Verificação:** 2026-09-27
- **Propósito no Projeto:** decisões estruturadas sobre mensagens (intenção, presença de
  entidade, sentimento, pedido de humano, relevância de trecho do RAG) no lugar de chamadas
  de LLM com *structured output*. Ver `planejamento/37-estudo-ia-engine-jev.md`.
- **Documentação Oficial:** https://docs.typesafe.ai (índice para agentes: https://docs.typesafe.ai/llms.txt)
- **Código do SDK:** https://github.com/typesafe-ai/typesafe-sdk-python
- **Library ID Context7:** — (não indexada; a doc oficial é a fonte)

---

## Histórico de Atualizações

- **2026-09-27** — Documentação inicial, lida por completo a partir da doc oficial
  (conceitos, primitivas, confiança, modelos, jaggedness do Jev 1.13, API HTTP, SDK
  Python e os cookbooks de roteamento, classificação, extração e RAG).

---

## 1. O que é (e o que não é)

Jev é um modelo **System One**: recebe um `state` (texto ou JSON) e um mapa de perguntas
tipadas, e devolve respostas tipadas com probabilidades. **Não gera texto**, não conversa,
não escreve código. Serve para a decisão que o código consome; a resposta ao cliente
continua sendo trabalho de uma LLM.

| Primitiva | Pergunta | Devolve |
|---|---|---|
| `Choice` | qual destas opções? (até 255; confiável até ~240) | `choice`, `probabilities`, `confidence` |
| `Score`  | em que nível? (2 a 10 níveis ordenados) | `score` (pode cair entre níveis), `legend`, `probabilities`, `confidence` |
| `Noul`   | isto é verdade? | `noul` = P(sim), de 0 a 1 — sem `confidence` |

- Todas as perguntas de uma chamada são avaliadas **em paralelo e isoladas** (uma não vê a
  outra). Acrescentar perguntas quase não muda a latência (~100 ms típico).
- O **id da pergunta não vai ao modelo**: a pergunta completa tem de estar em
  `instructions`.
- `instructions` e `criteria` aceitam string, objeto ou lista. Objetos com campos como
  `what`, `not_for`, `examples` separam opções parecidas (os nomes dos campos são livres).
- Referência a partes do `state` por caminho entre crases: `` `conversa.ultima` ``.
- Uma resposta sempre cai dentro das opções dadas — nunca inventa valor fora do schema.

## 2. Instalação

```bash
uv add typesafe-sdk          # requer Python >= 3.10
uv add 'typesafe-sdk[http2]' # multiplexa requisições concorrentes numa conexão
```

Variáveis lidas pelo SDK: `TYPESAFE_API_KEY`, `TYPESAFE_BASE_URL`,
`TYPESAFE_DEFAULT_MODEL`, `TYPESAFE_LOG_LEVEL`. Padrões: base `https://api.typesafe.ai`,
modelo `jev-latest`, timeout 10 s por operação HTTP.

> No projeto a chave **não** vem de variável de ambiente global: vem da config do tenant
> (mesmo caminho das chaves de LLM, decifradas pelo Rust e publicadas no Redis).
> Construir o cliente com `api_key=` explícito.

## 3. Uso (assíncrono — é o que o servidor gRPC usa)

```python
from typesafe_sdk import AsyncTypeSafeClient, Choice, Noul, NoulCriteria, Score

async with AsyncTypeSafeClient(api_key=chave, model="jev-1.13.0") as client:
    r = await client.system_one(
        state={"mensagem": texto, "historico": ultimas},
        questions={
            "intencao": Choice(
                instructions="Which intent best describes `mensagem`?",
                criteria={
                    "cartoes_visita": {"what": descricao, "examples": exemplos},
                    "nenhuma": "None of the listed intents applies.",
                },
            ),
            "pede_humano": Noul(
                instructions="Does `mensagem` ask to talk to a human person?",
                criteria=NoulCriteria(true="...", false="..."),
            ),
            "satisfacao": Score(
                instructions="How satisfied is the customer in `mensagem`?",
                criteria=["Very dissatisfied", "...", "Very satisfied"],
            ),
        },
    )
r.choices["intencao"].choice, r.choices["intencao"].confidence
r.nouls["pede_humano"].noul
r.scores["satisfacao"].score
r.usage.input_tokens  # custo = tokens de entrada; saída é grátis
```

- `response_model=` aceita um modelo **pydantic** para tipar as respostas (desde 0.7.0 o
  SDK usa pydantic na (de)serialização — pydantic é dependência transitiva).
- Cliente síncrono: `TypeSafeClient` (mesma API sem `await`).

## 4. Erros e retry

Base `TypeSafeError`; HTTP em `TypeSafeAPIError` (`status`, `body`, `request_id`):
`TypeSafeAuthenticationError` (401), `TypeSafePermissionDeniedError`,
`TypeSafeNotFoundError`, `TypeSafeBadRequestError`, `TypeSafeUnprocessableEntityError`
(422 — pergunta malformada), `TypeSafeRateLimitError` (429),
`TypeSafeInternalServerError`; rede: `TypeSafeAPIConnectionError`,
`TypeSafeAPITimeoutError`; `TypeSafeAPIResponseValidationError`.

O SDK já faz retry com backoff em 429/529/5xx e respeita `retry-after`. Ajustar por
`RetryPolicy(max_retries=, backoff_initial=, backoff_max=, timeout=<orçamento total>)` —
no caminho de uma mensagem de WhatsApp, o orçamento total tem de caber no tempo de resposta.

## 5. Limites do `jev-1.13` (doc oficial de *jaggedness*, revisada em 2026-09-17)

| Limite | Consequência para nós |
|---|---|
| Idioma principal é **inglês**; outros idiomas "funcionam com acurácia menor" | Português é o nosso caso inteiro: validar em dados reais antes de ligar; instruções em inglês, conteúdo em português |
| Não gera texto | Resposta ao cliente e extração de valor livre continuam com LLM |
| Leitura literal | Escrever a condição exata e os casos de fronteira nos `criteria` |
| Não faz conta, contagem, datas | Datas: extrair partes com `Choice`, montar em código |
| `state` grande com lixo derruba a acurácia | Mandar só o necessário (últimas mensagens, não a conversa inteira) |
| Conteúdo adversarial pode mover a resposta | Mensagem do cliente é dado não confiável |
| `Noul` e `Choice` da mesma pergunta não são comparáveis | Não reaproveitar limiar de um no outro |

## 6. Operação

- **Preço:** US$ 0,042 por milhão de tokens de **entrada**; saída não é cobrada.
- **Limites:** 250 mil tokens/s e **1.200 requisições/min por conta** (dinâmicos, "podem
  mudar sem aviso"); 64k tokens por requisição, 32k para `state` + a maior pergunta.
- **Aliases:** `jev-latest` e `jev-preview` andam sozinhos. Com limiares calibrados,
  **fixar `jev-1.13.0`** e migrar de versão de propósito. A resposta traz `model` com a
  versão que respondeu — registrar.
- **Dados:** não treinam com as requisições; ZDR (retenção zero) só em plano enterprise.
  O conteúdo da mensagem sai para um terceiro — tratar no DPA/LGPD do tenant.
- Também acessível por OpenRouter e Vercel AI Gateway (`base_url` + chave do gateway).
