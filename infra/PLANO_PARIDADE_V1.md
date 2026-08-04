# Plano — paridade funcional com a v1 e Kanban próprio

Levantado em 03/08/2026 varrendo `old/smart-core-assistant-painel/` (urls, views,
models) e comparando com as telas e tabelas do v2. Tudo aqui foi **verificado no
código**, não inferido.

## Correção já feita nesta rodada

**O laço da configuração.** Ao concluir o roteiro, a tela gravava
`setup_completed` no servidor e navegava para `/atendimentos`, mas o
`PortaoConfiguracao` — que é quem o guard consulta — continuava dizendo
"pendente". O guard devolvia a tela para a configuração, e não havia como sair.
Defeito meu, introduzido junto com a retomada. Corrigido e coberto por teste.

O segundo sintoma relatado — "fila de atendimento vazia, sem menus" — **não é
bug**: é a lacuna que este plano endereça. O workspace do v2 tem duas telas
(chat e kanban); o tenant-admin da v1 tem quinze.

---

## O que a v1 tem e o v2 não

Levantado das `urls.py` de cada app. Marcado com ⚠️ o que impede operar.

### Tenant-admin (`app/tenants/urls.py` — 23 rotas)

| v1 | v2 | falta |
|---|---|---|
| `dashboard` | — | ⚠️ painel do tenant: volume, filas, instâncias |
| `config_ai` | parcial (`tenant_own_config`) | conferir paridade de campos |
| `config_evolution` | — | ⚠️ gestão das conexões de WhatsApp |
| `config_trello` | — | substituído pelo Kanban próprio (ver adiante) |
| `config_database` | — | **não migra**: base unificada (ver "Decisão de arquitetura") |
| `config_debug` | — | baixa prioridade |
| `user_list`, `user_invite`, `user_permissions` | ✅ `tenant_users`, `invites` | — |
| `backoffice_dashboard`, `backoffice_register_payment` | ✅ `admin_module/billing` | — |
| `signup`, `activate_account` | ✅ `onboarding_module` | — |

### Evolution / WhatsApp (`app/evolution_sync/urls.py` — 19 rotas)

⚠️ **Nada disso existe no v2 fora do onboarding.** Depois de conectado, o tenant
não tem como ver, reconectar ou trocar a instância.

`instance_list`, `instance_detail`, `instance_create`, `instance_update`,
`instance_delete`, `instance_qrcode`, `instance_status`, `instance_logout`,
`instance_refresh_all`, `instance_toggle_bot`, `instance_webhook`,
`department_list`, `department_create`, `attendant_list`.

O servidor já tem os RPCs de instância (`data_whatsapp`); falta expor
departamento/atendente e construir as telas.

### Treinamento (`app/treinamento/urls.py` — 6 telas)

| v1 | v2 |
|---|---|
| `treinar_ia`, `pre_processamento`, `verificar_treinamentos` | ✅ unificados em `treinamento_page` |
| `cadastrar_query_compose`, `verificar_query_compose` | ⚠️ falta |
| `testar_query` + `feedback_resposta` | ⚠️ falta |

### Operação (`app/operacional/models.py`, `app/clientes/models.py`)

Tabelas existem no v2 (`operacional/`, `clientes/` em `infrastructure_postgres`),
telas não:

- ⚠️ **Departamentos** — CRUD (hoje só o primeiro, no onboarding);
- ⚠️ **Atendentes** — vincular usuário a departamento;
- ⚠️ **Fluxos de atendimento + etapas** — `FluxoAtendimento`/`EtapaFluxo`. Sem
  CRUD, o limite `max_fluxos` do plano não morde em nada;
- ⚠️ **Clientes e contatos** — `Cliente`/`Contato`;
- ⚠️ **Campos personalizados, etiquetas, notas** — `CampoPersonalizado`,
  `atu_etiqueta`, `atu_nota`. A v1 tem painéis para os três no detalhe do
  atendimento.

---

## Decisão de arquitetura: base unificada

Na v1 **cada tenant tinha seu banco** (`config_database`, `run_migrations`,
`test_connection` são disso). O v2 é **base única com RLS por tenant** — já é o
desenho vigente, provado pelos testes de isolamento.

Consequência para este plano: as rotas de gestão de banco por tenant **não são
portadas**. Some `config_database`, `run_migrations`, `test_connection`.

## Decisão de produto: Kanban próprio, não sincronização

A v1 sincronizava com o Trello (`app/trello_sync/`: `TrelloBoard`, `TrelloList`,
`TrelloCard`, `TrelloMember`, `TrelloWebhookEvent` + webhooks). O v2 terá
**quadro próprio integrado ao WhatsApp** — o cartão nasce do atendimento, e não
de um espelho de um serviço externo.

Isso **elimina** `config_trello`, `register_trello_webhook`,
`delete_trello_webhook` e todo o `trello_sync`, e **acrescenta** o domínio do
quadro. O v2 já tem `kanban_page`; falta o modelo por trás.

---

## Etapas de execução

Ordem por dependência e por dano ao usuário. Cada etapa é entregável sozinha:
contrato → servidor → cliente → testes, e fecha com as duas suítes verdes.

### Etapa 1 — Operar o WhatsApp depois de conectado — FEITO (parcial)

Entregue: **lista de conexões com estado, reconectar e remover** — o essencial
para uma conexão que cai não deixar o tenant sem saída. Rota
`/tenant/conexoes`, no menu.

3 RPCs novos na fachada (`ListMyWhatsappInstances`,
`ReconnectMyWhatsappInstance`, `DeleteMyWhatsappInstance`); os handlers já
existiam no `data_whatsapp`, faltava só expor. 7 testes.

`unknown` é tratado como situação própria ("sem resposta"), não como
desconectada: não saber pede espera, estar fora pede ação — confundir os dois
mandaria o tenant reconectar uma conexão que talvez esteja boa.

**Falta desta etapa**, para uma segunda passada: ver o QR de uma conexão já
existente (hoje só no onboarding), ligar/desligar o bot por conexão, editar o
webhook, e renomear.

### Etapa 2 — Departamentos e atendentes — FEITO (parcial)

Rota `/tenant/equipe`, duas abas. Departamentos: listar, criar, editar e
desativar. Atendentes: listar, com o departamento de cada um.

As duas listas na mesma tela de propósito — departamento sem atendente e
atendente sem departamento são os dois problemas que travam a fila, e separá-los
esconderia a relação.

**Desativar, não apagar**: atendimentos e atendentes apontam para o
departamento, e remover a linha levaria histórico junto. O `slug` também não
muda ao renomear: é referência estável.

`ativo` e `disponivel` são estados distintos do atendente e ambos aparecem —
quem está de férias fica ativo e indisponível, e confundir os dois esconde por
que uma fila parou.

**Falta desta etapa**: criar/editar atendente e vincular a departamento. O
`oraculo_atendente` exige `fluxo_id` NOT NULL, e fluxos são a Etapa 5 — criar
atendente antes disso exigiria inventar um fluxo padrão, o que é decisão de
produto, não detalhe de implementação.

### Etapa 3 — Painel do tenant — FEITO

Rota `/tenant/painel`. Números do que exige ação agora (fila, em atendimento,
mensagens em 24h) e da estrutura (conexões ativas/total, departamentos,
material treinado).

Uma consulta só, com `FILTER`: cinco contagens do mesmo instante. Cinco
SELECTs mostrariam uma soma que nunca existiu.

Os avisos **levam à tela que resolve** — dizer o problema sem oferecer o
caminho deixaria a pessoa procurando no menu. E distinguem os dois casos que
parecem iguais nos números: `0 de 0` conexões é conta nova (convite a
conectar), `1 de 2` é queda (alerta vermelho).

Os status vieram do banco, não de palpite: o `oraculo_atendimento` usa o
vocabulário da v1 (`fila`, `em_atendimento`, `pendencia`, `resolvido`,
`cancelado`, `arquivado`) e a coluna de data da mensagem é `timestamp`. Escrevi
`data_envio` de memória e o `sqlx` recusou na compilação — é para isso que a
validação contra o banco real serve.

### Etapa 4 — Clientes e contatos

CRUD + histórico de atendimentos do contato. Alimenta o painel de detalhe do
atendimento.

### Etapa 5 — Fluxos de atendimento

`FluxoAtendimento` + `EtapaFluxo`. Depende de departamentos (etapa 2). Fecha o
enforce de `max_fluxos`, hoje medido e não aplicado.

### Etapa 6 — Kanban próprio integrado ao WhatsApp

O maior item, e o que difere do old por decisão de produto.

Modelo novo: quadro, coluna, cartão — o cartão referencia `oraculo_atendimento`,
que é o elo com o WhatsApp. Mover cartão é evento de negócio (auditado), e a
coluna pode disparar ação no fluxo.

Aproveita: `kanban_page` (existe), `atu_etiqueta`, `atu_nota`,
`CampoPersonalizado` (tabelas existem).

Precisa de decisão sua antes de começar: **o que move um cartão de coluna** —
só a mão do atendente, ou também o estado do atendimento/fluxo?

### Etapa 7 — Treinamento: intents e teste de resposta

`query_compose` (CRUD de intents) e `testar_query` com feedback. Fecha a
paridade do módulo que já entreguei pela metade.

Também precisa de decisão: o RAG do v2 já consulta `treinamento_querycompose`
na composição de contexto, mas a **curadoria manual** de intents pode ter sido
absorvida pelo `ia_engine`.

### Etapa 8 — Detalhe do atendimento

Painéis de campos personalizados, etiquetas e notas (a v1 tem os três em
`gestao_kanban/partials/`). Depende das etapas 4 e 6.

---

## Como cada etapa é executada

Sempre nesta ordem, porque foi o que evitou retrabalho nas rodadas anteriores:

1. **contrato** — mensagens e RPCs no `.proto`;
2. **servidor** — repositório (queries validadas contra o banco real; regenerar
   o cache com `cargo sqlx prepare --workspace -- --all-targets`, conferindo que
   `git status server/.sqlx` não mostra deletados), port, adapter, handler com
   auditoria;
3. **fachada** — método concreto no `grpc_web.rs`. Sem ele o Flutter não alcança
   a rota, ainda que o `data_postgres` responda;
4. **stubs** — `server/bin/protoc.exe --dart_out=grpc:...`;
5. **cliente** — módulo no padrão RSOE, registrado no workspace, no bootstrap e
   no `test-flutter.ps1` (a lista de pacotes é fixa: módulo fora dela não é
   testado);
6. **testes** — domínio, tradução de erro e regressão do que já quebrou antes.

Armadilhas já pagas neste projeto, para não repetir: controllers de diálogo
pertencem ao `DialogoComCampos`; erro aparece dentro da janela, nunca em
SnackBar atrás do barrier; o `BuildContext` do item de lista não abre diálogo.

## Estimativa honesta

Oito etapas, cada uma com contrato+servidor+cliente+testes. **Não cabe numa
sessão** — nem em duas. A ordem acima é para que cada entrega deixe o sistema
mais usável que antes, e para que parar entre etapas não deixe nada pela metade.
