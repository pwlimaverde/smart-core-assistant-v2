# Final Review — ia-engine-jev
Data: 2026-09-28 · Modelo: Opus · Diff: e25f3ee..HEAD (caminhos do plano)

## Rótulo: CORRIGIDO (informativo — não bloqueia o ciclo)

## Resumo das correções
O ciclo cobre J0.1 a J5 (a troca e a remoção do motor antigo ficam para depois dos testes com a chave). Foram corrigidos oito desvios:
- faltava a métrica `smartcore_transferencias_total`;
- uma falha fora do SDK saía do cliente Jev como `ok`;
- na reserva, a resposta era gravada como `motor=jev` com a confiança de cosseno;
- `tenant_config.motor_alterado` saía sem `user_agent`;
- faltavam os testes de sanitização pedidos no plano;
- os outros três estão na tabela 2.

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---|---|---|
| J0.1 chave e modelo na configuração geral (0046, `RuntimeConfig`, publisher) | ✅ | A chave vem só do global e fica em `SecretString`; o teste de `Debug` foi adicionado |
| J0 avaliação (métricas, script, 3 variantes, conjunto semente) | ✅ | A rodada real depende da chave |
| J1 serviço, cliente, retry, erros, span e métricas do Jev, job de CI | ✅ | O 401 passou a ser logado em ERROR; teste de log sanitizado adicionado |
| J2 proto aditivo, motor `llm`/`sombra`/`jev`, `oraculo_decisao_ia`, motor e modelo na mensagem, troca de motor no painel | ✅ | A métrica de divergência da sombra não foi feita (pendência) |
| J3 decisões antes/depois, cadastro de regras, tela, MCP, filtro na trilha, motivo no ensaio | ✅ | Métrica de transferências adicionada; catálogo com mais de 240 intenções protegido |
| J4 entidades por candidatos | ✅ | |
| J5 compose, imagens, alertas | ✅ | O dashboard do Grafana não foi feito (pendência); troca e remoção adiadas por decisão |

## 2. Correções Aplicadas
| Arquivo | Problema | Correção |
|---|---|---|
| `ia_engine_jev/.../typesafe/cliente.py` | Uma exceção fora de `TypeSafeError` era registrada como `ok` e subia crua; o 401 saía como WARNING | Passa a virar `JevIndisponivel`, sanitizada; o 401 sai em ERROR |
| `ia_engine_jev/.../telemetry.py`, `servicer.py` | Não existia `smartcore_transferencias_total{motivo}` | `contar_transferencia` + `motivo_da_metrica`; o nome da regra nunca vira label |
| `ia_engine_jev/.../responder_jev/__init__.py` | Catálogo com mais de 240 intenções gerava 422 e mandava toda resposta para a reserva | Nesse caso a pergunta da intenção principal fica de fora |
| `ia_engine_jev/.../config/models.py` | A chave aparecia no `repr` do pydantic | `repr=False` |
| `server/apps/worker/src/main.rs` | Na reserva, a resposta era marcada `motor=jev` com confiança de cosseno | O motor passa a ser `llm`, e a reserva segue marcada em `decisao_motor` |
| `server/apps/worker/src/main.rs` | Faltava `regerada` no span `ia.responder` | Campo adicionado |
| `server/apps/data_postgres/src/transferencia_rpc.rs` | `motor_alterado` saía sem `user_agent` | Envelope apontado para o tenant alvo; teste atualizado |
| `server/crates/infrastructure_postgres/src/config_cache.rs`, `ia_engine_jev/tests/unit/test_jev_cliente.py` | Faltavam os testes de sanitização | Adicionados |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização |
|---|---|---|---|
| Chave e motor global | ✅ | ✅ `core_setting_upserted` | ✅ |
| Motor por tenant | ✅ | ✅ `tenant_config.motor_alterado` (antes, depois, `user_id`, `user_agent`) | ✅ |
| Requisição ao Jev | ✅ `jev.requisicao` | N/A | ✅ testado |
| Análise e resposta no worker | ✅ spans com motor, modelo, motivo, `regerada` | ✅ `bot.respondeu` | ✅ só ids e números |
| Transferência | ✅ métrica | ✅ `atendimento.transferido_por_ia` com motivo e sinais | ✅ |
| Regras e sinais | ✅ | ✅ `transferencia_regra.*`, `transferencia_sinais.alterados` | ✅ |

## 3. Decisões Autônomas (revisar depois)
- A métrica de transferências fica no `ia_engine_jev`. Na sombra ela conta também decisões que não valeram; a transferência efetiva está na auditoria.
- `oraculo_decisao_ia` grava a reserva como `motor=jev, decisao=reserva`. A calibração precisa filtrar `decisao <> 'reserva'`.

## 4. Revalidação
- lint (ruff) e tipos (mypy): ✅ em `ia_engine_jev` e `mcp_server`
- `flutter analyze`: ✅ nos módulos tocados
- clippy e testes: pela CI (esta máquina não compila nem testa)

## 5. Pendências (dependem da chave e dos testes, ou ficaram fora desta rodada)
- Rodada J0 real, go/no-go e calibração dos pisos.
- J5: troca por tenant, uma semana sem regressão, remoção do `ia_engine` e do `RespostaBot`.
- Métrica de divergência da sombra e dashboard do Jev no Grafana.
- O seletor de motor no painel começa em "Sombra" em vez de mostrar o motor atual do tenant.
- **Arquivamento do plano adiado:** a fase V (testes com a chave) ainda não aconteceu; o plano segue ativo até ela terminar.
