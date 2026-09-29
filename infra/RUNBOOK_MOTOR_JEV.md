# Runbook — motor Jev (plano ia-engine-jev)

Como ligar, testar, avaliar e desligar o motor de IA novo. O plano está em
`smart-agent-config/.context/plans/ia-engine-jev.md`. A metodologia está em
`smart-agent-config/doc_dev/planejamento/40-metodologia-motor-jev.md`.

## Como o motor decide (resumo)

"O Jev lê, o código decide o ato, a LLM só redige, o Jev confere."

1. **Leitura** — uma requisição ao Jev com todas as perguntas sobre a mensagem:
   - intenções e entidades;
   - tom (vira o sentimento do atendimento);
   - pedido de humano e regras do tenant;
   - coleta (o que o cliente já informou);
   - guarda de entrada;
   - item não fornecido.
2. **Ato** (código): `barrada`, `transferir`, `responder`, `coletar`, `social`
   ou `sem_info`.
3. **Trechos** — só quando o ato depende da base. São 10 trechos da busca
   vetorial, mais os dados da empresa e o comportamento da intenção. O Jev
   julga cada um e reordena; entram até 3.
4. **Redação** — a LLM escreve só o ato decidido, com um prompt curto por ato.
5. **Conferência** — uma requisição ao Jev. Verifica:
   - se a resposta tem apoio na evidência;
   - se promete o que não pode;
   - se diz que vai transferir;
   - se repete os dados do cliente;
   - se pede um dado proibido;
   - quantas perguntas faz;
   - se os valores copiados estão certos.
6. **Escalada** — se a conferência reprovou, o modelo maior reescreve com as
   correções, uma vez. Se reprovar de novo:
   - promessa ou texto sem apoio viram a mensagem do tenant;
   - problema de estilo sai marcado "a revisar".

Transferência, sem informação e mensagem barrada usam o texto do tenant, sem
LLM. Com o bot respondendo, a análise da mensagem (intenções, entidades, tom)
volta junto com a resposta: `Sentimento` e `Analyse` não são chamados de novo.

## O que já está no ar depois do deploy

- Serviço `ia_engine_jev` no compose, sem tráfego enquanto os tenants estão no
  motor `llm`. `JEV_REQ_POR_MINUTO` (padrão 1000) limita a vazão do processo.
- Worker e runtime_api com `SMARTCORE_IA_ENGINE_JEV_ENDPOINT`.
- CoreSettings `TYPESAFE_API_KEY` (vazia), `JEV_MODELO=jev-1.13.0` e
  `MOTOR_ANALISE=llm`.
- Tela "Transferência para atendente", coleta na tela de intenções (e nas
  tools `create_intencao`/`update_intencao`), troca de motor no painel do
  superusuário.
- Migration 0049:
  - coleta na intenção;
  - `ia_coleta_rodadas` no atendimento;
  - `ato`, `escalada`, `problemas`, `modelo_llm`, `etapas` e
    `campos_perguntados` em `oraculo_decisao_ia`.

## 1. Cadastrar a chave (configuração geral)

1. Painel do superusuário → **Configurações globais** → `TYPESAFE_API_KEY`.
2. Colar a chave e marcar **cifrada**. Salvar.
3. A gravação é auditada (`core_setting_upserted`, sem o valor) e a config de
   todos os tenants é republicada no Redis em segundo plano.

Conferir sem expor a chave (no VPS):

```bash
docker exec -it $(docker ps -qf name=data_redis) sh -c \
  'redis-cli -u "$REDIS_URL" GET tenant:config:<TENANT_UUID>' \
  | python3 -c "import sys,json; c=json.load(sys.stdin); print(len(c['typesafe_api_key']), c['jev_modelo'], c['motor_analise'])"
```

O primeiro número tem de ser maior que zero.

## 2. Configurar o tenant para a metodologia

### Coleta por intenção

App do tenant → Treinamento → Intenções → editar → **Coleta (motor Jev)**:

- **Dados que o bot pede**: tipos de entidade da configuração (ex.:
  `tipo_produto, quantidade_tiragem, dimensoes, formato_arte`) ou slugs de
  campo do cartão, em ordem de prioridade;
- **Perguntas por mensagem**: 1 a 5 (padrão 2);
- **Depois da coleta**: `Transferir` (padrão) ou `Continuar atendendo`.

O bot pede só o que falta, uma única rodada por atendimento. Depois dela, ou se
o cliente já informou tudo, aplica "depois da coleta". O texto "no máximo 2
perguntas, uma única vez" pode sair do comportamento, da persona e do
`PROMPT_INTENT_FOOTER`.

### Política do tenant (`jev_config`)

Por SQL. Chaves desconhecidas e valores tortos são ignorados:

```sql
UPDATE tenants_tenantconfig
   SET jev_config = '{
     "pisos": {"piso_assunto": 0.65, "piso_etiqueta": 0.8},
     "sensibilidade": {"alta": 0.6, "media": 0.78, "baixa": 0.9},
     "entidades": {"quantidade_tiragem": {"estrategia": "regex"},
                   "tipo_produto": {"estrategia": "lista",
                                    "opcoes": ["cartão", "banner"]}},
     "nao_fornecemos": {"itens": ["placa de ACM", "acrílico", "letra caixa",
                                  "caixa de luz (estrutura)"],
                        "alternativa": "Não trabalhamos com esse material, mas fazemos placa em PVC, lona ou adesivo vinil.",
                        "transferir": true},
     "nunca_pedir": ["telefone", "e-mail", "número do pedido", "nome completo"],
     "horario": {"fuso": "America/Fortaleza", "dias": [0,1,2,3,4],
                 "inicio": "08:00", "fim": "17:00",
                 "aviso": "O Paulo responde no próximo dia útil, a partir das 8h."},
     "llm": {"redacao": "<modelo pequeno>", "escalada": "<modelo maior>"},
     "trechos_max": 3
   }'::jsonb
 WHERE tenant_id = '<TENANT_UUID>';
```

Depois, reaplicar o motor do tenant no painel (passo 5): é o que republica a
config no Redis. Os modelos de `llm` usam o provedor do tenant; vazio = o
modelo do tenant.

## 3. Teste rápido (sem mudar o motor)

- **Ensaio** (app do tenant → Treinamento → Testar pergunta). Mostra:
  - ato e decisão;
  - intenção;
  - dados pedidos;
  - se a redação foi refeita no modelo maior, e por quê;
  - tempo de cada etapa;
  - sinais com o limiar.

  O ensaio sempre considera a primeira rodada de coleta.
- **Regra de transferência**: tela "Transferência para atendente" → campo
  "Testar". Pelo MCP: `testar_regra_transferencia` e `testar_pergunta`.

## 4. Avaliação J0 (go/no-go)

1. Montar o conjunto (`conjunto.jsonl`, uma mensagem por linha) com conversas
   reais **anonimizadas**. Formato:
   `{"mensagem", "historico": [...], "intencao", "intencoes": [...], "transfere", "ato", "rodadas_coleta"}`.
   - `ato` e `rodadas_coleta` são opcionais;
   - o ato medido é o do planejamento sem a base: `responder` pode virar
     `sem_info` no serviço.
2. Exportar o catálogo (`list_intencoes` pelo MCP) para `catalogo.json`.
3. Rodar no VPS, na rede do stack (as requisições saem com prioridade baixa):

```bash
mkdir -p /tmp/j0 && cp conjunto.jsonl catalogo.json /tmp/j0/
REDE=$(docker network ls --format '{{.Name}}' | grep -m1 '_internal$')
docker run --rm --network "$REDE" \
  --env-file /opt/smartcore/dev/env/dev.env -e TYPESAFE_API_KEY= \
  -v /tmp/j0:/dados \
  ghcr.io/pwlimaverde/smart-core-assistant-v2/smartcore-ia-engine-jev:dev \
  python -m ia_engine_jev.avaliacao.rodar \
    --tenant <TENANT_UUID> --conjunto /dados/conjunto.jsonl \
    --catalogo /dados/catalogo.json --saida /dados/relatorio
```

4. O relatório traz, por variante:
   - acurácia da intenção e do ato;
   - precisão e recall das etiquetas e da transferência;
   - calibração por faixa;
   - p95 e tokens.

   Com os números, calibrar `jev_config.pisos` (passo 2).

## 5. Sombra

Painel do superusuário → **Configurações por tenant** → "IA & Modelos" →
**Motor das decisões da IA** → **Sombra** → Aplicar (auditado como
`tenant_config.motor_alterado`).

O motor atual continua respondendo. O Jev só registra o que faria:
- faz a leitura, o ato e os trechos;
- não chama a LLM;
- roda com prioridade baixa, e é descartado se a vazão apertar.

Comparar:

```sql
SELECT motor, vale, ato, decisao, transferiu, motivo, count(*),
       round(avg(requisicoes), 1) AS req, round(avg(duracao_ms)) AS ms
  FROM oraculo_decisao_ia
 WHERE tenant_id = '<TENANT_UUID>' AND etapa = 'resposta'
   AND criado_em > now() - interval '7 days'
 GROUP BY 1,2,3,4,5,6 ORDER BY 1,2,3;
```

## 6. Regras de transferência

1. Tela "Transferência para atendente" → botão de **sugestões**: cria regras
   **desligadas** a partir do texto antigo.
2. Revisar cada uma, escrever a condição exata, testar e ligar.
3. Com o Jev valendo, tirar o texto de transferência da persona, do
   `PROMPT_REGRAS_TRANSFERENCIA` e dos comportamentos: uma fonte só. O prompt
   da redação já diz à LLM que ela não decide transferência.

## 7. Ligar o Jev

Mesmo lugar do passo 5 → **Jev** → Aplicar. Vale na próxima mensagem.

## 8. O que olhar durante os testes (logs, traces, métricas, auditoria)

**Logs** (Loki), nunca com texto de conversa:
- `ia_engine_jev` · evento `jev.decisao`. Traz:
  - `ato`, `decisao` e `motivo`;
  - `intencao` e `confianca_intencao`;
  - trechos avaliados e aprovados;
  - `perguntou` (slugs);
  - `escalada` e `problemas`;
  - `requisicoes` e `tokens_entrada`;
  - `modelo_llm`;
  - `etapas` (ms de leitura, ato, trechos, redação, conferência, escalada e
    cópia).
- `ia_engine_jev` · `requisição ao Jev falhou` (`error_code`) e
  `vazão do Jev esgotada`.
- `worker` · evento `decisão do motor Jev` (o mesmo resumo, no lado do
  worker) e o span `ia.responder`. O span tem `ato`, `escalada`,
  `requisicoes`, `trechos_count`, `rodadas_coleta`, `llm_chamada` e `motivo`.

**Traces** (Tempo): `ia.responder` → `jev.requisicao` com os atributos
`jev.etapa` (leitura, trecho, conferencia, conferencia_escalada, copia),
`jev.fila_ms`, `jev.prioridade`, `jev.tokens_entrada` e `http.status_code`.

**Métricas** (Prometheus):
- `smartcore_jev_ato_total{ato,decisao,modo}`;
- `smartcore_jev_etapa_ms{etapa,modo}`;
- `smartcore_jev_requisicoes_por_resposta`;
- `smartcore_ia_escalada_total{problema}`;
- `smartcore_jev_fila_ms` e `smartcore_jev_descartes_total`;
- `smartcore_jev_requisicoes_total{etapa,status}` e `smartcore_jev_limite_total`;
- `smartcore_ia_reserva_total` e `smartcore_transferencias_total{motivo}`.

**Auditoria** (`list_auditoria` ou tela):
- `bot.respondeu` (com `ato`, `escalada` e `decisao`);
- `atendimento.transferido_por_ia` (motivo e sinais);
- `atendimento.coleta_rodada` (campos pedidos);
- `bot.resposta_escalada` (problemas).

**Alertas**: `jev-limite-429`, `jev-reserva-alta`, `jev-p95-lento`,
`jev-custo-diario-alto`.

## Voltar atrás

Motor **Atual (LLM)** no painel. O efeito é imediato e nada é apagado. Uma
falha do Jev já cai sozinha na reserva (LLM com schema), com a decisão marcada
`reserva`.

## Depois de uma semana sem regressão (J5)

- `MOTOR_ANALISE=jev` na configuração geral (todos os tenants).
- Remover o `ia_engine` antigo do repositório e o caminho `RespostaBot` do
  `ia_engine_jev`, e só então.
