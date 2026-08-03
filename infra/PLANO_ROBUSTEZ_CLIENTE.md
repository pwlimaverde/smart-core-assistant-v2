# Plano — robustez do cliente e lacunas funcionais

Levantado em 02/08/2026 a partir de varredura do `clients/` e comparação com a
v1 (`old/smart-core-assistant-painel`). Cada item abaixo foi **verificado no
código**, não inferido.

## Ordem de execução

A ordem é por dano ao usuário, não por esforço.

### 1. Diálogos que não fecham e não avisam — FEITO

Diálogo aberto com o `BuildContext` do item de uma lista + operação que
recarrega a lista = o item desmonta antes da resposta, e o `if (context.mounted)`
engole o `Navigator.pop` **e** a mensagem. O usuário vê a janela parada, sem
saber se gravou.

- `billing_page` (edição de plano) — corrigido em `b33b0f4`
- `core_settings_page` (salvar e excluir) — corrigido em `eb84fe4`

Verificados e **sem** o defeito: `tenants_page` e `billing/_showPaymentDialog`
(usam `.map()` em método do State), `invites_page` (`dialogContext.mounted`),
`feature_flags` e demais (`mounted` do State).

### 2. Controllers sem `dispose` — vazamento

`TextEditingController` é `ChangeNotifier`: sem `dispose` os listeners ficam.

- **`accept_invite_page`** — 3 controllers como campos do State, nenhum
  `dispose`. Era o caso grave (vazava a cada abertura da tela). **FEITO.**
- Diálogos locais (`tenants_page` 5, `vouchers_tab` 5, `core_settings_page` 3,
  `invites_page` 3, `tenant_users_page` 1, `billing_page` 13): **FEITO.**

  Tentativa descartada no caminho: `showDialog(...).whenComplete(dispose)`
  **quebra**. O `whenComplete` dispara quando a rota é removida, mas a animação
  de saída ainda está em curso e os `TextField` continuam usando o controller —
  `A TextEditingController was used after being disposed`, 15 testes vermelhos.

  A solução foi um widget do design system, `DialogoComCampos`, que **possui**
  os controllers e os descarta no próprio `dispose` — dentro da rota do
  diálogo, que é quem sabe quando a árvore saiu de vez. Uma linha por diálogo
  em vez de seis refatorações, e dois testes fixam o comportamento, inclusive o
  caso que quebrava (descarte durante a animação) e o fechamento pelo barrier.

### 3. Feedback de erro invisível atrás do modal

`ScaffoldMessenger` chamado de dentro de um diálogo renderiza o SnackBar no
Scaffold **abaixo** do barrier — o usuário não vê. Já corrigido em
`billing_page` (erro dentro da janela); o mesmo padrão existe em
`tenants_page`, `invites_page` e `tenant_users_page`.

### 4. Módulo de treinamento — LACUNA FUNCIONAL, não bug

A v1 tem seis telas (`treinar_ia`, `verificar_treinamentos`,
`cadastrar_query_compose`, `verificar_query_compose`, `testar_query`,
`pre_processamento`). No v2:

- banco: `oraculo_treinamento`, `oraculo_documento`,
  `treinamento_querycompose`, `treinamento_query_test_feedback` — existem;
- servidor: `infrastructure_postgres/src/treinamento/` e
  `data_postgres/src/ports/treinamento.rs` — existem;
- **contrato: nenhum RPC**;
- **cliente: nenhuma tela**.

Há fundação e não há caminho: **não existe forma de treinar o assistente pelo
sistema**. Num produto que vende um assistente, é a feature central.

Escopo real: RPCs no `admin.proto` (listar/criar/remover treinamento, upload de
documento, CRUD de query compose, testar query), handlers no `data_postgres`,
métodos concretos na fachada gRPC-Web, regeneração dos stubs Dart e um
`treinamento_module` com as telas. **Trabalho de dias, não de uma sessão** —
merece planejamento próprio, com decisão de produto sobre quais das seis telas
da v1 valem no v2.

## Fora do escopo desta varredura

Não foram analisados de forma sistemática, e não devem ser dados como sãos:

- estados vazios e de erro das 14 telas, uma a uma;
- validação de formulários (hoje há checagens ad-hoc por tela);
- paridade de `kanban`/`chat` com a v1 (a v1 tem painéis de campos
  personalizados, etiquetas e detalhe cuja existência no v2 não foi conferida);
- acessibilidade e navegação por teclado.

## Nota de método

Os handlers do servidor **só logam em erro**. Isso atrasou dois diagnósticos
nesta rodada: quando o caminho funciona, não há rastro para confirmar. Vale um
INFO nos handlers do onboarding.
