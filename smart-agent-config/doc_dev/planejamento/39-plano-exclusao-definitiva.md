# 39 — Desativar × Excluir: exclusão definitiva com registro para auditoria

> **Status:** APROVADO em 27/09/2026 com as recomendações D1–D9; implementado na branch (ver §7).
> **Branch:** `feat/exclusao-definitiva` (a partir da `dev` em `6c27f678`).
> **Origem:** pedido do responsável em 27/09/2026, após o relatório de migração
> da Ecoprint e a entrega "excluir = desativar" (`6c27f678`), que ele considerou
> estruturalmente insuficiente.

## 1. O pedido

1. **Desativar** e **excluir** são ações diferentes, e o usuário escolhe qual quer.
2. **Desativar** é reversível: o item sai de uso, mas pode voltar.
3. **Excluir** é definitivo *para o usuário*: o item ganha um estado próprio
   ("excluído"), não pode ser restaurado — se precisar de novo, cria-se outro — e
   o registro é mantido só para auditoria.
4. Excluídos **só podem ser visualizados**, nunca editados ou restaurados.
5. Excluídos **não atrapalham a utilização** (não bloqueiam nome/telefone, não
   aparecem em seleção, busca, IA, filas) e **não entram em relatórios nem
   estatísticas**.

## 2. Estado de hoje (levantado em 27/09/2026, dev)

### 2.1 O que cada entidade faz hoje

| Entidade | Ação no app | Ação no MCP | Efeito real | Volta? | Aparece inativo na lista? |
|---|---|---|---|---|---|
| Contato | Desativar | `excluir_contato` (6c27f678) | `ativo=false` + conversas com `desativado_em` | sim (`restaurar_contato`) | **não** desde 6c27f678 |
| Conversa (atendimento) | Arquivar (status) | `excluir_atendimento` / `set_atendimento_status` | `desativado_em` (0044) ou status `arquivado` | sim | arquivada: só no histórico |
| Cliente (empresa) | Desativar | `definir_cliente_ativo` | `ativo=false` | sim | só com "incluir inativos" |
| Departamento | Desativar | `desativar_departamento` | `ativo=false` | só pelo update | **não** (lista só ativos) |
| Fluxo | Desativar | `desativar_fluxo` | `ativo=false` | pelo update | sim |
| Etapa (coluna) | "Remover a coluna" | `desativar_etapa_fluxo` | `ativo=false` | **não há** | não |
| Atendente | Desativar | `desativar_atendente` | `ativo=false` | pelo update | sim |
| Campo personalizado | Desativar | `desativar_campo` | `ativo=false` | pelo update | sim |
| Etiqueta | Desativar | `desativar_etiqueta` | `ativo=false` | **não há** | não |
| Nota | "Excluir anotação" | `remover_nota` | **DELETE físico** | — | — |
| Intenção | "Remover" | `remover_intencao` | **DELETE físico** | — | — |
| Treinamento | "Remover este material?" | `remover_treinamento` | **DELETE físico** (e chunks) | — | — |
| Número ignorado | "Remover" | `remover_numero_ignorado` | **DELETE físico** | — | — |
| Conexão WhatsApp | "Remover conexão" | `remover_conexao_whatsapp` | **DELETE físico** + apaga no provedor | — | — |

Números na dev: 17 contatos (6 inativos), 2 departamentos, 2 fluxos, 13 etapas,
1 atendente, 2 campos, 25 conversas — nenhum outro inativo.

### 2.2 Problemas estruturais encontrados

1. **"Excluir" hoje é uma de três coisas diferentes** — desativar (contato), apagar
   de verdade (nota, intenção, treinamento, número ignorado, conexão) ou arquivar
   (conversa) — e o rótulo do app nem sempre diz qual ("Remover a coluna" desativa).
2. **O que é apagado não deixa registro recuperável**: a auditoria guarda que a
   intenção 57 foi removida, mas não o que ela era.
3. **Desativado sem caminho de volta**: etapa e etiqueta não têm reativação;
   departamento desativado some da lista, então não há onde reativá-lo.
4. **Unicidades não conhecem exclusão**: `oraculo_contato (tenant_id, telefone)`,
   `oraculo_departamento (tenant_id, nome|slug)`, `atu_etiqueta (tenant_id, nome)`,
   `atu_campo_personalizado (tenant_id, slug, escopo, fluxo_id)`,
   `oraculo_atendente (tenant_id, email|telefone)`, `treinamento_querycompose` e
   `oraculo_treinamento (tenant_id, tag, grupo)`, `whatsapp_whitelist (tenant_id,
   phone_number)`, `whatsapp_instance (tenant_id, name)`, `oraculo_etapa_fluxo
   (fluxo_id, ordem)`, `oraculo_cliente (tenant_id, cnpj|cpf)`. Um item excluído
   que continue na tabela **bloquearia recriar** o mesmo nome/telefone — o oposto
   do pedido ("teria que ser criado novo").
5. **Estatísticas contam tudo**: painel do tenant (abertos, aguardando, mensagens
   24h, departamentos, treinamentos), SLA (mediana da primeira resposta), detalhe
   da conexão, contagens de fluxo/etapa/atendente, exportação CSV, limite diário de
   conversas do plano — nenhuma conhece "excluído".

### 2.3 O que a entrega 6c27f678 fez e precisa ser revista

- `excluir_*` do MCP = desativar, com `restaurar_*` → vira **desativar/reativar**,
  e `excluir_*` passa a ser a exclusão definitiva.
- Lista de contatos passou a esconder desativados → volta a mostrá-los (com
  selo "inativo"); só o **excluído** some.
- Coluna `oraculo_atendimento.desativado_em` (0044, já aplicada — imutável) →
  renomeada para `excluido_em` numa migração nova.
- Contato desativado que volta a escrever é reativado → **decisão D5** abaixo.

## 3. Como vai ficar

### 3.1 Os três estados

| Estado | Como chega | Aparece em listas de gestão | Usável (seleção, roteamento, IA, filas) | Estatísticas | Volta? |
|---|---|---|---|---|---|
| **Ativo** | criação / reativação | sim | sim | sim | — |
| **Inativo** | "Desativar" | sim, com selo e botão **Reativar** | não | não entra nas contagens "ativos" (como hoje) | sim, "Reativar" |
| **Excluído** | "Excluir" (confirmação forte) | **não** — só na visão somente leitura de excluídos | não | **não**, em nenhuma | **não** — cria-se outro |

### 3.2 Modelo de dados (uma regra para todas as tabelas)

Em cada tabela do escopo: `excluido_em TIMESTAMPTZ NULL` e `excluido_por_id INT
NULL` (usuário que excluiu). `excluido_em IS NOT NULL` = excluído. O `ativo`
existente continua sendo o "inativo".

Por que coluna e não um valor novo de status: só o atendimento tem coluna de
status, e ela dirige o quadro (etapas do tipo finalização, roteamento, SLA). Um
`status = 'excluido'` teria de ser ensinado a cada `CASE`/filtro de status do
quadro, e as outras 13 tabelas precisariam de uma coluna de status nova de
qualquer jeito. A coluna é uniforme, e o "status excluído" aparece para o
usuário do mesmo jeito.

Unicidades viram **índices únicos parciais** `... WHERE excluido_em IS NULL`: o
excluído não segura o nome/telefone, e o novo pode ser criado. Os `ON CONFLICT`
que dependem delas passam a declarar o mesmo predicado (hoje:
`oraculo_contato` na ingestão e `oraculo_treinamento` no upsert).

### 3.3 Regras de negócio

- **Excluir exige confirmação forte** no app (digitar o nome) e no MCP
  (`confirmar` com o nome + `dry_run`), e diz que é definitivo.
- **Cascata**
  - Contato excluído → as conversas dele são excluídas junto (mesma transação).
  - Conversa em andamento excluída → encerrada; a próxima mensagem abre outra.
  - Etiqueta excluída → sai dos cartões; campo excluído → valores somem da ficha.
  - Intenção/treinamento excluídos → saem da busca da IA na mesma transação.
  - Conexão excluída → apagada no provedor (como hoje), registro fica.
- **Item em uso** (departamento/fluxo/etapa/atendente com conversa aberta) →
  **decisão D3**.
- **Ingestão**: contato excluído que volta a escrever vira **contato novo** (sem
  o histórico excluído) — é o "cria-se outro".
- **Auditoria**: evento `<entidade>.excluido` (WARN) com id, nome/descrição sem
  PII sensível, quem e quando. O registro em si continua na tabela.

### 3.4 Onde os excluídos deixam de contar (lista fechada)

| Onde | O que muda |
|---|---|
| Painel do tenant (`GetPainelTenant`) | abertos, aguardando, mensagens 24h, departamentos, treinamentos: só não excluídos |
| SLA (mediana 1ª resposta) | ignora conversas excluídas |
| Detalhe da conexão | atendimentos abertos e mensagens 24h sem excluídos |
| Contagens de fluxo/etapa/atendente e rodízio | sem conversas excluídas |
| Exportação CSV do quadro | sem excluídos |
| Limite diário de conversas do plano | conversa excluída não devolve cota (decisão D6) |
| Quadro, busca, histórico do contato, listas por status | sem excluídos |
| Seletores (departamento, fluxo, etapa, atendente, etiqueta, campo) | sem excluídos |
| IA: RAG, intenções, vetorização, extração | sem excluídos |
| Jobs (inatividade, pesquisa, feedback vencido, vetorização) | ignoram excluídos |
| Não lidas / tempo real | sem excluídos |
| Purga de mídia (R2) | **continua** valendo para excluídos |

### 3.5 Visualização dos excluídos

Proposta (**decisão D1**): aba **"Excluídos"** dentro de Auditoria, só para
`tenant:admin`, somente leitura. Mostra tipo, nome, quando e por quem; abre o
detalhe sem botão de ação. No MCP, `list_excluidos` (leitura, `tenant:admin`).

### 3.6 Ferramentas do MCP

| Hoje (6c27f678) | Depois |
|---|---|
| `excluir_contato` = desativar | `desativar_contato` / `reativar_contato` + `excluir_contato` (definitivo) |
| `restaurar_contato` | removida (excluído não volta) |
| `excluir_atendimento` = desativar | `excluir_atendimento` (definitivo); arquivar segue em `set_atendimento_status` |
| `restaurar_atendimento` | removida |
| `desativar_*` (fluxo, etapa, departamento, atendente, campo, etiqueta) | mantidas + `reativar_*` onde falta + `excluir_*` |
| `remover_*` (nota, intenção, treinamento, número ignorado, conexão) | renomeadas `excluir_*`, com a nova semântica |
| — | `list_excluidos` |

Toda `excluir_*`: categoria destrutiva, `dry_run`, confirmação pelo nome, e a
descrição diz "definitivo: não há como restaurar; o registro fica só para
auditoria".

### 3.7 App (Flutter)

Em cada tela: **Desativar/Reativar** (inativos visíveis com selo) e **Excluir**
separado, com diálogo "Esta exclusão é definitiva…" e digitação do nome. Aba
"Excluídos" em Auditoria. Rótulos corrigidos ("Remover a coluna" deixa de
desativar escondido).

## 4. Fases

| Fase | Conteúdo | Validação |
|---|---|---|
| F1 — Banco | Migração 0045: `excluido_em`/`excluido_por_id` nas 14 tabelas; renomeia `desativado_em`; troca unicidades por índices parciais; ajusta `ON CONFLICT` | teste de integração: excluir e recriar o mesmo telefone/nome |
| F2 — Leitura | Filtro `excluido_em IS NULL` em listagens, seletores, busca, IA, jobs e em toda agregação da §3.4 | um teste por agregação: excluído não conta |
| F3 — Escrita | RPC de exclusão por entidade (ou um `ExcluirItem {tipo, id}`), cascatas, auditoria; `Definir*Ativo`/reativação onde falta | testes de handler + integração |
| F4 — MCP | Tools da §3.6 e `list_excluidos` | pytest |
| F5 — App | Botões, diálogos, selos, aba Excluídos; stubs Dart regenerados | `flutter analyze/test` no CI |
| F6 — Dados | Rever os 6 contatos da dev (inativos hoje): continuam inativos ou viram excluídos (D7) | conferência no banco |

Tamanho: ~120 consultas com macro do sqlx nos módulos afetados. Mudá-las exige
regenerar o `.sqlx` — o que aqui não é possível (sem compilar Rust nesta
máquina). **Proposta:** um workflow manual (`sqlx-prepare.yml`, `workflow_dispatch`)
que roda as migrações num Postgres do GitHub, gera o `.sqlx` e faz commit na
branch. Assim as consultas mantêm a checagem em tempo de compilação.

## 5. Decisões para o responsável

| # | Pergunta | Recomendação |
|---|---|---|
| D1 | Onde os excluídos são visualizados? | Aba "Excluídos" em Auditoria, só `tenant:admin`, somente leitura |
| D2 | Quem pode excluir? | Mesmo escopo de escrita que desativa hoje, mais a confirmação forte |
| D3 | Excluir item em uso (departamento/fluxo/etapa/atendente com conversa aberta)? | Recusar com mensagem clara ("mova as N conversas antes") |
| D4 | Escopo: todas as 14 entidades de uma vez, ou por partes? | Tudo na mesma branch, em fases; merge só completo |
| D5 | Contato **inativo** que volta a escrever? | A conversa entra normalmente e o contato é reativado (pessoa real voltou) |
| D6 | Conversa excluída devolve a cota do limite diário? | Não (a cota mede uso real) |
| D7 | Os 6 contatos de teste inativos da Ecoprint? | Converter em excluídos |
| D8 | LGPD: excluído guarda dado pessoal indefinidamente | Aceitar agora; anonimização a pedido do titular como item separado |
| D9 | Stubs Dart: instalar só o Dart SDK aqui para gerar os stubs (sem compilar o app)? | Sim — sem isso o app não chama os RPCs novos |

## 6. Fora do escopo

Usuários/logins, tenants, planos, convites (têm ciclo próprio), purga física
programada de excluídos, e anonimização LGPD (D8).

## 7. Implementação (27–28/09/2026)

| Fase | Onde | Estado |
|---|---|---|
| F1 Banco | `0045_exclusao_definitiva.sql` | feito; validada aplicando 0001–0045 num banco temporário |
| F2 Leitura | filtros nas consultas (contato, cliente, atendimento, departamento, fluxo, etapa, atendente, campo, etiqueta, nota, intenção, treinamento, número ignorado, conexão) e nas estatísticas da §3.4 | feito |
| F3 Escrita | `infrastructure_postgres::exclusao` + rotas `ExcluirItem`, `DefinirItemAtivo`, `ListarExcluidos` + RPCs `ExcluirMyItem` (com `dry_run` e `confirmar` conferidos no servidor), `DefinirMyItemAtivo`, `ListMyExcluidos` | feito |
| F4 MCP | `excluir_item`, `reativar_item`, `list_excluidos`, `excluir_conexao_whatsapp`; saem os `remover_*` e os `restaurar_*` | feito |
| F5 App | diálogo com nome digitado, botão "Excluir definitivamente" nas telas de gestão, textos dos "remover" antigos, aba "Excluídos" em Aplicativos conectados | feito |
| F6 Dados | converter os 6 contatos de teste inativos da Ecoprint (D7) | depois do deploy da 0045 na dev |

Decisões de implementação:

- **Excluir também desliga o `ativo`** onde a tabela o tem: todo filtro "só
  ativos" que já existia esconde o excluído sem mudança; o filtro explícito de
  `excluido_em` só entrou onde inativos aparecem (listas de gestão), onde se
  edita ou reativa, e nas tabelas sem `ativo`.
- **A confirmação é do servidor**: `ExcluirMyItem` exige `confirmar` igual ao
  rótulo do item, e o `dry_run` devolve esse rótulo. App e MCP usam o mesmo
  caminho, e um id errado não exclui outra coisa.
- **Conexão** continua pelo `DeleteMyWhatsappInstance` (apaga no provedor antes
  e depois marca a linha como excluída).
- **`.sqlx`** regenerado pelo workflow `sqlx-prepare.yml` (commit com
  `[sqlx-prepare]`), com `-- --all-targets` para incluir as consultas dos testes.
- **Stubs Dart** gerados com `protoc_plugin 25.0.0`, a versão que reproduz os
  atuais sem diferença (Dart SDK em `/opt/dart-sdk`, só para isso — D9).

Fica para depois: botão de excluir etiqueta e conversa no app (hoje só pelo
MCP), e a reativação de etapa/departamento pelo app (as listas dessas duas
mostram só ativos; a volta existe no servidor via `DefinirMyItemAtivo`).
