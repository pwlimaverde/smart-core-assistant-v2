# Runbook — motor Jev (plano ia-engine-jev)

Como ligar, testar, avaliar e desligar o motor de IA novo. O plano está em
`smart-agent-config/.context/plans/ia-engine-jev.md`.

## O que já está no ar depois do deploy

- Serviço `ia_engine_jev` no compose (sem tráfego enquanto os tenants estão no
  motor `llm`).
- Worker e runtime_api com `SMARTCORE_IA_ENGINE_JEV_ENDPOINT`.
- CoreSettings `TYPESAFE_API_KEY` (vazia), `JEV_MODELO=jev-1.13.0` e
  `MOTOR_ANALISE=llm`.
- Tela "Transferência para atendente" no app do tenant, tools MCP de
  transferência, troca de motor no painel do superusuário.

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

## 2. Teste rápido (sem mudar o motor)

- App do tenant → **Transferência para atendente** → **Nova regra** → escrever a
  condição → campo "Testar" com uma frase. Usa o Jev mesmo com o tenant no motor
  atual; nada é gravado.
- Pelo MCP: `testar_regra_transferencia`.

## 3. Avaliação J0 (go/no-go)

1. Montar o conjunto (`conjunto.jsonl`, uma mensagem por linha) a partir de
   conversas reais **anonimizadas** — o semente está em
   `ia_engine_jev/avaliacao/conjunto_semente.jsonl` (as 6 perguntas do
   relatório de migração). Formato de cada linha:
   `{"mensagem", "historico": [...], "intencao", "intencoes": [...], "transfere"}`.
2. Exportar o catálogo de intenções (`list_intencoes` pelo MCP) para
   `catalogo.json` — lista de `{tag, grupo, descricao, exemplo, comportamento}`.
   Opcional: `catalogo_en.json` com as descrições e exemplos traduzidos.
3. Rodar no VPS, na rede do stack (a chave sai do Redis, como no serviço):

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

4. O relatório (`/tmp/j0/relatorio/relatorio.md`) traz, por variante de idioma:
   acurácia da intenção, precisão/recall das etiquetas e da transferência,
   calibração por faixa de confiança, p95 e tokens por mensagem. Os CSVs não
   têm texto de mensagem. Com os números, calibrar os pisos em
   `tenants_tenantconfig.jev_config` (`{"pisos": {...}, "sensibilidade": {...}}`):

```sql
UPDATE tenants_tenantconfig
   SET jev_config = '{"pisos": {"piso_assunto": 0.65, "piso_etiqueta": 0.8},
                      "sensibilidade": {"alta": 0.6, "media": 0.78, "baixa": 0.9},
                      "entidades": {"quantidade_tiragem": {"estrategia": "regex"},
                                    "tipo_produto": {"estrategia": "lista",
                                                     "opcoes": ["cartão", "banner"]}}}'
 WHERE tenant_id = '<TENANT_UUID>';
```

   Depois, reaplicar o motor do tenant no painel (passo 4) — é o que republica
   a config no Redis. Chaves desconhecidas e números fora de 0–3 são ignorados.

## 4. Sombra

Painel do superusuário → **Configurações por tenant** → aba "IA & Modelos" →
**Motor das decisões da IA** → **Sombra** → Aplicar (auditado como
`tenant_config.motor_alterado`).

O motor atual continua decidindo; o Jev registra o que faria. Comparar:

```sql
SELECT etapa, motor, vale, decisao, transferiu, motivo, count(*)
  FROM oraculo_decisao_ia
 WHERE tenant_id = '<TENANT_UUID>' AND criado_em > now() - interval '7 days'
 GROUP BY 1,2,3,4,5,6 ORDER BY 1,2,3;
```

## 5. Regras de transferência

1. App do tenant → Transferência para atendente → botão de **sugestões** (ícone
   no topo): cria regras **desligadas** a partir do texto antigo (comportamentos
   das intenções e prompt de regras de transferência).
2. Revisar cada uma, escrever a condição exata, testar e ligar.
3. Quando o motor Jev estiver valendo, tirar o texto de transferência da
   persona, do `PROMPT_REGRAS_TRANSFERENCIA` e dos comportamentos — uma fonte só.

## 6. Ligar o Jev

Mesmo lugar do passo 4 → **Jev** → Aplicar. Vale na próxima mensagem.
Acompanhar no Grafana: alertas `jev-limite-429`, `jev-reserva-alta`,
`jev-p95-lento`, `jev-custo-diario-alto`; e "Últimas transferências" na tela do
tenant.

## Voltar atrás

Motor **Atual (LLM)** no painel. Efeito imediato; nada é apagado. Falha do Jev
já cai sozinha na reserva (LLM com schema), com a decisão marcada `reserva`.

## Depois de uma semana sem regressão (J5)

- `MOTOR_ANALISE=jev` na configuração geral (todos os tenants).
- Remover o `ia_engine` antigo do repositório e o caminho `RespostaBot` do
  `ia_engine_jev` — só então.
